#!/usr/bin/env bash
# Upload flattened repo/ as a GitHub Release. Tag is repo-<UTC stamp>, not a
# single package version — the db holds every allowlisted package.
# latest/download then serves company.db + packages. Requires gh + curl + GH_TOKEN.
# Call from Actions after build-repo.sh; do not run on pull_request.
#
# Do not pass the packages to `gh release create` in one shot. That command
# creates a draft, uploads every asset with no progress, then publishes. A
# stalled HTTP/2 upload looks like a hang and leaves an untagged draft that
# pacman cannot see. Create the draft via the API, POST each file to
# uploads.github.com over HTTP/1.1, then publish.
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"
command -v gh >/dev/null || { echo "need gh (github-cli)" >&2; exit 1; }
command -v curl >/dev/null || { echo "need curl" >&2; exit 1; }
[[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] || { echo "need GH_TOKEN" >&2; exit 1; }
export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

bash "$ROOT/scripts/flatten-repo-for-http.sh"

company_load_gate

stamp=$(date -u +%Y%m%dT%H%M%SZ)
tag="repo-${stamp}"
[[ -n "${GITHUB_RUN_ID:-}" ]] && tag="${tag}.${GITHUB_RUN_ID}"

lines=()
for name in "${company_pkgs[@]}"; do
  pkg=$(company_pkgbuild_file "$name")
  ver=$(company_pkgbuild_get "$pkg" pkgver)
  rel=$(company_pkgbuild_get "$pkg" pkgrel)
  lines+=("- ${name} ${ver}-${rel:-1}")
done

mapfile -t files < <(find "$ROOT/repo" -maxdepth 1 -type f \( \
  -name 'company.db' -o -name 'company.db.sig' \
  -o -name 'company.files' -o -name 'company.files.sig' \
  -o -name 'company-arch-packages.asc' \
  -o -name '*.pkg.tar.zst' -o -name '*.pkg.tar.zst.sig' \) | sort)
[[ ${#files[@]} -gt 0 ]] || { echo "nothing to upload" >&2; exit 1; }

nwo="${GITHUB_REPOSITORY:-}"
[[ "$nwo" == */* ]] || company_fail "GITHUB_REPOSITORY is not set (got ${nwo:-empty})"
notes="Signed [company] pacman repo.

Packages:
$(printf '%s\n' "${lines[@]}")

Pacman GETs company.db from this release; it does not clone git.
Server = https://github.com/${nwo}/releases/latest/download"

create_args=(
  -f tag_name="$tag"
  -f name="company ${tag}"
  -f body="$notes"
  -F draft=true
)
[[ -n "${GITHUB_SHA:-}" ]] && create_args+=(-f target_commitish="$GITHUB_SHA")

echo "creating draft release $tag"
id=$(gh api "repos/${nwo}/releases" "${create_args[@]}" --jq .id)
[[ "$id" =~ ^[0-9]+$ ]] || company_fail "could not create draft release (id=$id)"
echo "draft release id=$id tag=$tag"

upload_one() {
  local file=$1 name size attempt resp
  name=$(basename "$file")
  size=$(wc -c <"$file")
  size=$(company_trim "$size")
  resp=$(mktemp)
  for attempt in 1 2 3; do
    printf 'upload %s (%s bytes) attempt %s/3\n' "$name" "$size" "$attempt"
    if curl -sS -fL --http1.1 \
      --connect-timeout 30 \
      --max-time 600 \
      --speed-limit 1024 \
      --speed-time 120 \
      -H "Authorization: Bearer ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @"$file" \
      -w "  http %{http_code} uploaded %{size_upload} bytes in %{time_total}s\n" \
      -o "$resp" \
      "https://uploads.github.com/repos/${nwo}/releases/${id}/assets?name=${name}"; then
      rm -f "$resp"
      return 0
    fi
    printf 'upload failed %s attempt %s/3\n' "$name" "$attempt" >&2
    sleep $((attempt * 5))
  done
  rm -f "$resp"
  return 1
}

for file in "${files[@]}"; do
  upload_one "$file" || company_fail \
    "upload failed for $(basename "$file"); draft id=$id tag=$tag is unpublished (pacman cannot see it)"
done

echo "publishing release id=$id"
html=$(gh api -X PATCH "repos/${nwo}/releases/${id}" -F draft=false --jq .html_url)
echo "published $html"
echo "Server = https://github.com/${nwo}/releases/latest/download"
printf '  %s\n' "${files[@]}"

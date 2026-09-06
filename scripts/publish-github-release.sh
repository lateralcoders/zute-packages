#!/usr/bin/env bash
# Upload flattened repo/ as a GitHub Release. Tag is repo-<UTC stamp>, not a
# single package version — the db holds every allowlisted package.
# latest/download then serves company.db + packages. Requires gh + GH_TOKEN.
# Call from Actions after build-repo.sh; do not run on pull_request.
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"
command -v gh >/dev/null || { echo "need gh (github-cli)" >&2; exit 1; }
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

nwo="${GITHUB_REPOSITORY:-OWNER/REPO}"
notes="Signed [company] pacman repo.

Packages:
$(printf '%s\n' "${lines[@]}")

Pacman GETs company.db from this release; it does not clone git.
Server = https://github.com/${nwo}/releases/latest/download"

if gh release view "$tag" >/dev/null 2>&1; then
  gh release upload "$tag" --clobber "${files[@]}"
  echo "updated release $tag"
else
  gh release create "$tag" --title "company ${tag}" --notes "$notes" "${files[@]}"
  echo "created release $tag"
fi
echo "Server = https://github.com/${nwo}/releases/latest/download"
printf '  %s\n' "${files[@]}"

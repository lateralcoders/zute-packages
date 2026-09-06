#!/usr/bin/env bash
# Upload flattened repo/ as a GitHub Release. Tag = v<keeper pkgver>.
# latest/download then serves company.db + packages. Requires gh + GH_TOKEN.
# Call from Actions after build-repo.sh; do not run on pull_request.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v gh >/dev/null || { echo "need gh (github-cli)" >&2; exit 1; }
[[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] || { echo "need GH_TOKEN" >&2; exit 1; }
export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

bash "$ROOT/scripts/flatten-repo-for-http.sh"

ver=$(awk -F= '/^pkgver=/ {gsub(/["'\'']/,"",$2); print $2; exit}' \
  "$ROOT/packages/keeper-password-manager/PKGBUILD")
rel=$(awk -F= '/^pkgrel=/ {gsub(/["'\'']/,"",$2); print $2; exit}' \
  "$ROOT/packages/keeper-password-manager/PKGBUILD")
[[ -n "$ver" ]] || { echo "could not read keeper pkgver" >&2; exit 1; }
tag="v${ver}"
[[ -n "$rel" && "$rel" != "1" ]] && tag="v${ver}-${rel}"

mapfile -t files < <(find "$ROOT/repo" -maxdepth 1 -type f \( \
  -name 'company.db' -o -name 'company.db.sig' \
  -o -name 'company.files' -o -name 'company.files.sig' \
  -o -name 'company-arch-packages.asc' \
  -o -name '*.pkg.tar.zst' -o -name '*.pkg.tar.zst.sig' \) | sort)
[[ ${#files[@]} -gt 0 ]] || { echo "nothing to upload" >&2; exit 1; }

nwo="${GITHUB_REPOSITORY:-OWNER/REPO}"
notes="Signed [company] pacman repo (keeper-password-manager ${ver}-${rel:-1}).
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

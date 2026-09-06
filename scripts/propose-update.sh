#!/usr/bin/env bash
# Bump packages/<name>/PKGBUILD pkgver + sha256sums from that package's vendor
# checksums. Does not commit. Default: every allowlisted name.
#   scripts/propose-update.sh
#   scripts/propose-update.sh keeper-password-manager
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"

company_load_gate

in_allowlist() {
  local want=$1 n
  for n in "${company_pkgs[@]}"; do
    [[ "$n" == "$want" ]] && return 0
  done
  return 1
}

propose_one() {
  local name=$1
  local pkg up sums_url sums_glob version_regex tmp latest cur sha want
  in_allowlist "$name" || company_fail "$name is not in allowlist.txt"
  pkg=$(company_pkgbuild_file "$name")
  up=$(company_upstream_file "$name")
  sums_url=$(company_kv_get "$up" sums_url)
  sums_glob=$(company_kv_get "$up" sums_glob)
  version_regex=$(company_kv_get "$up" version_regex)

  tmp=$(mktemp)
  company_fetch "$sums_url" "$tmp" || {
    rm -f "$tmp"
    company_fail "$name: could not fetch $sums_url"
  }
  latest=$(company_versions_from_sums "$tmp" "$version_regex" | tail -n1)
  [[ -n "$latest" ]] || {
    rm -f "$tmp"
    company_fail "$name: no versions matched version_regex in checksums"
  }
  want=$(company_expand_glob "$sums_glob" "$latest")
  sha=$(company_sums_hash_for "$tmp" "$want") || {
    rm -f "$tmp"
    company_fail "$name: latest $latest ($want) has no sha256 line"
  }
  rm -f "$tmp"
  [[ ${#sha} -eq 64 ]] || company_fail "$name: parse failed for $want"

  cur=$(company_pkgbuild_get "$pkg" pkgver)
  if [[ "$cur" == "$latest" ]]; then
    printf 'CURRENT %s %s\n' "$name" "$latest"
    return 0
  fi

  sed -i "s/^pkgver=.*/pkgver=$latest/" "$pkg"
  sed -i "s/^pkgrel=.*/pkgrel=1/" "$pkg"
  sed -i "s/^sha256sums=.*/sha256sums=('${sha,,}')/" "$pkg"

  printf 'UPDATED %s %s -> %s\n' "$name" "$cur" "$latest"
  printf 'next: git checkout -b bump-%s-%s && git add packages/%s/PKGBUILD && git commit && gh pr create\n' \
    "$name" "$latest" "$name"
}

names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  names=("${company_pkgs[@]}")
fi

for name in "${names[@]}"; do
  company_valid_pkgname "$name" || company_fail "not a pkgname: $name"
  propose_one "$name"
done

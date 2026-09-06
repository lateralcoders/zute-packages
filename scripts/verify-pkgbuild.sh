#!/usr/bin/env bash
# Fail closed: allowlisted names have PKGBUILD + upstream; extra package dirs
# fail; each source= host and sha256 match that package's vendor checksums.
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"

company_load_gate

hostile() {
  local block=$1
  echo "$block" | grep -qE 'curl|\|[[:space:]]*bash|wget ' && return 0
  echo "$block" | grep -qE 'http://' && return 0
  return 1
}

verify_one() {
  local name=$1
  local pkg up host pkgver sha source_block url count src_host want vendor
  pkg=$(company_pkgbuild_file "$name")
  up=$(company_upstream_file "$name")
  host=$(company_kv_get "$up" host)

  pkgver=$(company_pkgbuild_get "$pkg" pkgver)
  sha=$(company_pkgbuild_get "$pkg" sha256sums)
  [[ -n "$pkgver" ]] || company_fail "$name: missing pkgver="
  [[ "$pkgver" != "0.0.0" ]] || company_fail "$name: pkgver still placeholder — run scripts/propose-update.sh $name"
  [[ "$sha" =~ ^[0-9a-fA-F]{64}$ ]] || company_fail "$name: sha256sums must be exactly one 64-hex digest (not SKIP)"

  mapfile -t urls < <(company_source_urls "$pkg")
  count=${#urls[@]}
  [[ "$count" -eq 1 ]] || company_fail "$name: expected exactly one https source= URL, found $count"
  url=${urls[0]}
  src_host=$(company_url_host "$url")
  company_host_ok "$src_host" "$host" || company_fail "$name: source= host $src_host is not $host"

  source_block=$(awk '/^source=/, /\)/' "$pkg")
  hostile "$source_block" && company_fail "$name: source= looks hostile"

  local sums_url sums_glob tmp
  sums_url=$(company_kv_get "$up" sums_url)
  sums_glob=$(company_kv_get "$up" sums_glob)
  tmp=$(mktemp)
  company_fetch "$sums_url" "$tmp" || {
    rm -f "$tmp"
    company_fail "$name: could not fetch $sums_url"
  }
  want=$(company_expand_glob "$sums_glob" "$pkgver")
  vendor=$(company_sums_hash_for "$tmp" "$want") || {
    rm -f "$tmp"
    company_fail "$name: version $pkgver ($want) not in vendor checksums"
  }
  rm -f "$tmp"
  [[ "${sha,,}" == "${vendor,,}" ]] || company_fail "$name: PKGBUILD sha256 $sha != vendor $vendor"

  printf 'OK %s %s sha256=%s\n' "$name" "$pkgver" "${sha,,}"
}

for name in "${company_pkgs[@]}"; do
  verify_one "$name"
done

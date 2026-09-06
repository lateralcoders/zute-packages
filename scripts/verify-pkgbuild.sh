#!/usr/bin/env bash
# Fail closed: every allowlisted name has a PKGBUILD; Keeper may only fetch
# the vendor URL and hash from SHASUM256.txt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW="$ROOT/allowlist.txt"
SUMS_URL="https://keepersecurity.com/desktop_electron/SHASUM256.txt"
HOST_OK='keepersecurity.com'

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$ALLOW")
[[ ${#pkgs[@]} -gt 0 ]] || fail "allowlist empty"

for name in "${pkgs[@]}"; do
  [[ -f "$ROOT/packages/$name/PKGBUILD" ]] || fail "no PKGBUILD for $name"
done

grep -qx 'keeper-password-manager' "$ALLOW" || fail "package not in allowlist"
PKG="$ROOT/packages/keeper-password-manager/PKGBUILD"

pkgver=$(awk -F= '/^pkgver=/ {gsub(/["'\'']/,"",$2); print $2; exit}' "$PKG")
source_line=$(awk -F= '/^source=/ {print; exit}' "$PKG")
sha=$(awk -F= '/^sha256sums=/ {gsub(/[("'\'' )]/,"",$2); print $2; exit}' "$PKG")

[[ "$pkgver" != "0.0.0" ]] || fail "pkgver still placeholder — run propose-keeper-update.sh"
[[ "$source_line" == *"$HOST_OK"* ]] || fail "source= host is not $HOST_OK"
echo "$source_line" | grep -qE 'curl|\| *bash|http://' && fail "source looks hostile"
[[ "$sha" != "SKIP" && ${#sha} -eq 64 ]] || fail "sha256sums missing or SKIP"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$SUMS_URL" -o "$tmp"
vendor=$(awk -v v="$pkgver" '$2 ~ "keeperpasswordmanager_" v "_amd64.deb$" {print $1; exit}' "$tmp")
[[ -n "$vendor" ]] || fail "version $pkgver not in vendor SHASUM256.txt"
[[ "$sha" == "$vendor" ]] || fail "PKGBUILD sha256 $sha != vendor $vendor"

src_count=$(grep -cE 'source=\(.*https://' "$PKG" || true)
[[ "$src_count" -eq 1 ]] || fail "expected exactly one source= URL in PKGBUILD, found $src_count"

printf 'OK keeper-password-manager %s sha256=%s\n' "$pkgver" "$sha"

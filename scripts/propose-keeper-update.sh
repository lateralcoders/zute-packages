#!/usr/bin/env bash
# Fill or bump packages/keeper-password-manager/PKGBUILD from Keeper's checksum file.
# Does not commit. CI / a human opens the PR.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/keeper-password-manager/PKGBUILD"
SUMS_URL="https://keepersecurity.com/desktop_electron/SHASUM256.txt"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$SUMS_URL" -o "$tmp"

# Latest amd64 deb line in the file (Keeper lists current builds)
line=$(grep -E 'keeperpasswordmanager_[0-9.]+_amd64\.deb$' "$tmp" | tail -n1)
[[ -n "$line" ]] || { echo "no amd64 deb in SHASUM256.txt" >&2; exit 1; }
sha=$(awk '{print $1}' <<<"$line")
file=$(awk '{print $2}' <<<"$line")
file=${file#\*}
ver=$(sed -n 's/.*keeperpasswordmanager_\([0-9.]*\)_amd64.deb/\1/p' <<<"$file")
[[ -n "$ver" && ${#sha} -eq 64 ]] || { echo "parse failed: $line" >&2; exit 1; }

cur=$(awk -F= '/^pkgver=/ {print $2; exit}' "$PKG")
if [[ "$cur" == "$ver" ]]; then
  echo "already $ver"
  exit 0
fi

sed -i "s/^pkgver=.*/pkgver=$ver/" "$PKG"
sed -i "s/^pkgrel=.*/pkgrel=1/" "$PKG"
sed -i "s/^sha256sums=.*/sha256sums=('$sha')/" "$PKG"

echo "updated $cur -> $ver"
echo "vendor: $line"
echo "next: git checkout -b keeper-$ver && git add packages/keeper-password-manager/PKGBUILD && git commit && gh pr create"

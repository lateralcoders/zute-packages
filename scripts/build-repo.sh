#!/usr/bin/env bash
# Build every allowlisted package, GPG-sign, repo-add --sign.
# Requires: scripts/init-signing-key.sh already run; makepkg; repo-add.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW="$ROOT/allowlist.txt"
export GNUPGHOME="${GNUPGHOME:-$ROOT/.gnupg}"
[[ -d "$GNUPGHOME" ]] || { echo "run scripts/init-signing-key.sh first" >&2; exit 1; }
fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$fpr" ]] || { echo "no signing key in $GNUPGHOME" >&2; exit 1; }

command -v makepkg >/dev/null || { echo "need makepkg (pacman -S --needed base-devel)" >&2; exit 1; }
command -v repo-add >/dev/null || { echo "need repo-add (pacman)" >&2; exit 1; }

mkdir -p "$ROOT/repo"
# Drop stale db so repo-add is a full rebuild of allowlisted packages.
rm -f "$ROOT/repo"/company.db* "$ROOT/repo"/company.files* "$ROOT/repo"/*.pkg.tar.*

mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$ALLOW")
[[ ${#pkgs[@]} -gt 0 ]] || { echo "allowlist empty" >&2; exit 1; }

export PACKAGER="${PACKAGER:-Company Arch Packages <packages@localhost>}"
export GPGKEY="$fpr"

for name in "${pkgs[@]}"; do
  dir="$ROOT/packages/$name"
  [[ -f "$dir/PKGBUILD" ]] || { echo "missing $dir/PKGBUILD" >&2; exit 1; }
  (
    cd "$dir"
    rm -rf src pkg
    makepkg -f --clean --sign --key "$fpr"
    mv -f ./*.pkg.tar.zst "$ROOT/repo/"
    mv -f ./*.pkg.tar.zst.sig "$ROOT/repo/"
  )
done

repo-add --sign --key "$fpr" "$ROOT/repo/company.db.tar.gz" "$ROOT/repo"/*.pkg.tar.zst
echo "repo $ROOT/repo"
ls -l "$ROOT/repo"

#!/usr/bin/env bash
# Build every allowlisted package, GPG-sign, repo-add --sign.
# Requires: scripts/init-signing-key.sh already run; makepkg; repo-add.
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"
export GNUPGHOME="${GNUPGHOME:-$ROOT/.gnupg}"
[[ -d "$GNUPGHOME" ]] || { echo "run scripts/init-signing-key.sh first" >&2; exit 1; }
fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$fpr" ]] || { echo "no signing key in $GNUPGHOME" >&2; exit 1; }

command -v makepkg >/dev/null || { echo "need makepkg (pacman -S --needed base-devel)" >&2; exit 1; }
command -v repo-add >/dev/null || { echo "need repo-add (pacman)" >&2; exit 1; }

mkdir -p "$ROOT/repo"
# Drop stale db so repo-add is a full rebuild of allowlisted packages.
rm -f "$ROOT/repo"/company.db* "$ROOT/repo"/company.files* "$ROOT/repo"/*.pkg.tar.*

company_load_gate

export PACKAGER="${PACKAGER:-Company Arch Packages <packages@localhost>}"
export GPGKEY="$fpr"

if grep -q "makedepends=('cargo')" "$ROOT"/packages/*/PKGBUILD; then
  command -v cargo >/dev/null || { echo "need cargo (pacman -S rust); shurectl builds from source" >&2; exit 1; }
  ldconfig -p 2>/dev/null | grep -q 'libasound.so.2' || { echo "need alsa-lib; shurectl links libasound" >&2; exit 1; }
fi

for name in "${company_pkgs[@]}"; do
  dir="$ROOT/packages/$name"
  [[ -f "$dir/PKGBUILD" ]] || { echo "missing $dir/PKGBUILD" >&2; exit 1; }
  (
    cd "$dir"
    rm -rf src pkg
    # --nodeps: depends= are for the laptop (gtk3, nss, alsa-lib, …), not this builder.
    # Deb/rpm packages only unpack. shurectl runs cargo, so rust and alsa-lib
    # must already be installed (publish.yml does that).
    makepkg -f --clean --nodeps --sign --key "$fpr"
    mv -f ./*.pkg.tar.zst "$ROOT/repo/"
    mv -f ./*.pkg.tar.zst.sig "$ROOT/repo/"
  )
done

repo-add --sign --key "$fpr" "$ROOT/repo/company.db.tar.gz" "$ROOT/repo"/*.pkg.tar.zst
echo "repo $ROOT/repo"
ls -l "$ROOT/repo"

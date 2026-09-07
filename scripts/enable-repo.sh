#!/usr/bin/env bash
# Import the public signing key and enable [company] on this machine.
# Default Server= is GitHub Releases (HTTPS). Does not TrustAll.
# Run as root (or via sudo).
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"
ASC="$ROOT/keys/company-arch-packages.asc"
CONF_SRC="$ROOT/pacman-company.conf.example"
ASC_TMP=""
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
cleanup() { [[ -n "$ASC_TMP" ]] && rm -f "$ASC_TMP"; }
trap cleanup EXIT

if server=$(company_repo_server); then
  :
else
  echo "set git remote origin to github.com/OWNER/REPO, COMPANY_REPO_SERVER=, or $ROOT/repo-server" >&2
  echo "  https://github.com/OWNER/REPO/releases/latest/download" >&2
  echo "USB copy: write-stick.sh writes repo-server. Local test: sudo COMPANY_REPO_SERVER=file://$ROOT/repo $0" >&2
  exit 1
fi

if [[ ! -f "$ASC" ]]; then
  [[ "$server" == https://* ]] || {
    echo "missing $ASC (needed for file:// Server=)" >&2
    exit 1
  }
  ASC_TMP=$(mktemp)
  curl -fsSL "$server/company-arch-packages.asc" -o "$ASC_TMP" || {
    echo "missing $ASC and could not GET $server/company-arch-packages.asc" >&2
    echo "commit the public key from init-signing-key.sh, or wait for the first GitHub Release" >&2
    exit 1
  }
  ASC=$ASC_TMP
fi

fpr=$(gpg --show-keys --with-colons "$ASC" | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$fpr" ]] || { echo "could not read fingerprint from $ASC" >&2; exit 1; }

pacman-key --add "$ASC"
pacman-key --lsign-key "$fpr"

dest=/etc/pacman.d/company.conf
sed "s|@SERVER@|$server|" "$CONF_SRC" >"$dest"
if ! grep -q 'Include = /etc/pacman.d/company.conf' /etc/pacman.conf; then
  printf '\nInclude = /etc/pacman.d/company.conf\n' >>/etc/pacman.conf
fi
pacman -Sy --noconfirm
echo "enabled [company] SigLevel Required, key $fpr"
echo "Server = $server"
if [[ -f "$ALLOW" ]]; then
  mapfile -t _pkgs < <(company_allowlist)
  if [[ ${#_pkgs[@]} -gt 0 ]]; then
    echo "next: pacman -S ${_pkgs[*]}"
  fi
else
  echo "next: pacman -Sy && pacman -Sl company"
fi

#!/usr/bin/env bash
# Create a repo-local signing key and export the public half to keys/.
# Does not upload anything. Private key stays in .gnupg/ (gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GNUPGHOME="$ROOT/.gnupg"
NAME="${COMPANY_PACKAGES_NAME:-Company Arch Packages}"
EMAIL="${COMPANY_PACKAGES_EMAIL:-packages@localhost}"
umask 077
mkdir -p "$GNUPGHOME" "$ROOT/keys"
chmod 700 "$GNUPGHOME"

if gpg --list-secret-keys --with-colons | grep -q '^sec:'; then
  echo "secret key already exists in $GNUPGHOME"
else
  gpg --batch --passphrase "" --pinentry-mode loopback \
    --quick-generate-key "$NAME <$EMAIL>" ed25519 sign 3y
fi

fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$fpr" ]] || { echo "no fingerprint" >&2; exit 1; }
gpg --armor --export "$fpr" >"$ROOT/keys/company-arch-packages.asc"
printf '%s\n' "$fpr" >"$ROOT/keys/fingerprint.txt"
echo "public key keys/company-arch-packages.asc"
echo "fingerprint $fpr"
echo "GNUPGHOME=$GNUPGHOME"

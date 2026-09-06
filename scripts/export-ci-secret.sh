#!/usr/bin/env bash
# One-time: put the signing secret in GitHub Actions. Never commit it.
#   ./scripts/init-signing-key.sh
#   git add keys/ && git commit   # public half only
#   ./scripts/export-ci-secret.sh --set
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GNUPGHOME="${GNUPGHOME:-$ROOT/.gnupg}"
[[ -d "$GNUPGHOME" ]] || { echo "run scripts/init-signing-key.sh first" >&2; exit 1; }
fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$fpr" ]] || { echo "no secret key in $GNUPGHOME" >&2; exit 1; }

if [[ "${1:-}" != "--set" ]]; then
  cat >&2 <<EOF
Refusing to print the private key. Pipe it into GitHub with:

  $0 --set

That runs: gpg --export-secret-keys | gh secret set GPG_SECRET_KEY
Commit keys/company-arch-packages.asc and keys/fingerprint.txt first.
Optional: gh secret set GPG_PASSPHRASE   (only if the key has a passphrase;
init-signing-key.sh creates an empty one.)
EOF
  exit 1
fi

command -v gh >/dev/null || { echo "need gh (github-cli), authenticated to this repo" >&2; exit 1; }
git -C "$ROOT" remote get-url origin >/dev/null || {
  echo "set git remote origin so gh knows which repo gets the secret" >&2
  exit 1
}
gpg --armor --export-secret-keys "$fpr" | gh secret set GPG_SECRET_KEY
echo "set GPG_SECRET_KEY on $(git -C "$ROOT" remote get-url origin)"
echo "fingerprint $fpr — public key must already be in keys/"

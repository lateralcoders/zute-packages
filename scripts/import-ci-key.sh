#!/usr/bin/env bash
# Import GPG_SECRET_KEY into GNUPGHOME for Actions. Must run as the builder user.
# Does not run on pull_request — the workflow must not pass this secret to forks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -n "${GPG_SECRET_KEY:-}" ]] || {
  echo "GPG_SECRET_KEY is empty. One-time: ./scripts/init-signing-key.sh && ./scripts/export-ci-secret.sh --set" >&2
  exit 1
}

export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
install -d -m 700 "$GNUPGHOME"

printf '%s\n' "$GPG_SECRET_KEY" | gpg --batch --import
cat >>"$GNUPGHOME/gpg.conf" <<'EOF'
batch
pinentry-mode loopback
use-agent
EOF
cat >>"$GNUPGHOME/gpg-agent.conf" <<'EOF'
allow-loopback-pinentry
allow-preset-passphrase
default-cache-ttl 86400
max-cache-ttl 86400
EOF
gpgconf --kill gpg-agent >/dev/null 2>&1 || true

fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$fpr" ]] || { echo "import produced no secret key" >&2; exit 1; }

expected_file="$ROOT/keys/fingerprint.txt"
[[ -f "$expected_file" && -f "$ROOT/keys/company-arch-packages.asc" ]] || {
  echo "missing keys/fingerprint.txt or keys/company-arch-packages.asc — run init-signing-key.sh and commit keys/ before publishing" >&2
  exit 1
}
expected=$(tr -d '[:space:]' <"$expected_file")
[[ "$fpr" == "$expected" ]] || {
  echo "CI secret fingerprint $fpr != committed $expected" >&2
  exit 1
}

if [[ -n "${GPG_PASSPHRASE:-}" ]]; then
  grip=$(gpg --list-secret-keys --with-keygrip --with-colons | awk -F: '/^grp:/{print $10; exit}')
  [[ -n "$grip" ]] || { echo "no keygrip" >&2; exit 1; }
  preset=/usr/lib/gnupg/gpg-preset-passphrase
  [[ -x $preset ]] || { echo "missing $preset" >&2; exit 1; }
  printf '%s' "$GPG_PASSPHRASE" | "$preset" --preset --passphrase-fd 0 "$grip"
fi

printf '%s\n' "$fpr" >"${FPR_OUT:-$HOME/fpr}"
echo "imported $fpr"

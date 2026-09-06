# Signing key

`scripts/init-signing-key.sh` creates a **repo-local** GnuPG home at `../.gnupg/` (gitignored) and writes the **public** key here as `company-arch-packages.asc` plus `fingerprint.txt`.

Private key never goes in git. One-time into Actions:

```bash
./scripts/export-ci-secret.sh --set
```

That is `gpg --export-secret-keys | gh secret set GPG_SECRET_KEY`. CI `publish.yml` imports it as the builder user, checks the fingerprint against `fingerprint.txt`, signs packages, and uploads a GitHub Release. PRs do not get this secret.

On each Omarchy laptop, `scripts/enable-repo.sh` does:

```bash
sudo pacman-key --add keys/company-arch-packages.asc
sudo pacman-key --lsign-key "$(gpg --show-keys --with-colons keys/company-arch-packages.asc | awk -F: '/^fpr:/{print $10; exit}')"
```

plus installs `[company]` with `SigLevel = Required` and `Server=` GitHub Releases.

Do **not** use `TrustAll` for this repo, `[omarchy]`, or `[core]`.

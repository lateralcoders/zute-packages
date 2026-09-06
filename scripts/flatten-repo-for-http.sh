#!/usr/bin/env bash
# repo-add writes symlinks (company.db -> company.db.tar.gz). HTTP hosts
# (GitHub Releases, S3) have no symlinks. Copy the blobs to the names
# pacman GETs: company.db, company.db.sig, company.files, company.files.sig.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/repo"
cd "$REPO"
[[ -f company.db.tar.gz || -f company.db ]] || { echo "no company.db.tar.gz — run build-repo.sh" >&2; exit 1; }

materialize() {
  local src=$1 dest=$2
  if [[ -L $dest || ! -f $dest ]]; then
    rm -f "$dest"
  fi
  if [[ -f $src ]]; then
    cp -f "$src" "$dest"
  elif [[ -f $dest ]]; then
    :
  else
    echo "missing $src" >&2
    return 1
  fi
}

if [[ -f company.db.tar.gz ]]; then
  materialize company.db.tar.gz company.db
  [[ -f company.db.tar.gz.sig ]] && materialize company.db.tar.gz.sig company.db.sig
fi
if [[ -f company.files.tar.gz ]]; then
  materialize company.files.tar.gz company.files
  [[ -f company.files.tar.gz.sig ]] && materialize company.files.tar.gz.sig company.files.sig
fi

if [[ -n "${GNUPGHOME:-}" ]] && gpg --list-secret-keys >/dev/null 2>&1; then
  fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
  [[ -n "$fpr" ]] && gpg --armor --export "$fpr" >company-arch-packages.asc
elif [[ -f $ROOT/keys/company-arch-packages.asc ]]; then
  cp -f "$ROOT/keys/company-arch-packages.asc" company-arch-packages.asc
fi

for f in company.db company.db.sig company-arch-packages.asc; do
  [[ -f $f ]] || { echo "missing $f (unsigned repo cannot be Server= HTTPS)" >&2; exit 1; }
done
shopt -s nullglob
pkgs=(./*.pkg.tar.zst)
[[ ${#pkgs[@]} -gt 0 ]] || { echo "no .pkg.tar.zst in repo/" >&2; exit 1; }
for p in "${pkgs[@]}"; do
  [[ -f ${p}.sig ]] || { echo "unsigned $p" >&2; exit 1; }
done
ls -l company.db company.db.sig company-arch-packages.asc ./*.pkg.tar.zst ./*.pkg.tar.zst.sig

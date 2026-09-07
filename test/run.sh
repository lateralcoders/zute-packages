#!/usr/bin/env bash
# Gate tests: N packages, extra dirs, host/hash, propose. No makepkg.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../scripts/pkg-lib.sh
source "$REPO/scripts/pkg-lib.sh"

PASS=0
FAIL=0
ok() { printf 'ok  %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

expect_ok() {
  local msg=$1
  shift
  if "$@" >/tmp/cap-out 2>/tmp/cap-err; then
    ok "$msg"
  else
    bad "$msg (exit $?): $(tr '\n' ' ' </tmp/cap-err)"
  fi
}

expect_fail() {
  local msg=$1 needle=$2
  shift 2
  if "$@" >/tmp/cap-out 2>/tmp/cap-err; then
    bad "$msg (wanted failure)"
  elif [[ -n "$needle" ]] && ! grep -q "$needle" /tmp/cap-err; then
    bad "$msg (wanted '$needle' in stderr: $(tr '\n' ' ' </tmp/cap-err))"
  else
    ok "$msg"
  fi
}

if company_host_ok keepersecurity.com keepersecurity.com; then ok 'host exact'; else bad 'host exact'; fi
if company_host_ok download.keepersecurity.com keepersecurity.com; then ok 'host subdomain'; else bad 'host subdomain'; fi
if company_host_ok keepersecurity.com.evil.com keepersecurity.com; then bad 'host suffix injection'; else ok 'host suffix injection'; fi
if company_host_ok evilkeepersecurity.com keepersecurity.com; then bad 'host prefix injection'; else ok 'host prefix injection'; fi
if company_valid_pkgname keeper-password-manager; then ok 'pkgname ok'; else bad 'pkgname ok'; fi
if company_valid_pkgname '../etc'; then bad 'pkgname traversal'; else ok 'pkgname traversal'; fi
if company_valid_pkgname 'alpha'; then ok 'pkgname alpha'; else bad 'pkgname alpha'; fi

RS=$(mktemp -d)
printf 'https://github.com/example/repo/releases/latest/download\n' >"$RS/repo-server"
got=$(COMPANY_REPO_SERVER= company_repo_server "$RS" || true)
if [[ "$got" == 'https://github.com/example/repo/releases/latest/download' ]]; then
  ok 'repo-server file'
else
  bad "repo-server file: $got"
fi
got=$(COMPANY_REPO_SERVER='file:///tmp/repo' company_repo_server "$RS" || true)
if [[ "$got" == 'file:///tmp/repo' ]]; then
  ok 'COMPANY_REPO_SERVER overrides repo-server'
else
  bad "COMPANY_REPO_SERVER: $got"
fi
rm -rf "$RS"
EMPTY=$(mktemp -d)
if COMPANY_REPO_SERVER= company_repo_server "$EMPTY" >/dev/null 2>&1; then
  bad 'repo-server missing should fail'
else
  ok 'repo-server missing fails'
fi
rmdir "$EMPTY"

H64A=$(printf 'a%.0s' {1..64})
H64B=$(printf 'b%.0s' {1..64})
H64C=$(printf 'c%.0s' {1..64})
H64D=$(printf 'd%.0s' {1..64})

write_pkg() {
  local root=$1 name=$2 ver=$3 sha=$4 host=$5
  mkdir -p "$root/packages/$name" "$root/sums"
  cat >"$root/packages/$name/PKGBUILD" <<EOF
pkgname=$name
pkgver=$ver
pkgrel=1
arch=('x86_64')
source=("https://${host}/${name}_\${pkgver}.deb")
sha256sums=('$sha')
EOF
  cat >"$root/packages/$name/upstream" <<EOF
host=$host
sums_url=file://${root}/sums/${name}.txt
sums_glob=${name}_{pkgver}.deb
version_regex=${name}_([0-9.]+)\\.deb
EOF
}

write_allow() {
  local root=$1
  shift
  printf '%s\n' "$@" >"$root/allowlist.txt"
}

verify() {
  COMPANY_ALLOW_FILE_SUMS=1 COMPANY_ROOT="$1" bash "$REPO/scripts/verify-pkgbuild.sh"
}

propose() {
  COMPANY_ALLOW_FILE_SUMS=1 COMPANY_ROOT="$1" bash "$REPO/scripts/propose-update.sh" "${@:2}"
}

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

write_pkg "$FIX" alpha 1.0.0 "$H64A" vendor.example
write_pkg "$FIX" beta 2.0.0 "$H64C" other.example
printf '%s  %s\n' "$H64A" 'alpha_1.0.0.deb' "$H64B" 'alpha_1.2.0.deb' >"$FIX/sums/alpha.txt"
printf '%s  %s\n' "$H64C" 'beta_2.0.0.deb' >"$FIX/sums/beta.txt"
write_allow "$FIX" alpha beta

expect_ok 'two packages verify' verify "$FIX"

mkdir -p "$FIX/packages/evil"
write_pkg "$FIX" evil 0.1.0 "$H64D" evil.example
printf '%s  %s\n' "$H64D" 'evil_0.1.0.deb' >"$FIX/sums/evil.txt"
expect_fail 'extra package dir' 'not in allowlist' verify "$FIX"
rm -rf "$FIX/packages/evil"

cp "$FIX/packages/beta/upstream" "$FIX/packages/beta/upstream.bak"
rm -f "$FIX/packages/beta/upstream"
expect_fail 'missing upstream' 'missing packages/beta/upstream' verify "$FIX"
mv "$FIX/packages/beta/upstream.bak" "$FIX/packages/beta/upstream"

sed -i 's#https://vendor.example/#https://evil.example/#' "$FIX/packages/alpha/PKGBUILD"
expect_fail 'source host mismatch' 'source= host' verify "$FIX"
sed -i 's#https://evil.example/#https://vendor.example/#' "$FIX/packages/alpha/PKGBUILD"

sed -i "s/^sha256sums=.*/sha256sums=('$H64D')/" "$FIX/packages/alpha/PKGBUILD"
expect_fail 'hash mismatch' 'sha256' verify "$FIX"
sed -i "s/^sha256sums=.*/sha256sums=('$H64A')/" "$FIX/packages/alpha/PKGBUILD"

sed -i "s/^sha256sums=.*/sha256sums=('SKIP')/" "$FIX/packages/alpha/PKGBUILD"
expect_fail 'SKIP digest' '64-hex' verify "$FIX"
sed -i "s/^sha256sums=.*/sha256sums=('$H64A')/" "$FIX/packages/alpha/PKGBUILD"

sed -i 's#source=.*#source=("https://vendor.example/alpha_${pkgver}.deb" "https://vendor.example/extra.bin")#' "$FIX/packages/alpha/PKGBUILD"
expect_fail 'two source URLs' 'exactly one https' verify "$FIX"
write_pkg "$FIX" alpha 1.0.0 "$H64A" vendor.example

printf '../etc\nalpha\nbeta\n' >"$FIX/allowlist.txt"
expect_fail 'path traversal allowlist' 'not a pkgname' verify "$FIX"
write_allow "$FIX" alpha beta

expect_ok 'two packages still verify' verify "$FIX"

expect_ok 'propose alpha only' propose "$FIX" alpha
if grep -q '^pkgver=1.2.0$' "$FIX/packages/alpha/PKGBUILD"; then
  ok 'alpha bumped to 1.2.0'
else
  bad "alpha pkgver=$(company_pkgbuild_get "$FIX/packages/alpha/PKGBUILD" pkgver)"
fi
if grep -q "sha256sums=('$H64B')" "$FIX/packages/alpha/PKGBUILD"; then
  ok 'alpha sha follows vendor latest'
else
  bad 'alpha sha not latest'
fi
if grep -q '^pkgver=2.0.0$' "$FIX/packages/beta/PKGBUILD"; then
  ok 'beta unchanged by alpha propose'
else
  bad 'beta was rewritten'
fi

sed -i "s/^sha256sums=.*/sha256sums=('$H64B')/" "$FIX/packages/alpha/PKGBUILD"
expect_ok 'verify after propose' verify "$FIX"

expect_ok 'propose all current' propose "$FIX"
if grep -q 'CURRENT alpha 1.2.0' /tmp/cap-out && grep -q 'CURRENT beta 2.0.0' /tmp/cap-out; then
  ok 'propose all reports CURRENT'
else
  bad "propose all output: $(tr '\n' ' ' </tmp/cap-out)"
fi

expect_ok 'real allowlist PKGBUILDs' bash "$REPO/scripts/verify-pkgbuild.sh"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

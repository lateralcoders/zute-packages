# Shared helpers for company-arch-packages. Source from other scripts.
# COMPANY_ROOT overrides the repo root (tests).
# shellcheck shell=bash

_PKG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${COMPANY_ROOT:-${ROOT:-$(cd "$_PKG_LIB_DIR/.." && pwd)}}"
ALLOW="${ALLOW:-$ROOT/allowlist.txt}"
PACKAGES="${PACKAGES:-$ROOT/packages}"

company_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

company_valid_pkgname() {
  [[ "$1" =~ ^[a-z0-9][+a-z0-9._-]*$ ]]
}

company_valid_host() {
  local h=$1
  [[ "$h" == *.* ]] || return 1
  [[ "$h" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]
}

# actual hostname is expected or a subdomain of expected.
company_host_ok() {
  local actual=$1 expected=$2
  [[ -n "$actual" && -n "$expected" ]] || return 1
  [[ "$actual" == "$expected" || "$actual" == *."$expected" ]]
}

company_trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

company_allowlist() {
  [[ -f "$ALLOW" ]] || company_fail "missing allowlist.txt"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    line=$(company_trim "$line")
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"
  done <"$ALLOW"
}

company_package_dirs() {
  [[ -d "$PACKAGES" ]] || return 0
  (
    shopt -s nullglob
    for d in "$PACKAGES"/*/; do
      basename "${d%/}"
    done
  )
}

company_upstream_file() { printf '%s\n' "$PACKAGES/$1/upstream"; }
company_pkgbuild_file() { printf '%s\n' "$PACKAGES/$1/PKGBUILD"; }

# key=value file (upstream). First match. Values may contain '='.
company_kv_get() {
  local file=$1 key=$2
  [[ -f "$file" ]] || return 1
  awk -v k="$key" '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*(#|$)/) next
      if (index(line, k "=") == 1) {
        print substr(line, length(k) + 2)
        exit
      }
    }
  ' "$file"
}

# First assignment of KEY= in a PKGBUILD; strips quotes, parens, whitespace.
company_pkgbuild_get() {
  local file=$1 key=$2
  awk -v k="$key" '
    $0 ~ "^" k "=" {
      sub(/^[^=]+=/, "")
      gsub(/["'\''()[:space:]]/, "")
      print
      exit
    }
  ' "$file"
}

# https:// URLs inside the source=(...) assignment (single- or multi-line).
company_source_urls() {
  local file=$1
  awk '
    BEGIN { in_src = 0 }
    /^source=/ { in_src = 1 }
    in_src {
      s = $0
      while (match(s, /https:\/\/[^"'\'' )]+/)) {
        print substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
      }
      if ($0 ~ /\)/) exit
    }
  ' "$file"
}

company_url_host() {
  local url=$1
  case "$url" in
    https://*) url="${url#https://}" ;;
    http://*) url="${url#http://}" ;;
    file://*) printf '\n'; return 0 ;;
    *) printf '\n'; return 1 ;;
  esac
  url="${url%%/*}"
  url="${url%%:*}"
  printf '%s\n' "$url"
}

company_url_scheme_ok() {
  local url=$1
  case "$url" in
    https://*) return 0 ;;
    file://*)
      [[ "${COMPANY_ALLOW_FILE_SUMS:-}" == 1 ]] || return 1
      return 0
      ;;
    *) return 1 ;;
  esac
}

company_expand_glob() {
  local glob=$1 ver=$2
  printf '%s\n' "${glob//\{pkgver\}/$ver}"
}

# SHA-256 from a sha256sum-format file for an exact basename.
company_sums_hash_for() {
  local sums_file=$1 want=$2
  local hash field
  while read -r hash field _; do
    [[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]] || continue
    field="${field#\*}"
    field="${field##*/}"
    if [[ "$field" == "$want" ]]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done <"$sums_file"
  return 1
}

# Print unique versions (capture group 1) found in a sums file, sort -V.
company_versions_from_sums() {
  local sums_file=$1 regex=$2
  local hash field base
  while read -r hash field _; do
    [[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]] || continue
    field="${field#\*}"
    base="${field##*/}"
    if [[ "$base" =~ $regex ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done <"$sums_file" | sort -uV
}

company_fetch() {
  curl -fsSL "$1" -o "$2"
}

company_require_upstream() {
  local name=$1
  local up host sums_url sums_glob version_regex sums_host
  up=$(company_upstream_file "$name")
  [[ -f "$up" ]] || company_fail "$name: missing packages/$name/upstream"
  host=$(company_kv_get "$up" host) || true
  sums_url=$(company_kv_get "$up" sums_url) || true
  sums_glob=$(company_kv_get "$up" sums_glob) || true
  version_regex=$(company_kv_get "$up" version_regex) || true
  sums_host=$(company_kv_get "$up" sums_host) || true
  [[ -n "$host" ]] || company_fail "$name: upstream missing host="
  [[ -n "$sums_url" ]] || company_fail "$name: upstream missing sums_url="
  [[ -n "$sums_glob" ]] || company_fail "$name: upstream missing sums_glob="
  [[ -n "$version_regex" ]] || company_fail "$name: upstream missing version_regex="
  company_valid_host "$host" || company_fail "$name: host= is not an FQDN: $host"
  if [[ -n "$sums_host" ]]; then
    company_valid_host "$sums_host" || company_fail "$name: sums_host= is not an FQDN: $sums_host"
  fi
  company_url_scheme_ok "$sums_url" || company_fail "$name: sums_url must be https:// (got $sums_url)"
  local sums_url_host
  sums_url_host=$(company_url_host "$sums_url")
  if [[ "$sums_url" == file://* ]]; then
    :
  else
    company_host_ok "$sums_url_host" "${sums_host:-$host}" || \
      company_fail "$name: sums_url host $sums_url_host is not ${sums_host:-$host}"
  fi
  [[ "$version_regex" == *"("* ]] || company_fail "$name: version_regex must have a capture group"
}

# Load allowlist, refuse path-traversal names, refuse extra package dirs.
# Sets company_pkgs array.
company_load_gate() {
  local name extra
  company_pkgs=()
  mapfile -t company_pkgs < <(company_allowlist)
  [[ ${#company_pkgs[@]} -gt 0 ]] || company_fail "allowlist empty"
  for name in "${company_pkgs[@]}"; do
    company_valid_pkgname "$name" || company_fail "allowlist name is not a pkgname: $name"
    [[ -f "$(company_pkgbuild_file "$name")" ]] || company_fail "no PKGBUILD for $name"
    company_require_upstream "$name"
  done
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    company_valid_pkgname "$name" || company_fail "packages/$name is not a pkgname"
    local listed=0
    for want in "${company_pkgs[@]}"; do
      if [[ "$want" == "$name" ]]; then
        listed=1
        break
      fi
    done
    [[ $listed -eq 1 ]] || company_fail "packages/$name is not in allowlist.txt"
  done < <(company_package_dirs)
}

#!/usr/bin/env bash
# Rewrite nvchecker.toml from packages/*/upstream. Source of truth is upstream.
set -euo pipefail
_HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pkg-lib.sh
source "$_HERE/pkg-lib.sh"

company_load_gate

out="$ROOT/nvchecker.toml"
{
  cat <<'EOF'
# Generated from packages/*/upstream. Do not edit by hand.
#   scripts/gen-nvchecker.sh
[__config__]
oldver = "nvchecker-old.json"
newver = "nvchecker-new.json"
EOF
  for name in "${company_pkgs[@]}"; do
    up=$(company_upstream_file "$name")
    url=$(company_kv_get "$up" sums_url)
    regex=$(company_kv_get "$up" version_regex)
    [[ "$regex" == *"'"* ]] && company_fail "$name: version_regex contains a quote"
    printf '\n[%s]\nsource = "regex"\nurl = "%s"\nregex = '\''%s'\''\n' "$name" "$url" "$regex"
  done
} >"$out"
echo "wrote $out"

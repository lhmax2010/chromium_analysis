#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
baseline=${1:-"$script_dir/inputs/baseline_exports.tsv"}
output=${2:-"$script_dir/inputs/node_nonstd_export_allowlist.tsv"}

fail() {
  echo "[NODE-ALLOWLIST-GEN-FAIL] $*" >&2
  exit 1
}

for tool in awk c++filt cut dirname mktemp paste rm sort wc; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done
[[ -f "$baseline" ]] || fail "missing baseline snapshot: $baseline"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
awk -F '\t' '$1 ~ /\/libnode\.so$/ && $2 ~ /^_Z/ {print $2}' "$baseline" |
  LC_ALL=C sort -u >"$tmp_dir/mangled.txt"
c++filt <"$tmp_dir/mangled.txt" >"$tmp_dir/demangled.txt"
paste "$tmp_dir/mangled.txt" "$tmp_dir/demangled.txt" |
  awk -F '\t' '$1 != $2 && $2 !~ /std::/ {print $1 "\t" $2}' |
  LC_ALL=C sort -u >"$output"

[[ $(wc -l <"$tmp_dir/mangled.txt") -eq 378 ]] ||
  fail "baseline libnode C++ export count is not 378"
[[ $(wc -l <"$output") -eq 354 ]] ||
  fail "stable non-STL libnode export count is not 354"
awk -F '\t' 'NF != 2 || $1 !~ /^_Z/ || $1 == $2 || $2 ~ /std::/ {bad++}
  {if (seen[$1]++) bad++} END {exit bad != 0}' "$output" ||
  fail "generated allowlist is malformed, duplicated, or contains std::"

echo "[NODE-ALLOWLIST-GEN-OK] baseline_cxx=378 stable_nonstd=354 std_carrying=22 demangle_unknown=2"

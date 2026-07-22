#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage: abi_gate_v2.sh \
  --candidate-root DIR \
  --baseline-exports FILE \
  --added-allowlist FILE \
  --internal-cxx-allowlist FILE \
  --bridge-allowlist FILE \
  --out DIR

Input files are read-only. Export files use: DSO-or-path<TAB>symbol.
The added-export allowlist is exact: DSO-basename<TAB>symbol.
The internal C++ allowlist is exact: provider-DSO<TAB>symbol[<TAB>demangled].
EOF
}

candidate_root=
baseline_exports=
added_allowlist=
internal_cxx_allowlist=
bridge_allowlist=
out=

while (($#)); do
  case "$1" in
    --candidate-root) candidate_root=$2; shift 2 ;;
    --baseline-exports) baseline_exports=$2; shift 2 ;;
    --added-allowlist) added_allowlist=$2; shift 2 ;;
    --internal-cxx-allowlist) internal_cxx_allowlist=$2; shift 2 ;;
    --bridge-allowlist) bridge_allowlist=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in candidate_root baseline_exports added_allowlist internal_cxx_allowlist bridge_allowlist out; do
  [[ -n ${!value} ]] || { echo "missing --${value//_/-}" >&2; exit 2; }
done
[[ -d $candidate_root ]] || { echo "candidate root not found: $candidate_root" >&2; exit 2; }
for input in "$baseline_exports" "$added_allowlist" "$internal_cxx_allowlist" "$bridge_allowlist"; do
  [[ -f $input ]] || { echo "input not found: $input" >&2; exit 2; }
done
for tool in readelf c++filt awk sort comm cut paste find wc; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

mkdir -p "$out/raw"
exports="$out/candidate_exports.tsv"
cxx_defined="$out/candidate_cxx_defined.tsv"
cxx_und="$out/candidate_cxx_und.tsv"
needed="$out/candidate_needed.tsv"
: > "$exports"
: > "$cxx_defined"
: > "$cxx_und"
: > "$needed"

while IFS= read -r -d '' elf; do
  readelf -h "$elf" >/dev/null 2>&1 || continue
  rel=${elf#"$candidate_root"/}
  dso=$(basename "$rel")
  key=${rel//\//__}
  dynsym="$out/raw/$key.dynsym.txt"
  dynamic="$out/raw/$key.dynamic.txt"
  readelf --dyn-syms -W "$elf" > "$dynsym"
  readelf -d -W "$elf" > "$dynamic"

  awk -v dso="$dso" 'BEGIN{OFS="\t"}
    /^[[:space:]]*[0-9]+:/ && ($5=="GLOBAL" || $5=="WEAK") && $7!="UND" {
      name=$8; sub(/@.*/, "", name); print dso,name
    }' "$dynsym" >> "$exports"
  awk -v dso="$dso" 'BEGIN{OFS="\t"}
    /^[[:space:]]*[0-9]+:/ && ($5=="GLOBAL" || $5=="WEAK") &&
      $7!="UND" && $8~/^_Z/ {
      name=$8; sub(/@.*/, "", name); print dso,name
    }' "$dynsym" >> "$cxx_defined"
  awk -v dso="$dso" 'BEGIN{OFS="\t"}
    /^[[:space:]]*[0-9]+:/ && $7=="UND" && $8~/^_Z/ {
      name=$8; sub(/@.*/, "", name); print dso,name
    }' "$dynsym" >> "$cxx_und"
  awk -v dso="$dso" 'BEGIN{OFS="\t"}
    /\(NEEDED\)/ {
      name=$0; sub(/^.*\[/, "", name); sub(/\].*$/, "", name); print dso,name
    }' "$dynamic" >> "$needed"
done < <(find "$candidate_root" -type f \
  \( -name '*.so' -o -name '*.so.*' \) \
  ! -name '*.debug' ! -path '*/usr/lib/debug/*' -print0 | LC_ALL=C sort -z)

for generated in "$exports" "$cxx_defined" "$cxx_und" "$needed"; do
  LC_ALL=C sort -u "$generated" -o "$generated"
done

unknown="$out/unknown_symbols.tsv"
: > "$unknown"

demangle_and_gate() {
  local scope=$1 raw=$2 result=$3
  local symbols="$out/.${scope}.symbols"
  local demangled="$out/.${scope}.demangled"
  local joined="$out/.${scope}.joined"
  : > "$result"
  [[ -s $raw ]] || return 0
  cut -f2 "$raw" > "$symbols"
  c++filt < "$symbols" > "$demangled"
  paste "$raw" "$demangled" > "$joined"
  awk -F '\t' -v scope="$scope" 'BEGIN{OFS="\t"}
    {
      dso=$1; raw=$2; demangled=$3
      if (demangled==raw || demangled=="")
        print scope,dso,raw > unknown
      if (demangled ~ /std::__(Cr|1)(::|[^[:alnum:]_])/ || raw ~ /NSt4__Cr|NSt3__1/)
        print dso,raw,demangled
    }' unknown="$unknown" "$joined" > "$result"
}

g1="$out/g1_full_signature_exports.tsv"
g2="$out/g2_full_signature_und.tsv"
demangle_and_gate defined "$cxx_defined" "$g1"
demangle_and_gate und "$cxx_und" "$g2"
LC_ALL=C sort -u "$unknown" -o "$unknown"

internal_normalized="$out/internal_cxx_allowlist.normalized.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} NF>=2 {
  dso=$1; sub(/^.*\//, "", dso); print dso,$2
}' "$internal_cxx_allowlist" | LC_ALL=C sort -u > "$internal_normalized"

g1_keys="$out/g1_full_signature_exports.keys.tsv"
g1_allowed_keys="$out/g1_full_signature_exports.allowlisted.keys.tsv"
g1_unallowed_keys="$out/g1_full_signature_exports.unallowlisted.keys.tsv"
g1_missing="$out/g1_internal_allowlist.missing.tsv"
g1_allowed="$out/g1_full_signature_exports.allowlisted.tsv"
g1_unallowed="$out/g1_full_signature_exports.unallowlisted.tsv"
cut -f1,2 "$g1" | LC_ALL=C sort -u > "$g1_keys"
comm -12 "$g1_keys" "$internal_normalized" > "$g1_allowed_keys"
comm -23 "$g1_keys" "$internal_normalized" > "$g1_unallowed_keys"
comm -23 "$internal_normalized" "$g1_keys" > "$g1_missing"
awk -F '\t' 'BEGIN{OFS="\t"} NR==FNR {ok[$1 SUBSEP $2]=1; next}
  (($1 SUBSEP $2) in ok) {print}' "$g1_allowed_keys" "$g1" > "$g1_allowed"
awk -F '\t' 'BEGIN{OFS="\t"} NR==FNR {bad[$1 SUBSEP $2]=1; next}
  (($1 SUBSEP $2) in bad) {print}' "$g1_unallowed_keys" "$g1" > "$g1_unallowed"

internal_symbols="$out/internal_cxx_allowlist.symbols.txt"
g2_allowed="$out/g2_full_signature_und.allowlisted.tsv"
g2_unallowed="$out/g2_full_signature_und.unallowlisted.tsv"
cut -f2 "$internal_normalized" | LC_ALL=C sort -u > "$internal_symbols"
awk -F '\t' 'BEGIN{OFS="\t"} NR==FNR {ok[$1]=1; next}
  ($2 in ok) {print}' "$internal_symbols" "$g2" > "$g2_allowed"
awk -F '\t' 'BEGIN{OFS="\t"} NR==FNR {ok[$1]=1; next}
  !($2 in ok) {print}' "$internal_symbols" "$g2" > "$g2_unallowed"

g3="$out/g3_needed_libcxx.tsv"
awk -F '\t' '$2 ~ /^libc\+\+(abi)?\.so([.0-9]*)?$/' "$needed" > "$g3"

baseline_normalized="$out/baseline_exports.normalized.tsv"
allowlist_normalized="$out/added_allowlist.normalized.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} NF>=2 {dso=$1; sub(/^.*\//, "", dso); print dso,$2}' \
  "$baseline_exports" | LC_ALL=C sort -u > "$baseline_normalized"
awk -F '\t' 'BEGIN{OFS="\t"} NF>=2 {dso=$1; sub(/^.*\//, "", dso); print dso,$2}' \
  "$added_allowlist" | LC_ALL=C sort -u > "$allowlist_normalized"

added="$out/added_exports.tsv"
unallowed="$out/added_exports.unallowlisted.tsv"
comm -13 "$baseline_normalized" "$exports" > "$added"
comm -23 "$added" "$allowlist_normalized" > "$unallowed"

bridge_actual="$out/bridge_exports.actual.txt"
bridge_expected="$out/bridge_exports.expected.txt"
bridge_unexpected="$out/bridge_exports.unexpected.txt"
bridge_missing="$out/bridge_exports.missing.txt"
bridge_cpp="$out/bridge_cpp_exports.txt"
bridge_needed="$out/bridge_needed_libstdcxx.txt"
: > "$bridge_actual"
: > "$bridge_cpp"
: > "$bridge_needed"
mapfile -d '' bridge_paths < <(find "$candidate_root" -type f -name 'libwrt-c++wrapper.so' -print0)
if ((${#bridge_paths[@]} == 1)); then
  bridge=${bridge_paths[0]}
  readelf --dyn-syms -W "$bridge" | awk '
    /^[[:space:]]*[0-9]+:/ && ($5=="GLOBAL" || $5=="WEAK") &&
      $7!="UND" {
      name=$8; sub(/@.*/, "", name); print name
    }' | LC_ALL=C sort -u > "$bridge_actual"
  awk '/^_ZNSt/' "$bridge_actual" > "$bridge_cpp"
  readelf -d -W "$bridge" | awk '/\(NEEDED\)/ && /\[libstdc\+\+\.so/ {print}' \
    > "$bridge_needed"
else
  printf 'bridge_count=%d\n' "${#bridge_paths[@]}" > "$out/bridge_path_error.txt"
fi
LC_ALL=C sort -u "$bridge_allowlist" > "$bridge_expected"
comm -23 "$bridge_actual" "$bridge_expected" > "$bridge_unexpected"
comm -13 "$bridge_actual" "$bridge_expected" > "$bridge_missing"

count() { wc -l < "$1" | awk '{print $1}'; }
g1_count=$(count "$g1")
g2_count=$(count "$g2")
g1_allowed_count=$(count "$g1_allowed")
g1_unallowed_count=$(count "$g1_unallowed")
g1_missing_count=$(count "$g1_missing")
g2_allowed_count=$(count "$g2_allowed")
g2_unallowed_count=$(count "$g2_unallowed")
g3_count=$(count "$g3")
unknown_count=$(count "$unknown")
added_count=$(count "$added")
unallowed_count=$(count "$unallowed")
bridge_unexpected_count=$(count "$bridge_unexpected")
bridge_missing_count=$(count "$bridge_missing")
bridge_cpp_count=$(count "$bridge_cpp")
bridge_needed_count=$(count "$bridge_needed")

status=PASS
if ((g1_unallowed_count || g1_missing_count || g2_unallowed_count ||
    g3_count || unallowed_count ||
    bridge_unexpected_count || bridge_missing_count || bridge_cpp_count ||
    bridge_needed_count == 0 || ${#bridge_paths[@]} != 1)); then
  status=FAIL
fi

summary="$out/summary.txt"
{
  echo "status=$status"
  echo "G1_full_signature_export_hits=$g1_count"
  echo "G1_allowlisted=$g1_allowed_count"
  echo "G1_unallowlisted=$g1_unallowed_count"
  echo "G1_internal_allowlist_missing=$g1_missing_count"
  echo "G2_full_signature_und_hits=$g2_count"
  echo "G2_allowlisted=$g2_allowed_count"
  echo "G2_unallowlisted=$g2_unallowed_count"
  echo "G3_needed_libcxx_hits=$g3_count"
  echo "unknown_symbols=$unknown_count"
  echo "added_exports=$added_count"
  echo "added_exports_unallowlisted=$unallowed_count"
  echo "bridge_count=${#bridge_paths[@]}"
  echo "bridge_unexpected=$bridge_unexpected_count"
  echo "bridge_missing=$bridge_missing_count"
  echo "bridge_ZNSt_exports=$bridge_cpp_count"
  echo "bridge_NEEDED_libstdcxx=$bridge_needed_count"
} | tee "$summary"

[[ $status == PASS ]]

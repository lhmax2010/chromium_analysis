#!/usr/bin/env bash
set -euo pipefail

evidence_dir=/home/linhao/Toolchain/plan_evaluation/spike_libcxx
attempt=${1:-12}
if [[ ! "$attempt" =~ ^[0-9]+$ ]]; then
  echo "attempt must be numeric: $attempt" >&2
  exit 2
fi
extract_root="$evidence_dir/attempt${attempt}_rpm_extract"
raw_dir="$evidence_dir/attempt${attempt}_elf_raw"

if [[ ! -d "$extract_root" ]]; then
  echo "missing extract root: $extract_root" >&2
  exit 2
fi
if [[ -e "$raw_dir" ]]; then
  echo "refusing existing raw output directory: $raw_dir" >&2
  exit 2
fi
mkdir -p "$raw_dir"

inventory="$evidence_dir/attempt${attempt}_elf_inventory.tsv"
g1="$evidence_dir/attempt${attempt}_g1_export_hits.tsv"
g2="$evidence_dir/attempt${attempt}_g2_und_hits.tsv"
g3="$evidence_dir/attempt${attempt}_g3_needed_hits.tsv"
index="$evidence_dir/attempt${attempt}_elf_raw_index.tsv"
: > "$inventory"
: > "$g1"
: > "$g2"
: > "$g3"
: > "$index"

printf 'payload_path\tfile_type\tsymlink_target\n' >> "$inventory"
printf 'payload_path\tsymbol\n' >> "$g1"
printf 'payload_path\tsymbol\n' >> "$g2"
printf 'payload_path\tdynamic_entry\n' >> "$g3"
printf 'payload_path\tdynsym_raw\tdynamic_raw\n' >> "$index"

shopt -s globstar nullglob
candidates=("$extract_root"/**/*.so "$extract_root"/**/*.so.*)
mapfile -d '' candidates < <(printf '%s\0' "${candidates[@]}" | sort -zu)

elf_count=0
for path in "${candidates[@]}"; do
  rel=${path#"$extract_root"/}
  symlink_target=-
  if [[ -L "$path" ]]; then
    symlink_target=$(readlink "$path")
  fi
  file_type=$(file -b "$path")
  printf '%s\t%s\t%s\n' "$rel" "$file_type" "$symlink_target" >> "$inventory"

  if ! readelf -h "$path" >/dev/null 2>&1; then
    continue
  fi
  ((elf_count += 1))

  key=${rel//\//__}
  dynsym_raw="$raw_dir/$key.dynsym.txt"
  dynamic_raw="$raw_dir/$key.dynamic.txt"
  readelf --dyn-syms -W "$path" > "$dynsym_raw" 2>&1 || true
  readelf -d -W "$path" > "$dynamic_raw" 2>&1 || true
  printf '%s\t%s\t%s\n' "$rel" "${dynsym_raw#"$evidence_dir"/}" "${dynamic_raw#"$evidence_dir"/}" >> "$index"

  awk -v file="$rel" '
    /^[[:space:]]*[0-9]+:/ {
      if (($5 == "GLOBAL" || $5 == "WEAK") && $7 != "UND" &&
          ($8 ~ /^_ZNSt4__Cr/ || $8 ~ /^_ZNSt3__1/))
        print file "\t" $8
    }
  ' "$dynsym_raw" >> "$g1"

  awk -v file="$rel" '
    /^[[:space:]]*[0-9]+:/ {
      if ($7 == "UND" && ($8 ~ /^_ZNSt4__Cr/ || $8 ~ /^_ZNSt3__1/))
        print file "\t" $8
    }
  ' "$dynsym_raw" >> "$g2"

  awk -v file="$rel" '
    /\(NEEDED\)/ && ($0 ~ /libc\+\+/ || $0 ~ /libc\+\+abi/) {
      print file "\t" $0
    }
  ' "$dynamic_raw" >> "$g3"
done

bridge_candidates=("$extract_root"/*/usr/share/chromium-efl/lib/libwrt-c++wrapper.so)
if [[ ${#bridge_candidates[@]} -ne 1 ]]; then
  echo "expected one packaged bridge, got ${#bridge_candidates[@]}" >&2
  exit 3
fi
bridge=${bridge_candidates[0]}
bridge_rel=${bridge#"$extract_root"/}
bridge_key=${bridge_rel//\//__}
bridge_dynsym="$raw_dir/$bridge_key.dynsym.txt"
bridge_dynamic="$raw_dir/$bridge_key.dynamic.txt"

bridge_actual="$evidence_dir/attempt${attempt}_wrt_bridge_exports.actual.txt"
bridge_unexpected="$evidence_dir/attempt${attempt}_wrt_bridge_exports.unexpected.txt"
bridge_missing="$evidence_dir/attempt${attempt}_wrt_bridge_exports.missing.txt"
bridge_cpp="$evidence_dir/attempt${attempt}_wrt_bridge_cpp_exports.txt"
bridge_needed="$evidence_dir/attempt${attempt}_wrt_bridge_needed.txt"
whitelist="$evidence_dir/wrt_bridge_export_whitelist.standard.txt"

awk '
  /^[[:space:]]*[0-9]+:/ && ($5 == "GLOBAL" || $5 == "WEAK") &&
  $7 != "UND" && $4 == "FUNC" {
    name=$8
    sub(/@.*/, "", name)
    print name
  }
' "$bridge_dynsym" | sort -u > "$bridge_actual"
comm -23 "$bridge_actual" "$whitelist" > "$bridge_unexpected"
comm -13 "$bridge_actual" "$whitelist" > "$bridge_missing"
awk '
  /^[[:space:]]*[0-9]+:/ && ($5 == "GLOBAL" || $5 == "WEAK") &&
  $7 != "UND" && $8 ~ /^_ZNSt/ { print $8 }
' "$bridge_dynsym" | sort -u > "$bridge_cpp"
awk '/\(NEEDED\)/ { print }' "$bridge_dynamic" > "$bridge_needed"

summary="$evidence_dir/attempt${attempt}_gate_summary.txt"
payload_count=$(tail -n +2 "$inventory" | wc -l)
g1_count=$(tail -n +2 "$g1" | wc -l)
g2_count=$(tail -n +2 "$g2" | wc -l)
g3_count=$(tail -n +2 "$g3" | wc -l)
bridge_actual_count=$(wc -l < "$bridge_actual")
bridge_unexpected_count=$(wc -l < "$bridge_unexpected")
bridge_missing_count=$(wc -l < "$bridge_missing")
bridge_cpp_count=$(wc -l < "$bridge_cpp")
bridge_libstdcxx_needed_count=$(grep -c 'Shared library: \[libstdc++\.so' "$bridge_needed" || true)

{
  echo "so_payload_count=$payload_count"
  echo "elf_payload_count=$elf_count"
  echo "G1_export_std_namespace_hits=$g1_count"
  echo "G2_und_std_namespace_hits=$g2_count"
  echo "G3_needed_libcxx_hits=$g3_count"
  echo "bridge_payload=$bridge_rel"
  echo "bridge_whitelist_count=$(wc -l < "$whitelist")"
  echo "bridge_actual_export_count=$bridge_actual_count"
  echo "bridge_unexpected_export_count=$bridge_unexpected_count"
  echo "bridge_missing_export_count=$bridge_missing_count"
  echo "bridge_ZNSt_export_count=$bridge_cpp_count"
  echo "bridge_NEEDED_libstdcxx_count=$bridge_libstdcxx_needed_count"
} > "$summary"
cat "$summary"

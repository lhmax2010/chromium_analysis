#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 CANDIDATE_RPM_DIR OUTPUT_DIR [BASELINE_RPM_DIR]" >&2
  exit 2
fi

candidate_rpm_dir=$(readlink -f "$1")
output_dir=$2
baseline_rpm_dir=${3:-}
if [[ -n "$baseline_rpm_dir" ]]; then
  baseline_rpm_dir=$(readlink -f "$baseline_rpm_dir")
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
whitelist="$repo_root/evidence/spike_libcxx/wrt_bridge_export_whitelist.standard.txt"

for tool in rpm rpm2cpio cpio readelf file awk sort comm sha256sum; do
  command -v "$tool" >/dev/null || {
    echo "missing tool: $tool" >&2
    exit 2
  }
done
if [[ ! -d "$candidate_rpm_dir" ]]; then
  echo "missing candidate RPM directory: $candidate_rpm_dir" >&2
  exit 2
fi
if [[ -e "$output_dir" ]]; then
  echo "refusing to overwrite output directory: $output_dir" >&2
  exit 2
fi
if [[ ! -f "$whitelist" ]]; then
  echo "missing bridge whitelist: $whitelist" >&2
  exit 2
fi

mkdir -p "$output_dir"

extract_rpms() {
  local rpm_dir=$1
  local tag=$2
  local extract_root="$output_dir/${tag}_rpm_extract"
  local inventory="$output_dir/${tag}_rpm_inventory.tsv"
  local total=0
  local count=0
  local rpm_path rpm_name rpm_bytes package_dir

  mkdir -p "$extract_root"
  printf 'rpm\tbytes\tsha256\n' > "$inventory"
  mapfile -d '' rpms < <(find "$rpm_dir" -maxdepth 1 -type f \
    -name 'chromium-efl*.armv7l.rpm' -print0 | sort -z)
  if [[ ${#rpms[@]} -eq 0 ]]; then
    echo "no chromium-efl RPMs in $rpm_dir" >&2
    exit 3
  fi

  for rpm_path in "${rpms[@]}"; do
    rpm_name=$(basename "$rpm_path")
    rpm_bytes=$(stat -c %s "$rpm_path")
    package_dir="$extract_root/${rpm_name%.rpm}"
    mkdir -p "$package_dir"
    (
      cd "$package_dir"
      rpm2cpio "$rpm_path" | cpio -idm --quiet
    )
    printf '%s\t%s\t%s\n' "$rpm_name" "$rpm_bytes" \
      "$(sha256sum "$rpm_path" | awk '{print $1}')" >> "$inventory"
    rpm -qpl "$rpm_path" > "$output_dir/${tag}_${rpm_name}.payload.txt"
    total=$((total + rpm_bytes))
    count=$((count + 1))
  done

  {
    echo "rpm_count=$count"
    echo "rpm_total_bytes=$total"
    find "$extract_root" -type f -name 'libchromium-impl.so' \
      -printf 'libchromium_impl_bytes=%s path=%p\n'
  } > "$output_dir/${tag}_size_summary.txt"
}

scan_elfs() {
  local tag=$1
  local root="$output_dir/${tag}_rpm_extract"
  local raw="$output_dir/${tag}_elf_raw"
  local inventory="$output_dir/${tag}_elf_inventory.tsv"
  local exports="$output_dir/${tag}_exports.tsv"
  local needed="$output_dir/${tag}_needed.tsv"
  local runtime="$output_dir/${tag}_runtime_abi_symbols.tsv"
  local ewk="$output_dir/${tag}_ewk_parse_cookie.tsv"
  local path rel key dyn dynamic

  mkdir -p "$raw"
  printf 'payload_path\tfile_type\tsymlink_target\n' > "$inventory"
  : > "$exports"
  : > "$needed"
  : > "$runtime"
  : > "$ewk"

  mapfile -d '' candidates < <(find "$root" \
    \( -type f -o -type l \) \
    \( -name '*.so' -o -name '*.so.*' \) -print0 | sort -z)

  for path in "${candidates[@]}"; do
    rel=${path#"$root"/}
    target=-
    [[ -L "$path" ]] && target=$(readlink "$path")
    printf '%s\t%s\t%s\n' "$rel" "$(file -b "$path")" "$target" >> "$inventory"
    readelf -h "$path" >/dev/null 2>&1 || continue

    key=${rel//\//__}
    dyn="$raw/$key.dynsym.txt"
    dynamic="$raw/$key.dynamic.txt"
    readelf --dyn-syms -W "$path" > "$dyn" 2>&1 || true
    readelf -d -W "$path" > "$dynamic" 2>&1 || true

    awk -v file="$rel" '
      /^[[:space:]]*[0-9]+:/ && ($5 == "GLOBAL" || $5 == "WEAK") && $7 != "UND" {
        name=$8; sub(/@.*/, "", name); print file "\t" name
      }
    ' "$dyn" >> "$exports"
    awk -v file="$rel" '/\(NEEDED\)/ { print file "\t" $0 }' \
      "$dynamic" >> "$needed"
    awk -v file="$rel" '
      /^[[:space:]]*[0-9]+:/ && $8 ~ /^(__cxa_|_Unwind|Unwind)/ {
        print file "\t" $7 "\t" $5 "\t" $8
      }
    ' "$dyn" >> "$runtime"
    awk -v file="$rel" '
      /^[[:space:]]*[0-9]+:/ && $8 ~ /ewk_parse_cookie/ {
        print file "\t" $7 "\t" $5 "\t" $8
      }
    ' "$dyn" >> "$ewk"
  done

  sort -u -o "$exports" "$exports"
  sort -u -o "$needed" "$needed"
  sort -u -o "$runtime" "$runtime"
  sort -u -o "$ewk" "$ewk"
}

extract_rpms "$candidate_rpm_dir" candidate
scan_elfs candidate

candidate_raw="$output_dir/candidate_elf_raw"
g1="$output_dir/g1_export_hits.tsv"
g2="$output_dir/g2_und_hits.tsv"
g3="$output_dir/g3_needed_hits.tsv"
: > "$g1"
: > "$g2"
: > "$g3"

for dyn in "$candidate_raw"/*.dynsym.txt; do
  rel=$(basename "$dyn" .dynsym.txt)
  awk -v file="$rel" '
    /^[[:space:]]*[0-9]+:/ && ($5 == "GLOBAL" || $5 == "WEAK") &&
      $7 != "UND" && ($8 ~ /^_ZNSt4__Cr/ || $8 ~ /^_ZNSt3__1/) {
      print file "\t" $8
    }
  ' "$dyn" >> "$g1"
  awk -v file="$rel" '
    /^[[:space:]]*[0-9]+:/ && $7 == "UND" &&
      ($8 ~ /^_ZNSt4__Cr/ || $8 ~ /^_ZNSt3__1/) {
      print file "\t" $8
    }
  ' "$dyn" >> "$g2"
done
for dynamic in "$candidate_raw"/*.dynamic.txt; do
  rel=$(basename "$dynamic" .dynamic.txt)
  awk -v file="$rel" '/\(NEEDED\)/ && /libc\+\+|libc\+\+abi/ {
    print file "\t" $0
  }' "$dynamic" >> "$g3"
done

bridge=$(find "$output_dir/candidate_rpm_extract" -type f \
  -path '*/usr/share/chromium-efl/lib/libwrt-c++wrapper.so' -print -quit)
if [[ -z "$bridge" ]]; then
  echo "packaged bridge not found" >&2
  exit 4
fi
readelf --dyn-syms -W "$bridge" > "$output_dir/bridge_dynsym.txt"
readelf -d -W "$bridge" > "$output_dir/bridge_dynamic.txt"
awk '
  /^[[:space:]]*[0-9]+:/ && ($5 == "GLOBAL" || $5 == "WEAK") &&
  $7 != "UND" && $4 == "FUNC" {
    name=$8; sub(/@.*/, "", name); print name
  }
' "$output_dir/bridge_dynsym.txt" | sort -u > "$output_dir/bridge_exports.actual.txt"
comm -23 "$output_dir/bridge_exports.actual.txt" "$whitelist" \
  > "$output_dir/bridge_exports.unexpected.txt"
comm -13 "$output_dir/bridge_exports.actual.txt" "$whitelist" \
  > "$output_dir/bridge_exports.missing.txt"
awk '/^[[:space:]]*[0-9]+:/ && $7 != "UND" && $8 ~ /^_ZNSt/ { print $8 }' \
  "$output_dir/bridge_dynsym.txt" | sort -u > "$output_dir/bridge_cpp_exports.txt"
awk '/\(NEEDED\)/ { print }' "$output_dir/bridge_dynamic.txt" \
  > "$output_dir/bridge_needed.txt"

if [[ -n "$baseline_rpm_dir" ]]; then
  if [[ ! -d "$baseline_rpm_dir" ]]; then
    echo "missing baseline RPM directory: $baseline_rpm_dir" >&2
    exit 2
  fi
  extract_rpms "$baseline_rpm_dir" baseline
  scan_elfs baseline
  comm -13 "$output_dir/baseline_exports.tsv" "$output_dir/candidate_exports.tsv" \
    > "$output_dir/g4_added.tsv"
  comm -23 "$output_dir/baseline_exports.tsv" "$output_dir/candidate_exports.tsv" \
    > "$output_dir/g4_removed.tsv"
  diff -u "$output_dir/baseline_exports.tsv" "$output_dir/candidate_exports.tsv" \
    > "$output_dir/g4_full.diff" || true
else
  echo "UNRESOLVED: baseline RPM directory not supplied" > "$output_dir/g4_full.diff"
  : > "$output_dir/g4_added.tsv"
  : > "$output_dir/g4_removed.tsv"
fi

{
  echo "G1_export_std_namespace_hits=$(wc -l < "$g1")"
  echo "G2_und_std_namespace_hits=$(wc -l < "$g2")"
  echo "G3_needed_libcxx_hits=$(wc -l < "$g3")"
  echo "bridge_expected_exports=$(wc -l < "$whitelist")"
  echo "bridge_actual_exports=$(wc -l < "$output_dir/bridge_exports.actual.txt")"
  echo "bridge_unexpected_exports=$(wc -l < "$output_dir/bridge_exports.unexpected.txt")"
  echo "bridge_missing_exports=$(wc -l < "$output_dir/bridge_exports.missing.txt")"
  echo "bridge_ZNSt_exports=$(wc -l < "$output_dir/bridge_cpp_exports.txt")"
  echo "bridge_NEEDED_libstdcxx=$(grep -c 'Shared library: \[libstdc++\.so' "$output_dir/bridge_needed.txt" || true)"
  echo "G4_added=$(wc -l < "$output_dir/g4_added.tsv")"
  echo "G4_removed=$(wc -l < "$output_dir/g4_removed.tsv")"
} > "$output_dir/gate_summary.txt"

cat "$output_dir/gate_summary.txt"

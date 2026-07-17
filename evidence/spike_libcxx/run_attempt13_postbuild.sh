#!/usr/bin/env bash
set -euo pipefail

evidence_dir=/home/linhao/Toolchain/plan_evaluation/spike_libcxx
build_unit=chromium-libcxx-attempt13-visibility.service
repo=/home/linhao/GBS-ROOT-TIZEN-UNIFIED-LLVM/local/repos/tizen_unified_standard/armv7l/RPMS
extract_root="$evidence_dir/attempt13_rpm_extract"
log="$evidence_dir/attempt13_postbuild.log"
final_state="$evidence_dir/full_gbs_attempt13_service_final.txt"
payloads="$evidence_dir/attempt13_rpm_payloads.txt"
sizes="$evidence_dir/attempt13_size_summary.txt"

exec > >(tee -a "$log") 2>&1
echo "postbuild_started=$(date --iso-8601=seconds)"

while systemctl --user is-active --quiet "$build_unit"; do
  sleep 30
done

systemctl --user show "$build_unit" \
  -p ActiveState -p SubState -p Result -p ExecMainStatus -p NRestarts \
  -p MemoryPeak -p CPUUsageNSec -p TasksMax -p MemoryMax -p MemorySwapMax \
  > "$final_state"
cat "$final_state"

result=$(sed -n 's/^Result=//p' "$final_state")
status=$(sed -n 's/^ExecMainStatus=//p' "$final_state")
if [[ "$result" != success || "$status" != 0 ]]; then
  echo "build did not succeed; refusing RPM extraction: result=$result status=$status" >&2
  exit 3
fi

if [[ -e "$extract_root" ]]; then
  echo "refusing existing extraction root: $extract_root" >&2
  exit 4
fi

mapfile -d '' rpms < <(
  find "$repo" -maxdepth 1 -type f -name 'chromium-efl*.armv7l.rpm' -print0 | sort -z
)
if [[ ${#rpms[@]} -eq 0 ]]; then
  echo "no chromium-efl binary RPMs found in $repo" >&2
  exit 5
fi

mkdir -p "$extract_root"
: > "$payloads"
total_rpm_bytes=0
for rpm_path in "${rpms[@]}"; do
  rpm_name=$(basename "$rpm_path")
  package_dir="$extract_root/${rpm_name%.rpm}"
  rpm_bytes=$(stat -c %s "$rpm_path")
  total_rpm_bytes=$((total_rpm_bytes + rpm_bytes))
  printf '===== RPM %s SIZE %s =====\n' "$rpm_name" "$rpm_bytes" >> "$payloads"
  rpm -qpl "$rpm_path" >> "$payloads"
  mkdir -p "$package_dir"
  (
    cd "$package_dir"
    rpm2cpio "$rpm_path" | cpio -idm --quiet
  )
  echo "extracted=$rpm_name bytes=$rpm_bytes"
done

{
  echo "rpm_count=${#rpms[@]}"
  echo "rpm_total_bytes=$total_rpm_bytes"
  find "$extract_root" -type f -name 'libchromium-impl.so' \
    -printf 'libchromium_impl_bytes=%s path=%p\n'
} > "$sizes"
cat "$sizes"

bash "$evidence_dir/run_attempt12_elf_gates.sh" 13
echo "postbuild_finished=$(date --iso-8601=seconds)"

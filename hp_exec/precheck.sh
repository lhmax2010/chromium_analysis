#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
analysis_root=$(cd "$script_dir/.." && pwd)
inputs="$script_dir/inputs"
logs="$script_dir/logs"
generated="$script_dir/generated"
source_repo=$(cd "$analysis_root/.." && pwd)/chromium-efl
backup_repo=$(cd "$analysis_root/.." && pwd)/chromium-efl_backup
source_commit=$(<"$inputs/SOURCE_COMMIT")
base_commit=$(<"$inputs/SOURCE_BASE_COMMIT")
started=0
failure_reported=0

precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] precheck.sh: $*" >&2
  exit 1
}
step_fail() {
  failure_reported=1
  echo "[STEP-0-FAIL] precheck.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-0-FAIL] precheck.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] precheck.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

mkdir -p "$logs" "$generated"

required_tools=(
  awk bash c++filt cmp cpio cut df dirname du file find free gbs git grep gzip
  head mkdir mktemp nm nproc paste readelf readlink rpm2cpio sed sha256sum
  sort stat systemctl systemd-run tail tar tee timeout tr uname uniq wc
)
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || precheck_fail "missing tool: $tool"
done
[[ -x /usr/bin/time ]] || precheck_fail "missing executable: /usr/bin/time"
if command -v qemu-arm-static >/dev/null 2>&1; then
  qemu_arm=$(command -v qemu-arm-static)
elif command -v qemu-arm >/dev/null 2>&1; then
  qemu_arm=$(command -v qemu-arm)
else
  precheck_fail "missing qemu-arm-static and qemu-arm"
fi

[[ -d "$source_repo/.git" ]] || precheck_fail "missing independent clone: $source_repo"
[[ -d "$backup_repo/.git" ]] || precheck_fail "missing independent clone: $backup_repo"
[[ -f "$inputs/SHA256SUMS" ]] || precheck_fail "missing inputs/SHA256SUMS"
(cd "$inputs" && sha256sum -c SHA256SUMS) >"$logs/input_sha256_check.txt" 2>&1 ||
  precheck_fail "input SHA256 verification failed; see logs/input_sha256_check.txt"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ && "$base_commit" =~ ^[0-9a-f]{40}$ ]] ||
  precheck_fail "source commit input is not a 40-character SHA"
[[ $(wc -l <"$inputs/internal_cr_allowlist.tsv") -eq 34 ]] ||
  precheck_fail "internal C++ allowlist count is not 34"
[[ $(wc -l <"$inputs/expected_hidden_cr_exports.tsv") -eq 454 ]] ||
  precheck_fail "hidden export assertion count is not 454"
[[ $(wc -l <"$inputs/expected_added_exports.tsv") -eq 166 ]] ||
  precheck_fail "added export allowlist count is not 166"
[[ $(wc -l <"$inputs/bridge_export_allowlist.txt") -eq 92 ]] ||
  precheck_fail "bridge export allowlist count is not 92"
[[ $(wc -l <"$inputs/removed_59_input.tsv") -eq 59 ]] ||
  precheck_fail "removed residual input count is not 59"
[[ $(wc -l <"$inputs/removed_59_triage.tsv") -eq 60 ]] ||
  precheck_fail "removed residual triage count is not 59 data rows"
[[ $(wc -l <"$inputs/baseline_exports.tsv") -eq 21842 ]] ||
  precheck_fail "baseline export snapshot count is not 21842"
git bundle list-heads "$inputs/chromium_stage4.bundle" | grep -Fqx \
  "$source_commit refs/heads/spike/libcxx-m144" ||
  precheck_fail "source bundle does not expose the fixed candidate ref"

for repo in "$source_repo" "$backup_repo"; do
  [[ -z $(git -C "$repo" status --porcelain=v1 --untracked-files=all) ]] ||
    precheck_fail "repository is not clean: $repo"
  git -C "$repo" cat-file -e "$base_commit^{commit}" 2>/dev/null ||
    precheck_fail "base commit $base_commit is absent from $repo"
done
backup_head=$(git -C "$backup_repo" rev-parse HEAD)
[[ "$backup_head" == "$base_commit" ]] ||
  precheck_fail "chromium-efl_backup HEAD=$backup_head expected=$base_commit"
source_head=$(git -C "$source_repo" rev-parse HEAD)
[[ "$source_head" == "$base_commit" || "$source_head" == "$source_commit" ]] ||
  precheck_fail "chromium-efl HEAD=$source_head expected base=$base_commit or candidate=$source_commit"
git -C "$source_repo" bundle verify "$inputs/chromium_stage4.bundle" \
  >"$logs/source_bundle_verify.txt" 2>&1 ||
  precheck_fail "source bundle verification failed; see logs/source_bundle_verify.txt"

mem_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
[[ "$mem_kib" =~ ^[0-9]+$ ]] || precheck_fail "cannot read MemTotal"
mem_gib=$((mem_kib / 1024 / 1024))
((mem_gib >= 64)) || precheck_fail "RAM ${mem_gib}GiB is below the 64GiB threshold"
disk_avail_kib=$(df -Pk "$analysis_root" | awk 'NR==2 {print $4}')
[[ "$disk_avail_kib" =~ ^[0-9]+$ ]] || precheck_fail "cannot read free disk space"
disk_avail_gib=$((disk_avail_kib / 1024 / 1024))
((disk_avail_gib >= 350)) ||
  precheck_fail "free disk ${disk_avail_gib}GiB is below the 350GiB threshold"
cores=$(nproc)
[[ "$cores" =~ ^[0-9]+$ ]] || precheck_fail "cannot read CPU count"
((cores >= 16)) || precheck_fail "CPU count $cores is below the 16-core threshold"

jobs_by_mem=$((mem_gib / 3))
jobs=$cores
((jobs > jobs_by_mem)) && jobs=$jobs_by_mem
((jobs > 64)) && jobs=64
((jobs >= 8)) || precheck_fail "derived job count $jobs is below 8"
memory_max_mib=$((mem_kib / 1024 * 80 / 100))
memory_high_mib=$((memory_max_mib * 90 / 100))
cpu_quota=$((jobs * 100))
gbs_root="$HOME/GBS-ROOT-TIZEN-UNIFIED-LLVM"

systemd-run --user --wait --pipe --quiet \
  --property=MemoryMax=512M --property=CPUQuota=100% /usr/bin/true \
  >"$logs/systemd_user_probe.txt" 2>&1 ||
  precheck_fail "systemd --user transient services are unavailable"

started=1
{
  printf 'ANALYSIS_ROOT=%q\n' "$analysis_root"
  printf 'SOURCE_REPO=%q\n' "$source_repo"
  printf 'BACKUP_REPO=%q\n' "$backup_repo"
  printf 'SOURCE_COMMIT=%q\n' "$source_commit"
  printf 'SOURCE_BASE_COMMIT=%q\n' "$base_commit"
  printf 'INPUTS_DIR=%q\n' "$inputs"
  printf 'LOG_DIR=%q\n' "$logs"
  printf 'GENERATED_DIR=%q\n' "$generated"
  printf 'GBS_CONF=%q\n' "$inputs/gbs_llvm.conf"
  printf 'GBS_ROOT=%q\n' "$gbs_root"
  printf 'QEMU_ARM=%q\n' "$qemu_arm"
  printf 'BUILD_JOBS=%q\n' "$jobs"
  printf 'MEMORY_MAX=%q\n' "${memory_max_mib}M"
  printf 'MEMORY_HIGH=%q\n' "${memory_high_mib}M"
  printf 'CPU_QUOTA=%q\n' "${cpu_quota}%"
} >"$generated/stage4.env"

{
  echo "timestamp=$(date --iso-8601=seconds)"
  echo "analysis_root=$analysis_root"
  echo "source_repo=$source_repo"
  echo "backup_repo=$backup_repo"
  echo "source_head=$source_head"
  echo "backup_head=$backup_head"
  echo "source_commit=$source_commit"
  echo "base_commit=$base_commit"
  echo "memory_gib=$mem_gib"
  echo "disk_available_gib=$disk_avail_gib"
  echo "cpu_count=$cores"
  echo "build_jobs=$jobs"
  echo "memory_max=${memory_max_mib}M"
  echo "memory_high=${memory_high_mib}M"
  echo "cpu_quota=${cpu_quota}%"
  echo "qemu_arm=$qemu_arm"
} >"$logs/precheck_summary.txt"

{
  bash --version | head -1
  git --version
  gbs --version
  readelf --version | head -1
  nm --version | head -1
  "$qemu_arm" --version | head -1
  systemd-run --version | head -1
  uname -a
  free -h
  df -h "$analysis_root"
} >"$logs/tool_versions.txt" 2>&1 || step_fail "failed to record tool versions"

trap - EXIT
echo "[STEP-0-OK] jobs=$jobs memory_max=${memory_max_mib}M disk_available=${disk_avail_gib}GiB"

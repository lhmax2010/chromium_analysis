#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
env_file=${STAGE4_ENV_FILE:-"$script_dir/generated/stage4.env"}

if [[ ${1:-} == "--worker" ]]; then
  # shellcheck disable=SC1090
  source "$env_file"
  cd "$SOURCE_REPO"
  exec /usr/bin/time -v -o "$LOG_DIR/build_resource_time.txt" \
    gbs -c "$GBS_CONF" build \
      -A armv7l \
      --include-all \
      --overwrite \
      --define "_costomized_smp_mflags -j${BUILD_JOBS}" \
      .
fi

started=0
failure_reported=0
precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] run_build.sh: $*" >&2
  exit 1
}
step_fail() {
  failure_reported=1
  echo "[STEP-2-FAIL] run_build.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-2-FAIL] run_build.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] run_build.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

[[ -f "$env_file" ]] || precheck_fail "missing generated/stage4.env"
# shellcheck disable=SC1090
source "$env_file"
required_tools=(
  awk bash basename cat cmp cp curl date df dirname find gbs git grep head mktemp
  sha256sum sort stat systemctl systemd-run tee touch wc
)
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || precheck_fail "missing tool: $tool"
done
[[ -x /usr/bin/time ]] || precheck_fail "missing /usr/bin/time"
(cd "$INPUTS_DIR" && sha256sum -c SHA256SUMS) >"$LOG_DIR/step2_input_sha256.txt" 2>&1 ||
  precheck_fail "input SHA256 verification failed"
[[ -f "$GBS_CONF" ]] || precheck_fail "missing GBS config: $GBS_CONF"
[[ $(git -C "$SOURCE_REPO" rev-parse HEAD) == "$SOURCE_COMMIT" ]] ||
  precheck_fail "chromium-efl is not at fixed commit $SOURCE_COMMIT"
[[ -z $(git -C "$SOURCE_REPO" status --porcelain=v1 --untracked-files=all) ]] ||
  precheck_fail "chromium-efl is not clean before build"
[[ $(git -C "$BACKUP_REPO" rev-parse HEAD) == "$SOURCE_BASE_COMMIT" ]] ||
  precheck_fail "chromium-efl_backup is not at fixed baseline commit"
mem_total_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_available_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
[[ "$mem_total_kib" =~ ^[0-9]+$ ]] || precheck_fail "cannot read MemTotal"
[[ "$mem_available_kib" =~ ^[0-9]+$ ]] || precheck_fail "cannot read MemAvailable"
mem_total_gib=$((mem_total_kib / 1024 / 1024))
mem_available_gib=$((mem_available_kib / 1024 / 1024))
disk_gib=$(df -Pk "$ANALYSIS_ROOT" | awk 'NR==2 {print int($4/1024/1024)}')
((mem_total_gib >= 64)) || precheck_fail "total RAM ${mem_total_gib}GiB is below 64GiB"
((mem_available_gib >= 48)) ||
  precheck_fail "MemAvailable ${mem_available_gib}GiB is below 48GiB; stop other workloads and rerun only the precheck"
((disk_gib >= 275)) || precheck_fail "free disk ${disk_gib}GiB is below 275GiB"
[[ "$MEMORY_MAX" =~ ^[0-9]+M$ ]] || precheck_fail "invalid MEMORY_MAX: $MEMORY_MAX"
configured_memory_max_mib=${MEMORY_MAX%M}
safe_memory_max_mib=$((mem_available_kib / 1024 - 16384))
total_cap_mib=$((mem_total_kib / 1024 * 75 / 100))
((safe_memory_max_mib > total_cap_mib)) && safe_memory_max_mib=$total_cap_mib
((safe_memory_max_mib >= configured_memory_max_mib)) ||
  precheck_fail "current safe memory budget ${safe_memory_max_mib}MiB is below configured MemoryMax ${configured_memory_max_mib}MiB"
[[ ! -e "$GENERATED_DIR/build_started.marker" ]] ||
  precheck_fail "build marker already exists; do not rerun in this checkout"

base_repo_url=https://download.tizen.org/snapshots/TIZEN/Tizen/Tizen-Base-Toolchain/reference/repos/standard/packages/repodata/repomd.xml
unified_repo_url=https://download.tizen.org/snapshots/TIZEN/Tizen/Tizen-Unified-Toolchain/reference/repos/standard/packages/repodata/repomd.xml
proxy_names=(
  HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY
  http_proxy https_proxy ftp_proxy no_proxy
)
proxy_env_args=()
for proxy_name in "${proxy_names[@]}"; do
  proxy_env_args+=(--setenv="$proxy_name=${!proxy_name-}")
done
curl_bin=$(command -v curl)
for entry in "base:$base_repo_url" "unified:$unified_repo_url"; do
  label=${entry%%:*}
  url=${entry#*:}
  probe_unit="chromium-stage4-repo-${label}-$(date +%Y%m%d%H%M%S%N)"
  systemd-run --user --unit="$probe_unit" --wait --pipe --quiet \
    --property=MemoryMax=512M --property=CPUQuota=100% \
    "${proxy_env_args[@]}" \
    "$curl_bin" -fsSL --connect-timeout 15 --max-time 45 -D - -o /dev/null "$url" \
    >"$LOG_DIR/step2_repo_${label}_service_probe.txt" 2>&1 ||
    precheck_fail "$label repository is unreachable from the build service environment"
done

tmp_dir=$(mktemp -d "$GENERATED_DIR/filter-check.XXXXXX")
"$SOURCE_REPO/tizen_src/build/abi/generate_libcxx_export_filters.sh" \
  "$SOURCE_REPO/tizen_src/build/abi/internal_cr_allowlist.tsv" \
  "$tmp_dir/v8.filter" "$tmp_dir/node.filter" \
  "$SOURCE_REPO/tizen_src/build/abi/node_nonstd_export_allowlist.tsv" \
  >"$LOG_DIR/filter_regeneration.txt" 2>&1
cmp -s "$tmp_dir/v8.filter" "$INPUTS_DIR/v8_tizen.filter" ||
  precheck_fail "generated V8 filter differs from checked input"
cmp -s "$tmp_dir/node.filter" "$INPUTS_DIR/node.filter" ||
  precheck_fail "generated Node filter differs from checked input"
cmp -s "$SOURCE_REPO/tizen_src/build/abi/node_nonstd_export_allowlist.tsv" \
  "$INPUTS_DIR/node_nonstd_export_allowlist.tsv" ||
  precheck_fail "source stable Node allowlist differs from packaged input"
node_exact_cxx=$(grep -c '^    _Z.*;$' "$tmp_dir/node.filter")
node_cr=$(grep '^    _Z.*;$' "$tmp_dir/node.filter" | grep -c 'NSt4__Cr' || true)
((node_exact_cxx == 361)) || precheck_fail "Node exact C++ export count is not 361"
((node_cr == 7)) || precheck_fail "Node __Cr export count is not 7"
while IFS= read -r symbol; do
  awk -F '\t' -v wanted="$symbol" '$2==wanted {found=1} END {exit !found}' \
    "$INPUTS_DIR/node_nonstd_export_allowlist.tsv" ||
    precheck_fail "Retry 1 missing symbol remains absent: $symbol"
done <"$INPUTS_DIR/retry1_visible_undefined.demangled.txt"

bridge_scan="$LOG_DIR/bridge_header_c_purity_scan.txt"
: >"$bridge_scan"
grep -RInE --include='*.h' --include='*.hpp' \
  'std::|#[[:space:]]*include[[:space:]]*<(string|vector|map|memory|set|list|deque|array|unordered_map|unordered_set)>' \
  "$SOURCE_REPO/wrt/cxx_wrapper" >"$bridge_scan" || true
bridge_scan_hits=$(wc -l <"$bridge_scan")
echo "bridge_header_cpp_hits=$bridge_scan_hits" >>"$bridge_scan"
((bridge_scan_hits == 0)) || precheck_fail "bridge header C purity scan is nonzero"

started=1
touch "$GENERATED_DIR/build_started.marker"
unit="chromium-stage4-build-$(date +%Y%m%d%H%M%S)"
{
  echo "unit=$unit"
  echo "command=gbs -c $GBS_CONF build -A armv7l --include-all --overwrite --define '_costomized_smp_mflags -j${BUILD_JOBS}' ."
  echo "MemoryMax=$MEMORY_MAX"
  echo "MemoryHigh=$MEMORY_HIGH"
  echo "MemorySwapMax=0"
  echo "CPUQuota=$CPU_QUOTA"
  echo "Nice=5"
  echo "MemAvailable=${mem_available_gib}GiB"
  echo "repository_preflight=base:OK,unified:OK"
  echo "proxy_forwarding=explicit"
  echo "started=$(date --iso-8601=seconds)"
} >"$LOG_DIR/build_invocation.txt"

set +e
systemd-run --user --unit="$unit" --wait --pipe --quiet \
  --property="MemoryMax=$MEMORY_MAX" \
  --property="MemoryHigh=$MEMORY_HIGH" \
  --property="MemorySwapMax=0" \
  --property="CPUQuota=$CPU_QUOTA" \
  --property="Nice=5" \
  "${proxy_env_args[@]}" \
  --setenv="STAGE4_ENV_FILE=$env_file" \
  "$script_dir/run_build.sh" --worker 2>&1 | tee "$LOG_DIR/build_console.log"
build_rc=${PIPESTATUS[0]}
set -e
echo "build_exit_code=$build_rc" >>"$LOG_DIR/build_invocation.txt"
echo "finished=$(date --iso-8601=seconds)" >>"$LOG_DIR/build_invocation.txt"
systemctl --user show "$unit" \
  --property=Id,LoadState,ActiveState,SubState,Result,ExecMainCode,ExecMainStatus,CPUUsageNSec,MemoryPeak,MemoryMax,MemoryHigh,MemorySwapMax,CPUQuotaPerSecUSec \
  >"$LOG_DIR/build_service_result.txt" 2>&1 || true
((build_rc == 0)) || step_fail "GBS exited $build_rc; do not modify code or retry"

mapfile -t rpm_paths < <(find "$GBS_ROOT/local/repos" -type f \
  -name 'chromium-efl*.rpm' -newer "$GENERATED_DIR/build_started.marker" -print | LC_ALL=C sort)
(( ${#rpm_paths[@]} == 8 )) ||
  step_fail "expected 8 newly written chromium-efl RPMs, found ${#rpm_paths[@]}"
printf '%s\n' "${rpm_paths[@]}" >"$GENERATED_DIR/candidate_rpm_paths.txt"
{
  echo -e 'rpm_path\tbytes\tsha256'
  for rpm_path in "${rpm_paths[@]}"; do
    printf '%s\t%s\t' "$rpm_path" "$(stat -c %s "$rpm_path")"
    sha256sum "$rpm_path" | awk '{print $1}'
  done
} >"$LOG_DIR/candidate_rpm_inventory.tsv"

mapfile -t args_candidates < <(find "$GBS_ROOT/local/BUILD-ROOTS" -type f \
  -path '*/home/abuild/rpmbuild/BUILD/chromium-efl-*/out*/args.gn' \
  -printf '%T@\t%p\n' | LC_ALL=C sort -n)
(( ${#args_candidates[@]} >= 1 )) || step_fail "cannot locate generated args.gn"
last_args_index=$((${#args_candidates[@]} - 1))
args_gn=${args_candidates[$last_args_index]#*$'\t'}
build_out=$(dirname "$args_gn")
build_source=$(dirname "$build_out")
printf '%s\n' "$args_gn" >"$GENERATED_DIR/args_gn_path.txt"
printf '%s\n' "$build_out" >"$GENERATED_DIR/build_out_path.txt"
printf '%s\n' "$build_source" >"$GENERATED_DIR/build_source_path.txt"
cp "$args_gn" "$LOG_DIR/args.gn"
"$SOURCE_REPO/buildtools/linux64/gn" args "$build_out" --list --short \
  >"$LOG_DIR/gn_args_list_short.txt" 2>&1 || step_fail "gn args --list --short failed"
{
  cat "$LOG_DIR/args.gn"
  echo
  echo '----- gn args --list --short -----'
  cat "$LOG_DIR/gn_args_list_short.txt"
} >"$LOG_DIR/gn_resolved.txt"
for expected in \
  'is_clang = true' \
  'use_custom_libcxx = true' \
  'use_custom_libcxx_for_host = true' \
  'use_lld = true' \
  'use_thin_lto = true'; do
  grep -Fxq "$expected" "$LOG_DIR/gn_args_list_short.txt" ||
    step_fail "resolved GN arg missing: $expected"
done

: >"$GENERATED_DIR/unstripped_dso_paths.tsv"
for dso in libchromium-impl.so libv8.so libnode.so; do
  match=$(find "$build_out" -type f -name "$dso" -printf '%s\t%p\n' |
    LC_ALL=C sort -nr | head -1)
  [[ -n "$match" ]] || step_fail "unstripped output not found: $dso"
  printf '%s\t%s\n' "$dso" "${match#*$'\t'}" >>"$GENERATED_DIR/unstripped_dso_paths.tsv"
done

touch "$GENERATED_DIR/build_success.marker"
trap - EXIT
echo "[STEP-2-OK] rpms=8 jobs=$BUILD_JOBS source_commit=$SOURCE_COMMIT node_nonstd=354 node_cr=7"

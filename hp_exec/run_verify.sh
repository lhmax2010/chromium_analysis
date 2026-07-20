#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
env_file="$script_dir/generated/stage4.env"
started=0
failure_reported=0

precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] run_verify.sh: $*" >&2
  exit 1
}
step_fail() {
  failure_reported=1
  echo "[STEP-3-FAIL] run_verify.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-3-FAIL] run_verify.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] run_verify.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

[[ -f "$env_file" ]] || precheck_fail "missing generated/stage4.env"
# shellcheck disable=SC1090
source "$env_file"
required_tools=(
  awk bash basename c++filt cat comm cp cpio cut df dirname file find git grep
  head mkdir mktemp nm paste python3 readelf rpm2cpio sed sha256sum size sort
  stat tail tee timeout touch tr uniq wc
)
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || precheck_fail "missing tool: $tool"
done
[[ -x "$QEMU_ARM" ]] || precheck_fail "qemu executable missing: $QEMU_ARM"
(cd "$INPUTS_DIR" && sha256sum -c SHA256SUMS) >"$LOG_DIR/step3_input_sha256.txt" 2>&1 ||
  precheck_fail "input SHA256 verification failed"
[[ -f "$GENERATED_DIR/build_success.marker" ]] || precheck_fail "missing build success marker"
[[ -f "$GENERATED_DIR/candidate_rpm_paths.txt" ]] || precheck_fail "missing candidate RPM list"
[[ -f "$GENERATED_DIR/build_source_path.txt" ]] || precheck_fail "missing build source path"
[[ -f "$GENERATED_DIR/unstripped_dso_paths.tsv" ]] || precheck_fail "missing unstripped DSO list"
[[ $(git -C "$SOURCE_REPO" rev-parse HEAD) == "$SOURCE_COMMIT" ]] ||
  precheck_fail "source commit changed after build"
mem_gib=$(awk '/^MemTotal:/ {print int($2/1024/1024)}' /proc/meminfo)
disk_gib=$(df -Pk "$ANALYSIS_ROOT" | awk 'NR==2 {print int($4/1024/1024)}')
((mem_gib >= 64)) || precheck_fail "RAM ${mem_gib}GiB is below 64GiB"
((disk_gib >= 100)) || precheck_fail "free disk ${disk_gib}GiB is below 100GiB for verification"
[[ ! -e "$script_dir/work" ]] || precheck_fail "hp_exec/work already exists; do not rerun"
[[ ! -e "$script_dir/verify_results" ]] || precheck_fail "verify_results already exists; do not rerun"
while IFS= read -r rpm_path; do
  [[ -f "$rpm_path" ]] || precheck_fail "RPM no longer exists: $rpm_path"
done <"$GENERATED_DIR/candidate_rpm_paths.txt"

started=1
work="$script_dir/work"
candidate_root="$work/candidate_root"
verify="$script_dir/verify_results"
gate_out="$verify/gate_v2"
mkdir -p "$candidate_root" "$verify"

: >"$LOG_DIR/rpm_extract.log"
while IFS= read -r rpm_path; do
  case "$(basename "$rpm_path")" in
    *-debuginfo-*|*-debugsource-*) continue ;;
  esac
  echo "===== $rpm_path =====" >>"$LOG_DIR/rpm_extract.log"
  rpm2cpio "$rpm_path" | (cd "$candidate_root" && cpio -idmu --quiet --no-absolute-filenames) \
    >>"$LOG_DIR/rpm_extract.log" 2>&1 || step_fail "RPM extraction failed: $rpm_path"
done <"$GENERATED_DIR/candidate_rpm_paths.txt"

set +e
"$INPUTS_DIR/abi_gate_v2.sh" \
  --candidate-root "$candidate_root" \
  --baseline-exports "$INPUTS_DIR/baseline_exports.tsv" \
  --added-allowlist "$INPUTS_DIR/expected_added_exports.tsv" \
  --internal-cxx-allowlist "$INPUTS_DIR/internal_cr_allowlist.tsv" \
  --bridge-allowlist "$INPUTS_DIR/bridge_export_allowlist.txt" \
  --out "$gate_out" 2>&1 | tee "$LOG_DIR/gate_v2_console.txt"
gate_rc=${PIPESTATUS[0]}
set -e
((gate_rc == 0)) || step_fail "gate v2 returned $gate_rc"

assert_summary() {
  local key=$1 expected=$2
  grep -Fxq "$key=$expected" "$gate_out/summary.txt" ||
    step_fail "gate summary expected $key=$expected"
}
assert_summary status PASS
assert_summary G1_full_signature_export_hits 34
assert_summary G1_allowlisted 34
assert_summary G1_unallowlisted 0
assert_summary G1_internal_allowlist_missing 0
assert_summary G2_full_signature_und_hits 41
assert_summary G2_allowlisted 41
assert_summary G2_unallowlisted 0
assert_summary G3_needed_libcxx_hits 0
assert_summary added_exports_unallowlisted 0
assert_summary bridge_count 1
assert_summary bridge_unexpected 0
assert_summary bridge_missing 0
assert_summary bridge_ZNSt_exports 0
assert_summary bridge_NEEDED_libstdcxx 1

candidate_exports="$gate_out/candidate_exports.tsv"
expected_hidden="$INPUTS_DIR/expected_hidden_cr_exports.tsv"
hidden_still_exported="$verify/expected_hidden_cr_still_exported.tsv"
comm -12 "$expected_hidden" "$candidate_exports" >"$hidden_still_exported"
[[ ! -s "$hidden_still_exported" ]] || step_fail "one or more of the expected 454 exports remain visible"
[[ $(wc -l <"$expected_hidden") -eq 454 ]] || step_fail "hidden input count changed"

expected_added="$INPUTS_DIR/expected_added_exports.tsv"
comm -23 "$expected_added" "$gate_out/added_exports.tsv" >"$verify/expected_added_missing.tsv"
comm -13 "$expected_added" "$gate_out/added_exports.tsv" >"$verify/expected_added_unexpected.tsv"
[[ ! -s "$verify/expected_added_unexpected.tsv" ]] || step_fail "unexpected added export exists"
observed_added=$(wc -l <"$gate_out/added_exports.tsv")
((observed_added >= 34 && observed_added <= 166)) ||
  step_fail "added export count $observed_added is outside the allowed range 34..166"

comm -23 "$gate_out/baseline_exports.normalized.tsv" "$candidate_exports" \
  >"$verify/removed_exports.tsv"
comm -13 "$gate_out/baseline_exports.normalized.tsv" "$candidate_exports" \
  >"$verify/added_exports_recomputed.tsv"
cut -f2 "$verify/removed_exports.tsv" | c++filt >"$verify/removed_exports.demangled.txt"
paste "$verify/removed_exports.tsv" "$verify/removed_exports.demangled.txt" \
  >"$verify/removed_exports.demangled.tsv"
cut -f2 "$verify/removed_exports.tsv" | LC_ALL=C sort -u >"$verify/removed_symbols.txt"
cut -f1 "$INPUTS_DIR/removed_59_input.tsv" | LC_ALL=C sort -u >"$verify/removed_59_symbols.txt"
comm -23 "$verify/removed_59_symbols.txt" "$verify/removed_symbols.txt" \
  >"$verify/removed_59_not_in_stage4_removed.txt"
[[ ! -s "$verify/removed_59_not_in_stage4_removed.txt" ]] ||
  step_fail "one or more Stage 3 residual 59 symbols is not removed"

: >"$verify/dyn_sections.tsv"
: >"$verify/all_packaged_dso_dynsym.txt"
: >"$verify/all_packaged_dso_dynamic.txt"
echo -e 'relative_path\tsection\tbytes' >"$verify/dyn_sections.tsv"
packaged_dso_count=0
while IFS= read -r -d '' elf; do
  readelf -h "$elf" >/dev/null 2>&1 || continue
  rel=${elf#"$candidate_root"/}
  packaged_dso_count=$((packaged_dso_count + 1))
  {
    echo "===== $rel ====="
    readelf --dyn-syms -W "$elf"
  } >>"$verify/all_packaged_dso_dynsym.txt"
  {
    echo "===== $rel ====="
    readelf -d -W "$elf"
  } >>"$verify/all_packaged_dso_dynamic.txt"
  size -A -d "$elf" | awk -v rel="$rel" 'BEGIN{OFS="\t"}
    $1==".dynsym" || $1==".dynstr" {print rel,$1,$2}' >>"$verify/dyn_sections.tsv"
done < <(find "$candidate_root" -type f \( -name '*.so' -o -name '*.so.*' \) \
  ! -path '*/usr/lib/debug/*' -print0 | LC_ALL=C sort -z)
((packaged_dso_count > 0)) || step_fail "no packaged DSO found"

echo -e 'dso\tpath\tbytes\tsha256' >"$verify/primary_dso_sizes.tsv"
: >"$GENERATED_DIR/primary_dso_paths.txt"
for dso in libv8.so libnode.so libchromium-ewk.so libwrt-c++wrapper.so; do
  mapfile -d '' matches < <(find "$candidate_root" -type f -name "$dso" -print0)
  (( ${#matches[@]} == 1 )) || step_fail "expected one packaged $dso, found ${#matches[@]}"
  path=${matches[0]}
  printf '%s\n' "$path" >>"$GENERATED_DIR/primary_dso_paths.txt"
  printf '%s\t%s\t%s\t' "$dso" "$path" "$(stat -c %s "$path")" >>"$verify/primary_dso_sizes.tsv"
  sha256sum "$path" | awk '{print $1}' >>"$verify/primary_dso_sizes.tsv"
done

echo -e 'rpm_path\tbytes\tsha256' >"$verify/candidate_rpm_inventory.tsv"
candidate_rpm_total=0
while IFS= read -r rpm_path; do
  bytes=$(stat -c %s "$rpm_path")
  candidate_rpm_total=$((candidate_rpm_total + bytes))
  printf '%s\t%s\t' "$rpm_path" "$bytes" >>"$verify/candidate_rpm_inventory.tsv"
  sha256sum "$rpm_path" | awk '{print $1}' >>"$verify/candidate_rpm_inventory.tsv"
done <"$GENERATED_DIR/candidate_rpm_paths.txt"
baseline_rpm_total=$(<"$INPUTS_DIR/baseline_rpm_total_bytes.txt")
{
  echo "baseline_rpm_total_bytes=$baseline_rpm_total"
  echo "candidate_rpm_total_bytes=$candidate_rpm_total"
  echo "rpm_total_delta_bytes=$((candidate_rpm_total - baseline_rpm_total))"
} >"$verify/rpm_size_summary.txt"

build_source=$(<"$GENERATED_DIR/build_source_path.txt")
sysroot=${build_source%%/home/abuild/*}
[[ -x "$sysroot/usr/lib/ld-linux.so.3" ]] || step_fail "ARM loader absent from sysroot: $sysroot"
clang="$SOURCE_REPO/tizen_src/buildtools/llvm-22/bin/clang"
[[ -x "$clang" ]] || step_fail "bundled clang missing: $clang"
probe_c="$work/dlopen_probe.c"
probe_bin="$work/dlopen_probe.arm"
cp "$INPUTS_DIR/dlopen_probe.c" "$probe_c"
set +e
"$clang" --target=armv7l-tizen-linux-gnueabi --sysroot="$sysroot" \
  -fuse-ld=lld -march=armv7-a -Wl,--dynamic-linker=/lib/ld-linux.so.3 \
  "$probe_c" -ldl -o "$probe_bin" >"$LOG_DIR/dlopen_probe_compile.txt" 2>&1
probe_compile_rc=$?
set -e
((probe_compile_rc == 0)) || step_fail "ARM dlopen probe compilation failed"
readelf -h "$probe_bin" >"$LOG_DIR/dlopen_probe_elf_header.txt"

candidate_lib_dirs=$(while IFS= read -r path; do dirname "$path"; done \
  <"$GENERATED_DIR/primary_dso_paths.txt" | LC_ALL=C sort -u | paste -sd: -)
guest_ld_path="$candidate_lib_dirs:/lib:/usr/lib:/usr/lib/hal:/usr/share/chromium-efl/lib"
mapfile -t primary_dsos <"$GENERATED_DIR/primary_dso_paths.txt"
set +e
timeout 180 "$QEMU_ARM" -L "$sysroot" \
  -E LD_BIND_NOW=1 -E "LD_LIBRARY_PATH=$guest_ld_path" \
  "$probe_bin" "${primary_dsos[@]}" >"$LOG_DIR/qemu_ld_bind_now.txt" 2>&1
qemu_rc=$?
set -e
echo "qemu_exit_code=$qemu_rc" >>"$LOG_DIR/qemu_ld_bind_now.txt"
((qemu_rc == 0)) || step_fail "QEMU LD_BIND_NOW dlopen validation failed"
grep -Fxq '[DLOPEN-ALL-OK] count=4' "$LOG_DIR/qemu_ld_bind_now.txt" ||
  step_fail "QEMU dlopen completion marker missing"

echo -e 'dso\ttype\tsymbol' >"$verify/unstripped_runtime_symbol_ownership.tsv"
: >"$verify/unstripped_selected_nm.txt"
: >"$verify/unstripped_selected_dynsym.txt"
while IFS=$'\t' read -r dso path; do
  [[ -f "$path" ]] || step_fail "unstripped DSO disappeared: $path"
  nm_raw="$work/$dso.nm.txt"
  nm -a "$path" >"$nm_raw"
  {
    echo "===== $dso $path ====="
    awk '$3 ~ /^(__cxa_(throw|begin_catch|guard_acquire)|_?Unwind)/ {print}' "$nm_raw"
  } >>"$verify/unstripped_selected_nm.txt"
  awk -v dso="$dso" 'BEGIN{OFS="\t"}
    $3 ~ /^(__cxa_(throw|begin_catch|guard_acquire)|_?Unwind)/ {print dso,$2,$3}' \
    "$nm_raw" >>"$verify/unstripped_runtime_symbol_ownership.tsv"
  {
    echo "===== $dso $path ====="
    readelf --dyn-syms -W "$path" | awk 'NR<4 || /NSt4__Cr|NSt3__1|__cxa_|Unwind/'
  } >>"$verify/unstripped_selected_dynsym.txt"
done <"$GENERATED_DIR/unstripped_dso_paths.tsv"

base_node_version=$(python3 "$SOURCE_REPO/third_party/electron_node/tools/getmoduleversion.py")
[[ "$base_node_version" == "137" ]] || step_fail "base NODE_MODULE_VERSION=$base_node_version expected=137"
grep -Fq 'node_module_version += 1000000' "$SOURCE_REPO/third_party/electron_node/node.gni" ||
  step_fail "NODE_EMBEDDER_MODULE_VERSION offset source line missing"
echo "base_node_module_version=$base_node_version" >"$verify/node_module_version.txt"
echo "stage4_embedder_module_version=$((base_node_version + 1000000))" >>"$verify/node_module_version.txt"

removed_count=$(wc -l <"$verify/removed_exports.tsv")
added_count=$(wc -l <"$verify/added_exports_recomputed.tsv")
unknown_count=$(awk -F= '$1=="unknown_symbols" {print $2}' "$gate_out/summary.txt")
chromium_size=$(awk -F '\t' '$1=="libchromium-ewk.so" {print $3}' "$verify/primary_dso_sizes.tsv")
{
  echo "status=PASS"
  echo "source_commit=$SOURCE_COMMIT"
  echo "packaged_dso_count=$packaged_dso_count"
  echo "hidden_454_still_exported=0"
  echo "G1_allowlisted=34"
  echo "G2_allowlisted=41"
  echo "removed_exports=$removed_count"
  echo "added_exports=$added_count"
  echo "removed_59_present=59"
  echo "unknown_symbols=$unknown_count"
  echo "qemu_ld_bind_now=PASS"
  echo "libchromium_ewk_bytes=$chromium_size"
  echo "baseline_rpm_total_bytes=$baseline_rpm_total"
  echo "candidate_rpm_total_bytes=$candidate_rpm_total"
  echo "rpm_total_delta_bytes=$((candidate_rpm_total - baseline_rpm_total))"
  echo "node_embedder_module_version=$((base_node_version + 1000000))"
} >"$verify/summary.txt"

touch "$GENERATED_DIR/verify_success.marker"
trap - EXIT
echo "[STEP-3-OK] gate=PASS hidden_454=0 qemu_ld_bind_now=PASS added=$added_count removed=$removed_count"

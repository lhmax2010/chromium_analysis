#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
env_file="$script_dir/generated/stage4.env"
started=0
failure_reported=0

precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] prepare_source.sh: $*" >&2
  exit 1
}
step_fail() {
  failure_reported=1
  echo "[STEP-1-FAIL] prepare_source.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-1-FAIL] prepare_source.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] prepare_source.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

[[ -f "$env_file" ]] || precheck_fail "missing generated/stage4.env; run precheck.sh first"
# shellcheck disable=SC1090
source "$env_file"
for tool in awk chmod cmp cp df git grep mktemp sed sha256sum sort wc; do
  command -v "$tool" >/dev/null 2>&1 || precheck_fail "missing tool: $tool"
done
(cd "$INPUTS_DIR" && sha256sum -c SHA256SUMS) >"$LOG_DIR/step1_input_sha256.txt" 2>&1 ||
  precheck_fail "input SHA256 verification failed"
[[ -z $(git -C "$SOURCE_REPO" status --porcelain=v1 --untracked-files=all) ]] ||
  precheck_fail "chromium-efl is not clean"
[[ -z $(git -C "$BACKUP_REPO" status --porcelain=v1 --untracked-files=all) ]] ||
  precheck_fail "chromium-efl_backup is not clean"
[[ $(git -C "$BACKUP_REPO" rev-parse HEAD) == "$SOURCE_BASE_COMMIT" ]] ||
  precheck_fail "chromium-efl_backup is not at $SOURCE_BASE_COMMIT"
mem_available_gib=$(awk '/^MemAvailable:/ {print int($2/1024/1024)}' /proc/meminfo)
disk_gib=$(df -Pk "$ANALYSIS_ROOT" | awk 'NR==2 {print int($4/1024/1024)}')
((mem_available_gib >= 48)) || precheck_fail "MemAvailable ${mem_available_gib}GiB is below 48GiB"
((disk_gib >= 300)) || precheck_fail "free disk ${disk_gib}GiB is below 300GiB"

remote_head=$(git ls-remote "$GERRIT_URL" "refs/heads/$GERRIT_BRANCH" | awk '{print $1}')
[[ "$remote_head" == "$SOURCE_START_COMMIT" ]] ||
  precheck_fail "Gerrit toolchain HEAD=$remote_head expected=$SOURCE_START_COMMIT"

tmp_dir=$(mktemp -d "$GENERATED_DIR/retry2-source-check.XXXXXX")
"$script_dir/generate_node_nonstd_input.sh" \
  "$INPUTS_DIR/baseline_exports.tsv" "$tmp_dir/node_nonstd_export_allowlist.tsv" \
  >"$LOG_DIR/step1_node_allowlist_regeneration.txt" 2>&1
cmp -s "$tmp_dir/node_nonstd_export_allowlist.tsv" \
  "$INPUTS_DIR/node_nonstd_export_allowlist.tsv" ||
  precheck_fail "regenerated stable Node allowlist differs from packaged input"
"$INPUTS_DIR/generate_libcxx_export_filters.sh" \
  "$INPUTS_DIR/internal_cr_allowlist.tsv" \
  "$tmp_dir/v8_tizen.filter" "$tmp_dir/node.filter" \
  "$INPUTS_DIR/node_nonstd_export_allowlist.tsv" \
  >"$LOG_DIR/step1_filter_package_regeneration.txt" 2>&1
cmp -s "$tmp_dir/v8_tizen.filter" "$INPUTS_DIR/v8_tizen.filter" ||
  precheck_fail "packaged V8 filter is not reproducible"
cmp -s "$tmp_dir/node.filter" "$INPUTS_DIR/node.filter" ||
  precheck_fail "packaged Node filter is not reproducible"

while IFS= read -r symbol; do
  awk -F '\t' -v wanted="$symbol" '$2==wanted {found=1} END {exit !found}' \
    "$INPUTS_DIR/node_nonstd_export_allowlist.tsv" ||
    precheck_fail "Retry 1 missing symbol is absent from stable allowlist: $symbol"
done <"$INPUTS_DIR/retry1_visible_undefined.demangled.txt"

started=1
git -C "$SOURCE_REPO" fetch --no-tags "$GERRIT_URL" "refs/heads/$GERRIT_BRANCH" \
  >"$LOG_DIR/step1_gerrit_fetch.txt" 2>&1
[[ $(git -C "$SOURCE_REPO" rev-parse FETCH_HEAD) == "$SOURCE_START_COMMIT" ]] ||
  step_fail "fetched Gerrit HEAD changed after precheck"
git -C "$SOURCE_REPO" checkout --detach "$SOURCE_START_COMMIT" \
  >"$LOG_DIR/step1_checkout.txt" 2>&1
[[ -z $(git -C "$SOURCE_REPO" status --porcelain=v1 --untracked-files=all) ]] ||
  step_fail "source is not clean after fixed checkout"
[[ $(sha256sum "$SOURCE_REPO/tizen_src/build/abi/generate_libcxx_export_filters.sh" | awk '{print $1}') == \
   19dc053976a688157c2b156ddd2cd0b0b1198179f286ba01ed97892225ba8945 ]] ||
  step_fail "source filter generator does not match Retry 1 input"
[[ $(sha256sum "$SOURCE_REPO/third_party/electron_node/node.filter" | awk '{print $1}') == \
   65f2f7c7bf4bdf3c8cb3de179fe0632bb04400b32ed25dbc0306ca485ee22452 ]] ||
  step_fail "source node.filter does not match Retry 1 input"

cp "$INPUTS_DIR/generate_libcxx_export_filters.sh" \
  "$SOURCE_REPO/tizen_src/build/abi/generate_libcxx_export_filters.sh"
cp "$INPUTS_DIR/node_nonstd_export_allowlist.tsv" \
  "$SOURCE_REPO/tizen_src/build/abi/node_nonstd_export_allowlist.tsv"
chmod 755 "$SOURCE_REPO/tizen_src/build/abi/generate_libcxx_export_filters.sh"
"$SOURCE_REPO/tizen_src/build/abi/generate_libcxx_export_filters.sh" \
  "$SOURCE_REPO/tizen_src/build/abi/internal_cr_allowlist.tsv" \
  "$SOURCE_REPO/v8/v8_tizen.filter" \
  "$SOURCE_REPO/third_party/electron_node/node.filter" \
  "$SOURCE_REPO/tizen_src/build/abi/node_nonstd_export_allowlist.tsv" \
  >"$LOG_DIR/step1_source_filter_generation.txt" 2>&1
cmp -s "$SOURCE_REPO/v8/v8_tizen.filter" "$INPUTS_DIR/v8_tizen.filter" ||
  step_fail "source V8 filter differs from packaged output"
cmp -s "$SOURCE_REPO/third_party/electron_node/node.filter" "$INPUTS_DIR/node.filter" ||
  step_fail "source Node filter differs from packaged output"

mapfile -t changed_files < <(git -C "$SOURCE_REPO" status --short | sed 's/^...//' | LC_ALL=C sort)
expected_files=(
  third_party/electron_node/node.filter
  tizen_src/build/abi/generate_libcxx_export_filters.sh
  tizen_src/build/abi/node_nonstd_export_allowlist.tsv
)
[[ ${#changed_files[@]} -eq 3 ]] || step_fail "source change count is not 3"
for i in 0 1 2; do
  [[ ${changed_files[$i]} == "${expected_files[$i]}" ]] ||
    step_fail "unexpected source change: ${changed_files[$i]}"
done
git -C "$SOURCE_REPO" diff --check >"$LOG_DIR/step1_source_diff_check.txt" 2>&1 ||
  step_fail "source diff --check failed"
git -C "$SOURCE_REPO" diff --stat >"$LOG_DIR/step1_source_diff_stat.txt"
git -C "$SOURCE_REPO" add -- "${expected_files[@]}"
git -C "$SOURCE_REPO" -c user.name='Stage4 HP Executor' \
  -c user.email='stage4-executor@localhost' commit \
  -m 'stage4: preserve stable non-STL Node exports' \
  >"$LOG_DIR/step1_source_commit.txt" 2>&1 || step_fail "source fix commit failed"
source_commit=$(git -C "$SOURCE_REPO" rev-parse HEAD)
[[ -z $(git -C "$SOURCE_REPO" status --porcelain=v1 --untracked-files=all) ]] ||
  step_fail "source is not clean after Retry 2 fix commit"
git -C "$SOURCE_REPO" diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort \
  >"$LOG_DIR/step1_source_commit_files.txt"
printf 'SOURCE_COMMIT=%q\n' "$source_commit" >>"$env_file"
printf '%s\n' "$source_commit" >"$GENERATED_DIR/retry2_source_commit.txt"

trap - EXIT
echo "[STEP-1-OK] source_commit=$source_commit source_start=$SOURCE_START_COMMIT backup_commit=$SOURCE_BASE_COMMIT node_nonstd=354 node_cr=7"

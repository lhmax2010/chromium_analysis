#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
env_file="$script_dir/generated/stage4.env"
started=0
failure_reported=0

precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] checkout_source.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-1-FAIL] checkout_source.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] checkout_source.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

[[ -f "$env_file" ]] || precheck_fail "missing generated/stage4.env; run precheck.sh first"
# shellcheck disable=SC1090
source "$env_file"
for tool in awk cmp df git sha256sum; do
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
mem_gib=$(awk '/^MemTotal:/ {print int($2/1024/1024)}' /proc/meminfo)
disk_gib=$(df -Pk "$ANALYSIS_ROOT" | awk 'NR==2 {print int($4/1024/1024)}')
((mem_gib >= 64)) || precheck_fail "RAM ${mem_gib}GiB is below 64GiB"
((disk_gib >= 350)) || precheck_fail "free disk ${disk_gib}GiB is below 350GiB"

started=1
git -C "$SOURCE_REPO" fetch "$INPUTS_DIR/chromium_stage4.bundle" \
  refs/heads/spike/libcxx-m144 >"$LOG_DIR/step1_bundle_fetch.txt" 2>&1
[[ $(git -C "$SOURCE_REPO" rev-parse FETCH_HEAD) == "$SOURCE_COMMIT" ]]
git -C "$SOURCE_REPO" checkout --detach "$SOURCE_COMMIT" \
  >"$LOG_DIR/step1_checkout.txt" 2>&1
[[ $(git -C "$SOURCE_REPO" rev-parse HEAD) == "$SOURCE_COMMIT" ]]
[[ -z $(git -C "$SOURCE_REPO" status --porcelain=v1 --untracked-files=all) ]]

cmp -s "$SOURCE_REPO/tizen_src/build/abi/internal_cr_allowlist.tsv" \
  "$INPUTS_DIR/internal_cr_allowlist.tsv"
cmp -s "$SOURCE_REPO/v8/v8_tizen.filter" "$INPUTS_DIR/v8_tizen.filter"
cmp -s "$SOURCE_REPO/third_party/electron_node/node.filter" "$INPUTS_DIR/node.filter"

{
  git -C "$SOURCE_REPO" show -s --format='candidate=%H%nsubject=%s%nparents=%P' HEAD
  git -C "$BACKUP_REPO" show -s --format='backup=%H%nsubject=%s' HEAD
  git -C "$SOURCE_REPO" diff-tree --no-commit-id --name-status -r HEAD
} >"$LOG_DIR/step1_source_identity.txt"

trap - EXIT
echo "[STEP-1-OK] source_commit=$SOURCE_COMMIT backup_commit=$SOURCE_BASE_COMMIT"

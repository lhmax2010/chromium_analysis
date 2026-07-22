#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
analysis_root=$(cd "$script_dir/.." && pwd)
inputs="$script_dir/inputs"
started=0
failure_reported=0

precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] collect_results.sh: $*" >&2
  exit 1
}
step_fail() {
  failure_reported=1
  echo "[STEP-4-FAIL] collect_results.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-4-FAIL] collect_results.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] collect_results.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

for tool in awk basename cp date df file find git grep mkdir sha256sum sort stat tar; do
  command -v "$tool" >/dev/null 2>&1 || precheck_fail "missing tool: $tool"
done
[[ -f "$inputs/SHA256SUMS" ]] || precheck_fail "missing inputs/SHA256SUMS"
(cd "$inputs" && sha256sum -c SHA256SUMS) >/dev/null 2>&1 ||
  precheck_fail "input SHA256 verification failed"
mem_gib=$(awk '/^MemTotal:/ {print int($2/1024/1024)}' /proc/meminfo)
disk_gib=$(df -Pk "$analysis_root" | awk 'NR==2 {print int($4/1024/1024)}')
((mem_gib >= 2)) || precheck_fail "RAM ${mem_gib}GiB is below the 2GiB collection threshold"
((disk_gib >= 2)) || precheck_fail "free disk ${disk_gib}GiB is below the 2GiB collection threshold"
archive="$script_dir/results_stage4.tar.gz"
archive_sha="$script_dir/results_stage4.tar.gz.sha256"
[[ ! -e "$archive" && ! -e "$archive_sha" ]] ||
  precheck_fail "results archive already exists; do not overwrite it"

started=1
stamp=$(date +%Y%m%d_%H%M%S)
staging="$script_dir/return_stage4_$stamp"
mkdir "$staging"

for dir in logs generated verify_results; do
  if [[ -d "$script_dir/$dir" ]]; then
    cp -a "$script_dir/$dir" "$staging/$dir"
  fi
done
if [[ -f "$script_dir/generated/stage4.env" ]]; then
  awk '!/^(HTTP_PROXY|HTTPS_PROXY|FTP_PROXY|NO_PROXY|http_proxy|https_proxy|ftp_proxy|no_proxy)=/' \
    "$script_dir/generated/stage4.env" >"$staging/generated/stage4.env"
fi
mkdir "$staging/package_inputs"
for input in \
  SHA256SUMS SOURCE_COMMIT SOURCE_BASE_COMMIT EVIDENCE_SOURCE_COMMIT \
  baseline_rpm_total_bytes.txt expected_added_exports.tsv \
  expected_hidden_cr_exports.tsv internal_cr_allowlist.tsv \
  removed_59_triage.tsv; do
  cp "$inputs/$input" "$staging/package_inputs/$input"
done
cp "$script_dir/GUIDE.md" "$script_dir/ANALYSIS_PLAN.md" \
  "$script_dir/RETRY_V2_NOTES.md" "$staging/"

{
  echo "collected=$(date --iso-8601=seconds)"
  echo "analysis_head=$(git -C "$analysis_root" rev-parse HEAD)"
  echo "analysis_status_begin"
  git -C "$analysis_root" status --short
  echo "analysis_status_end"
  if [[ -d "$analysis_root/../chromium-efl/.git" ]]; then
    git -C "$analysis_root/../chromium-efl" show -s \
      --format='source_head=%H%nsource_subject=%s%nsource_parents=%P' HEAD
    git -C "$analysis_root/../chromium-efl" diff-tree --no-commit-id --name-status -r HEAD
  else
    echo "source_repo=ABSENT"
  fi
} >"$staging/repository_state.txt"

{
  echo "[STEP-4-OK] result collection completed"
  if [[ -f "$script_dir/generated/verify_success.marker" ]]; then
    echo "run_outcome=STEP-3-OK"
  elif [[ -f "$script_dir/generated/build_success.marker" ]]; then
    echo "run_outcome=STEP-3-FAIL_OR_NOT_RUN"
  elif [[ -f "$script_dir/generated/build_started.marker" ]]; then
    echo "run_outcome=STEP-2-FAIL"
  elif [[ -f "$script_dir/generated/stage4.env" ]]; then
    echo "run_outcome=STEP-1-FAIL_OR_NOT_RUN"
  else
    echo "run_outcome=STEP-0-FAIL"
  fi
  echo "binary_payloads_included=0"
  echo "rpm_payloads_included=0"
  echo "rootfs_or_out_directories_included=0"
} >"$staging/collection_summary.txt"

forbidden="$staging/forbidden_payloads.txt"
: >"$forbidden"
find "$staging" -type f \( -name '*.rpm' -o -name '*.o' -o -name '*.a' \
  -o -name '*.so' -o -name '*.so.[0-9]*' \) -print >>"$forbidden"
while IFS= read -r path; do
  if file -b "$path" | grep -q '^ELF '; then
    echo "$path" >>"$forbidden"
  fi
done < <(find "$staging" -type f -print)
[[ ! -s "$forbidden" ]] || step_fail "forbidden binary payload detected in result staging"

find "$staging" -type f -printf '%P\t%s\n' | LC_ALL=C sort \
  >"$staging/RETURN_MANIFEST.tsv"
tar -C "$script_dir" -czf "$archive" "$(basename "$staging")"
archive_bytes=$(stat -c %s "$archive")
((archive_bytes < 95000000)) || step_fail "archive exceeds GitHub 95MB safety limit"
(cd "$script_dir" && sha256sum "$(basename "$archive")") >"$archive_sha"

trap - EXIT
echo "[STEP-4-OK] archive=$archive bytes=$archive_bytes"

#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
export GIT_SSH_COMMAND='ssh -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=yes'

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
analysis_root=$(cd "$script_dir/.." && pwd)
source_repo=$(cd "$analysis_root/.." && pwd)/chromium-efl
inputs="$script_dir/inputs"
logs="$script_dir/logs"
generated="$script_dir/generated"
archive="$script_dir/results_stage4.tar.gz"
archive_sha="$script_dir/results_stage4.tar.gz.sha256"
source_start_commit=$(<"$inputs/SOURCE_START_COMMIT")
gerrit_url=ssh://lhmax2025@review.tizen.org:29418/platform/framework/web/chromium-efl
gerrit_branch=sandbox/lhmax2025/toolchain
result_dir=stage4_retry2_v2_results
started=0
failure_reported=0

precheck_fail() {
  failure_reported=1
  echo "[PRECHECK-FAIL] publish_results.sh: $*" >&2
  exit 1
}
step_fail() {
  failure_reported=1
  echo "[STEP-5-FAIL] publish_results.sh: $*" >&2
  exit 1
}
trap 'rc=$?; if ((rc != 0 && failure_reported == 0)); then if ((started)); then echo "[STEP-5-FAIL] publish_results.sh: line=${LINENO} rc=${rc}" >&2; else echo "[PRECHECK-FAIL] publish_results.sh: line=${LINENO} rc=${rc}" >&2; fi; fi' EXIT

for tool in awk basename cp git mkdir sed sha256sum sleep ssh timeout; do
  command -v "$tool" >/dev/null 2>&1 || precheck_fail "missing tool: $tool"
done
[[ -d "$source_repo/.git" ]] || precheck_fail "missing source repository: $source_repo"
[[ -f "$archive" && -f "$archive_sha" ]] || precheck_fail "missing result archive or checksum"
(cd "$script_dir" && sha256sum -c "$(basename "$archive_sha")") \
  >"$logs/step5_archive_sha256.txt" 2>&1 || precheck_fail "result archive SHA256 failed"
[[ -z $(git -C "$source_repo" status --porcelain=v1 --untracked-files=all) ]] ||
  precheck_fail "source repository is dirty before result publication"
query_gerrit_head() {
  local attempt output head
  for attempt in 1 2 3; do
    if output=$(timeout 75 git ls-remote "$gerrit_url" "refs/heads/$gerrit_branch" \
        2>>"$logs/step5_gerrit_connectivity.txt"); then
      head=$(awk '{print $1}' <<<"$output")
      if [[ "$head" =~ ^[0-9a-f]{40}$ ]]; then
        printf '%s\n' "$head"
        return 0
      fi
    fi
    sleep 5
  done
  return 1
}

remote_head=$(query_gerrit_head) || precheck_fail "Gerrit HEAD query failed after 3 bounded attempts"
[[ "$remote_head" == "$source_start_commit" ]] ||
  precheck_fail "Gerrit toolchain HEAD=$remote_head expected=$source_start_commit"

if [[ -f "$generated/retry2_source_commit.txt" ]]; then
  source_commit=$(<"$generated/retry2_source_commit.txt")
  [[ $(git -C "$source_repo" rev-parse HEAD) == "$source_commit" ]] ||
    precheck_fail "source HEAD does not match the recorded Retry 2 fix commit"
  git -C "$source_repo" merge-base --is-ancestor "$source_start_commit" "$source_commit" ||
    precheck_fail "Retry 2 fix commit does not descend from fixed Gerrit HEAD"
else
  fetch_ok=0
  for attempt in 1 2 3; do
    if timeout 180 git -C "$source_repo" fetch --no-tags "$gerrit_url" \
        "refs/heads/$gerrit_branch" >>"$logs/step5_gerrit_fetch.txt" 2>&1; then
      fetch_ok=1
      break
    fi
    sleep 5
  done
  ((fetch_ok == 1)) || precheck_fail "Gerrit fetch failed after 3 bounded attempts"
  [[ $(git -C "$source_repo" rev-parse FETCH_HEAD) == "$source_start_commit" ]] ||
    precheck_fail "fetched Gerrit HEAD changed"
  git -C "$source_repo" checkout --detach "$source_start_commit" \
    >"$logs/step5_checkout.txt" 2>&1
  source_commit=$source_start_commit
fi

[[ ! -e "$source_repo/$result_dir" ]] || precheck_fail "$result_dir already exists"
started=1
mkdir "$source_repo/$result_dir"
cp "$archive" "$archive_sha" "$source_repo/$result_dir/"
for console in "$logs"/step*-*.console.log; do
  [[ -f "$console" ]] || continue
  cp "$console" "$source_repo/$result_dir/"
done
cp "$logs/step5_archive_sha256.txt" "$source_repo/$result_dir/"
if [[ "$source_commit" != "$source_start_commit" ]]; then
  git -C "$source_repo" diff "$source_start_commit..$source_commit" -- \
    third_party/electron_node/node.filter \
    tizen_src/build/abi/generate_libcxx_export_filters.sh \
    tizen_src/build/abi/node_nonstd_export_allowlist.tsv \
    >"$source_repo/$result_dir/source_fix.diff"
fi
{
  echo "source_start_commit=$source_start_commit"
  echo "source_fix_commit=$source_commit"
  echo "analysis_package_commit=$(git -C "$analysis_root" rev-parse HEAD)"
  echo "result_archive_sha256=$(awk '{print $1}' "$archive_sha")"
} >"$source_repo/$result_dir/result_identity.txt"

git -C "$source_repo" add -f -- "$result_dir"
git -C "$source_repo" -c user.name='Stage4 HP Executor' \
  -c user.email='stage4-executor@localhost' commit \
  -m 'results: stage4 chromium libc++ retry2 evidence' \
  >"$logs/step5_result_commit.txt" 2>&1 || step_fail "result commit failed"
result_commit=$(git -C "$source_repo" rev-parse HEAD)
remote_head_now=$(query_gerrit_head) || step_fail "Gerrit HEAD recheck failed"
[[ "$remote_head_now" == "$source_start_commit" ]] ||
  step_fail "Gerrit toolchain HEAD changed before push"
push_ok=0
for attempt in 1 2 3; do
  if timeout 180 git -C "$source_repo" push "$gerrit_url" \
      "HEAD:refs/heads/$gerrit_branch" >>"$logs/step5_gerrit_push.txt" 2>&1; then
    push_ok=1
    break
  fi
  observed_head=$(query_gerrit_head || true)
  if [[ "$observed_head" == "$result_commit" ]]; then
    push_ok=1
    break
  fi
  [[ "$observed_head" == "$source_start_commit" ]] ||
    step_fail "Gerrit HEAD changed during failed push"
  sleep 5
done
((push_ok == 1)) || step_fail "Gerrit push failed after 3 bounded attempts"
published_head=$(query_gerrit_head) || step_fail "published Gerrit HEAD query failed"
[[ "$published_head" == "$result_commit" ]] || step_fail "published Gerrit HEAD verification failed"

trap - EXIT
echo "[STEP-5-OK] branch=$gerrit_branch result_commit=$result_commit source_fix_commit=$source_commit"

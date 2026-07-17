#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 SOURCE_DIR GBS_CONF OUTPUT_DIR JOBS" >&2
  exit 2
fi

source_dir=$(readlink -f "$1")
gbs_conf=$(readlink -f "$2")
output_dir=$3
jobs=$4

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "JOBS must be a positive integer: $jobs" >&2
  exit 2
fi
if [[ ! -d "$source_dir/.git" ]]; then
  echo "not an independent git clone: $source_dir" >&2
  exit 2
fi
if [[ ! -f "$gbs_conf" ]]; then
  echo "missing GBS config: $gbs_conf" >&2
  exit 2
fi
if [[ -e "$output_dir" ]]; then
  echo "refusing to overwrite output directory: $output_dir" >&2
  exit 2
fi

mkdir -p "$output_dir"
cp "$gbs_conf" "$output_dir/gbs.conf.effective"
git -C "$source_dir" rev-parse HEAD > "$output_dir/source_head.txt"
git -C "$source_dir" status --short --branch > "$output_dir/source_status.txt"

{
  echo "started=$(date --iso-8601=seconds)"
  echo "source_dir=$source_dir"
  echo "gbs_conf=$gbs_conf"
  echo "jobs=$jobs"
  echo "command=gbs -c $gbs_conf build -A armv7l --include-all --overwrite --define '_costomized_smp_mflags -j$jobs' ."
  uname -a
  free -h
  df -h "$source_dir"
  gbs --version
} > "$output_dir/preflight.txt" 2>&1

set +e
(
  cd "$source_dir"
  /usr/bin/time -v -o "$output_dir/build.time" \
    gbs -c "$gbs_conf" build \
      -A armv7l \
      --include-all \
      --overwrite \
      --define "_costomized_smp_mflags -j$jobs" \
      .
) > "$output_dir/build.log" 2>&1
rc=$?
set -e

printf '%s\n' "$rc" > "$output_dir/exit_code.txt"
echo "finished=$(date --iso-8601=seconds)" >> "$output_dir/preflight.txt"
exit "$rc"

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 GBS_BUILDROOT OUTPUT_DIR TIMEOUT_SECONDS" >&2
  exit 2
fi

buildroot=$(readlink -f "$1")
output_dir=$2
timeout_seconds=$3

if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "timeout must be a positive integer" >&2
  exit 2
fi
if [[ -e "$output_dir" ]]; then
  echo "refusing to overwrite output directory: $output_dir" >&2
  exit 2
fi

mkdir -p "$output_dir"
deadline=$((SECONDS + timeout_seconds))
args_path=

while (( SECONDS < deadline )); do
  if [[ -d "$buildroot/home/abuild/rpmbuild/BUILD" ]]; then
    args_path=$(find "$buildroot/home/abuild/rpmbuild/BUILD" \
      -type f -path '*/out.chrome.*/args.gn' -print -quit 2>/dev/null || true)
  fi
  if [[ -n "$args_path" ]]; then
    break
  fi
  sleep 15
done

if [[ -z "$args_path" ]]; then
  echo "timed out waiting for args.gn" >&2
  exit 3
fi

cp "$args_path" "$output_dir/args.gn"
printf '%s\n' "$args_path" > "$output_dir/args_path.host.txt"

out_dir_host=$(dirname "$args_path")
source_host=$(dirname "$out_dir_host")
source_chroot=${source_host#"$buildroot"}
out_name=$(basename "$out_dir_host")

if [[ "$source_chroot" == "$source_host" ]]; then
  echo "failed to translate path into chroot: $source_host" >&2
  exit 4
fi

sudo chroot "$buildroot" /bin/bash -lc \
  "cd '$source_chroot' && ./buildtools/linux64/gn args '$out_name' --list --short" \
  > "$output_dir/gn_args_list_short.txt" 2>&1

rg '^(is_clang|use_custom_libcxx|use_custom_libcxx_for_host|use_lld|use_thin_lto|use_system_icu|enable_rust)[[:space:]]*=' \
  "$output_dir/gn_args_list_short.txt" \
  > "$output_dir/gn_key_args.txt" || true

cat "$output_dir/gn_key_args.txt"

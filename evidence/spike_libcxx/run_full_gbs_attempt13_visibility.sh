#!/usr/bin/env bash
set -euo pipefail

workcopy=/home/linhao/Toolchain/plan_evaluation/chromium-efl-spike-libcxx-wt
config=/home/linhao/Toolchain/plan_evaluation/gbs_llvm.conf
evidence=/home/linhao/Toolchain/plan_evaluation/spike_libcxx

cd "$workcopy"

# Reuse the initialized attempt12 buildroot, retain the complete packaging
# flow, and keep the same two-CPU Ninja limit used by the stable attempt8/12
# isolation profile.
exec /usr/bin/time -v \
  -o "$evidence/full_gbs_attempt13_visibility.time" \
  taskset -c 0,1 \
  gbs -c "$config" build \
    -A armv7l \
    --include-all \
    --overwrite \
    --incremental \
    --noinit \
    --define '_costomized_smp_mflags -j2' \
    . > "$evidence/full_gbs_attempt13_visibility.log" 2>&1

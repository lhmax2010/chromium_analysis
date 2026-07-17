#!/usr/bin/env bash
set -euo pipefail

workcopy=/home/linhao/Toolchain/plan_evaluation/chromium-efl-spike-libcxx-wt
config=/home/linhao/Toolchain/plan_evaluation/gbs_llvm.conf
evidence=/home/linhao/Toolchain/plan_evaluation/spike_libcxx

cd "$workcopy"

# Reuse attempt 11's initialized buildroot.  Keep the complete packaging flow,
# but avoid another dependency installation and force the spec's Ninja to -j2.
exec /usr/bin/time -v \
  -o "$evidence/full_gbs_attempt12_incremental.time" \
  taskset -c 0,1 \
  gbs -c "$config" build \
    -A armv7l \
    --include-all \
    --overwrite \
    --incremental \
    --noinit \
    --define '_costomized_smp_mflags -j2' \
    . > "$evidence/full_gbs_attempt12_incremental.log" 2>&1

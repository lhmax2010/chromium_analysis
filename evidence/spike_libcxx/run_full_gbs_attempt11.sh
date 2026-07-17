#!/usr/bin/env bash
set -euo pipefail

workcopy=/home/linhao/Toolchain/plan_evaluation/chromium-efl-spike-libcxx-wt
config=/home/linhao/Toolchain/plan_evaluation/gbs_llvm.conf
evidence=/home/linhao/Toolchain/plan_evaluation/spike_libcxx

cd "$workcopy"

# Keep GBS, rpmbuild, Ninja, and ThinLTO on the same two CPUs.  The spec
# intentionally honors this downstream macro before defining _smp_mflags.
exec /usr/bin/time -v \
  -o "$evidence/full_gbs_attempt11.time" \
  taskset -c 0,1 \
  gbs -c "$config" build \
    -A armv7l \
    --include-all \
    --overwrite \
    --clean-repos \
    --define '_costomized_smp_mflags -j2' \
    . > "$evidence/full_gbs_attempt11.log" 2>&1

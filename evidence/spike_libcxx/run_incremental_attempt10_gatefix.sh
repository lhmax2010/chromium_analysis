#!/usr/bin/env bash
set -euo pipefail

root=/home/linhao/GBS-ROOT-TIZEN-UNIFIED-LLVM/local/BUILD-ROOTS/scratch.armv7l.0
src=/home/abuild/rpmbuild/BUILD/chromium-efl-1.1.144
out=out.chrome.tz_v11.0.standard.armv7l
evidence=/home/linhao/Toolchain/plan_evaluation/spike_libcxx

exec /usr/bin/time -v \
  -o "$evidence/incremental_build_attempt10_gatefix.time" \
  taskset -c 0,1 \
  sudo -n chroot "$root" su - abuild -c "
    cd $src
    exec ninja -j2 -C $out libchromium-impl.so
  " > "$evidence/incremental_build_attempt10_gatefix.log" 2>&1

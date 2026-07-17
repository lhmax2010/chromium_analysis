#!/usr/bin/env bash
set -euo pipefail

root=/home/linhao/GBS-ROOT-TIZEN-UNIFIED-LLVM/local/BUILD-ROOTS/scratch.armv7l.0
src=/home/abuild/rpmbuild/BUILD/chromium-efl-1.1.144
out=out.chrome.tz_v11.0.standard.armv7l
evidence=/home/linhao/Toolchain/plan_evaluation/spike_libcxx

# Match attempt 8: two CPUs for Ninja and ThinLTO, hard memory cap, no swap.
exec /usr/bin/time -v \
  -o "$evidence/incremental_build_attempt9_isolated.time" \
  taskset -c 0,1 \
  sudo -n chroot "$root" su - abuild -c "
    export PATH=$src/third_party/node/tizen:\$PATH
    cd $src
    node --version
    exec ninja -j2 -C $out \
      wrt wrt-service wrt-service-launcher node-runtime ewk-interface \
      chrome_tizen efl_webprocess chromium-ewk efl_webview_app \
      mini_browser ubrowser
  " > "$evidence/incremental_build_attempt9_isolated.log" 2>&1

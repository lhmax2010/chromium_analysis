#!/usr/bin/env bash
set -euo pipefail

root=/home/linhao/GBS-ROOT-TIZEN-UNIFIED-LLVM/local/BUILD-ROOTS/scratch.armv7l.0
src=/home/abuild/rpmbuild/BUILD/chromium-efl-1.1.144
out=out.chrome.tz_v11.0.standard.armv7l
evidence=/home/linhao/Toolchain/plan_evaluation/spike_libcxx

exec /usr/bin/time -v \
  -o "$evidence/prepare_attempt9_isolated.time" \
  taskset -c 0,1 \
  sudo -n chroot "$root" su - abuild -c "
    set -eux
    export PATH=$src/third_party/node/tizen:\$PATH
    cd $src
    ./wrt/cxx_wrapper/build.sh '' \"\$PWD/$out\" 11 0 0
    tizen_src/buildtools/gn gen $out --root=$src --dotfile=$src/.gn
    tizen_src/buildtools/gn args $out --list --short
  " > "$evidence/prepare_attempt9_isolated.log" 2>&1

# tizen_src downstream 工具链补丁 / GN 覆盖清单（24 项）

- `tizen_src/build/config/tizen_features.gni:33-37` — 声明 `clang_ver="22"`，Tizen 非 x64 工具链指向仓内 `tizen_src/buildtools/llvm-22`，x64 特判到 `third_party/llvm-build`。
- `tizen_src/build/toolchain/tizen/BUILD.gn:9-32` — 定义 Tizen GCC/Clang GN toolchain 模板，并在 Clang 分支选择 `clang/clang++/llvm-ar`。
- `tizen_src/build/config/tizen/BUILD.gn:22-49` — 为各 Tizen CPU 注入 target triple、Clang resource-dir 与 linker target 参数。
- `tizen_src/build/config/tizen/BUILD.gn:151-153` — 在 Clang 配置下额外定义 `USE_CLANG`。
- `tizen_src/build/config/BUILD.gn:57-63` — 下游 Tizen 公共配置为 Clang 屏蔽 EFL 头的 `-Wextern-c-compat` 告警。
- `tizen_src/build/config/tizen_pkg_config.gni:7-32` — 包装 Tizen `pkg_config` 依赖，非 Tizen 或空依赖时生成空 config。
- `tizen_src/build/gn_chromiumefl.sh:84-86,227-238` — 解析 `is_clang`，Clang 分支设置 Tizen Clang host/snapshot toolchain、LLD 和 ThinLTO，GCC 分支设置对应 GCC toolchain。
- `tizen_src/build/gn_chromiumefl:145-157` — 下游 Python GN 启动器，从 `tizen_src/buildtools` 选择仓内 `gn` 可执行文件。
- `tizen_src/build/common.sh:383-390,437-446` — GBS 入口把 `--gcc/--clang` 映射为 RPM `_clang` 宏；local/release 默认强制 `_clang=1`。
- `tizen_src/build/cross_build_mobile.sh:36-48` — mobile 外部交叉构建导出 GCC/G++/binutils 前缀及 GBS sysroot。
- `tizen_src/build/cross_build_tv.sh:36-48` — TV 外部交叉构建导出 GCC/G++/binutils 前缀及 GBS sysroot。
- `tizen_src/build/cross-shim/arm-linux-gnueabihf-gcc:3-5` — 将硬浮点命名的 GCC shim 重定向到 Tizen `CROSS_COMPILE` GCC。
- `tizen_src/build/cross-shim/arm-linux-gnueabihf-g++:3-5` — 将硬浮点命名的 G++ shim 重定向到 Tizen `CROSS_COMPILE` G++。
- `tizen_src/build/ccache_env.sh:10-30` — 为 Tizen/desktop/crosscompile 构建配置 ccache 路径、缓存目录和 compiler-content 校验。
- `tizen_src/buildtools/gn` — 仓内 GN 可执行物，由 `tizen_src/build/gn_chromiumefl:151-157` 直接启动。
- `tizen_src/buildtools/llvm-22/` — 当前 Tizen 非 x64 选中的 Clang/LLD/llvm-ar/llvm-symbolizer 物料（选择证据：`tizen_features.gni:33,37`）。
- `tizen_src/buildtools/llvm-21/` — 与当前选择器并存但未被 `clang_ver="22"` 选中的旧 LLVM 工具链物料。
- `tizen_src/buildtools/llvm-20/` — 与当前选择器并存但未被 `clang_ver="22"` 选中的旧 LLVM 工具链物料。
- `tizen_src/buildtools/llvm/` — 无版本后缀的更早 LLVM bundle；当前 `llvm-$clang_ver` 路径不选择它。
- `tizen_src/build/prebuild/ld.gold.static` — 仓内静态 gold 二进制；全仓脚本/GN 无路径引用，当前 Clang 路径由 `use_lld=true` 绕开。
- `tizen_src/build/prebuild/tizen_2.4_tv/ld.gold` — 旧 Tizen 2.4 TV ARM gold 二进制；全仓脚本/GN 无路径引用。
- `tizen_src/build/jhbuild/patches/gst-ffmpeg-fixes-compilation-for-gcc-4.7-or-higher.patch` — 修复 gst-ffmpeg 在 GCC 4.7 下的汇编约束编译问题（补丁头 `Description`）。
- `tizen_src/build/jhbuild/patches/gst-plugins-good-fix-build-with-recent-kernels.patch` 与 `...-part-2.patch` — 修复 GStreamer v4l2 源码对较新内核头的构建兼容性（补丁 `Subject`）。
- `tizen_src/build/jhbuild/patches/gst-yylex-param-is-no-longer-supported-in-bison-3.patch` — 修复旧 grammar 在 Bison 3 下的生成失败（补丁 `Subject`）。

证据命令及原始命中另见 `spec_analysis.md`、`grep_hits.txt`、`checkpoint1_probes.txt`、`binutils_gold.txt`；本清单未超过 30 项。


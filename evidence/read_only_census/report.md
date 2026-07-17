# chromium-efl 构建现状证据报告：GCC 线 vs LLVM 线

范围：`chromium-efl/`，只读源码/历史与只读编译器 driver 探测；未执行构建，未修改源码。原始命令输出分别保存在本目录的 `conf_diff.txt`、`spec_analysis.md`、`grep_hits.txt`、`checkpoint1_probes.txt`、`version_rust.txt`、`libcxx_inventory.txt`、`binutils_gold.txt` 和 `ewk_api_scan.txt`。

## Q1：两条 conf 的实际 Chromium 编译器与标准库

**两线 Chromium 均为仓内 clang 22 + 系统 libstdc++;GCC/LLVM 两条 conf 的差异在平台底座 rootstrap 的 `%_toolchain` 默认值,不在 Chromium 自身。**

证据链：两份 conf 只切换 buildroot/repo（`checkpoint1_probes.txt:1-30`）；LLVM rootstrap 把 `%_toolchain` 默认设为 clang（`checkpoint1_probes.txt:43-59`），普通 rootstrap 的 RPM 宏求值为 GCC/G++（`checkpoint1_probes.txt:31-39`）。但 Chromium spec 在两份 conf 都未提供 `_clang` 时自行默认 `_clang=1`，最终发出 `is_clang=true`（`chromium-efl/packaging/chromium-efl.spec:344,352-356,714-718`）。Tizen GN 再选择仓内 Clang 22（`chromium-efl/tizen_src/build/config/tizen_features.gni:33-37`）。spec 发出 `is_tizen=true` 而不覆盖 `use_custom_libcxx`，故 `use_custom_libcxx=!is_tizen` 解析为 false（`chromium-efl/build/config/c++/c++.gni:10-18`）；两套 rootstrap/driver 探测均落到 `-lstdc++`（`checkpoint1_probes.txt:40-42,87-93`）。

## Q2：gbs_llvm.conf 线及 use_custom_libcxx 当前值

结论：**仓内 Clang 22 + 系统 libstdc++，`use_custom_libcxx=false`。** `gbs_llvm.conf` 的 Toolchain repo 让平台 RPM 默认使用 clang，但 Chromium spec 自身与 Q1 相同，仍由 `_clang=1` 和 Tizen GN 工具链选仓内 Clang；目标端 driver 从 GCC 14.2 sysroot 取 libstdc++ 头并链接 `-lstdc++`（`checkpoint1_probes.txt:43-65,66-93`）。`is_tizen=true` 与 `use_custom_libcxx=!is_tizen` 是 false 的直接源码证据（`spec_analysis.md:77-108`；`chromium-efl/build/config/c++/c++.gni:17`）。

## Q3：LLVM 线 Clang 来源与版本

结论：**版本为 `clang 22.0.0git`，revision `efe9a8c95451c9dadb5dd522802b05afd8b52d1b`。** Tizen 非 x64 toolchain 的来源是 `//tizen_src/buildtools/llvm-22`；x64 分支特判为 Chromium 的 `//third_party/llvm-build/Release+Asserts`（`chromium-efl/tizen_src/build/config/tizen_features.gni:33-37`）。实际二进制版本输出见 `checkpoint1_probes.txt:82-89`。

## Q4a：Chromium 主线版本

结论：**144.0.7559.132**（`chromium-efl/chrome/VERSION:1-4`；原始输出 `version_rust.txt`）。

## Q4b：enable_rust=false 是否仍为合法关闭路径

结论：**YES（M144 当前树的静态 GN 路径合法）。** `enable_rust` 仍是公开 GN arg（`chromium-efl/build/config/rust.gni:20-35`）；false 时 `toolchain_has_rust` 保持 false，Rust sysroot/target 初始化只在 true 分支执行（同文件 `:118-157,167-172`）；顶层 `all` 与 `all_rust` 均由 `if (enable_rust)` 保护（`chromium-efl/BUILD.gn:831-856`）；`rust_target` 模板在 false 时直接 `not_needed`，assert 位于 else 分支（`chromium-efl/build/rust/gni_impl/rust_target.gni:40-45`）。

没有发现无条件的“Rust is required”类全局 assert。现存 assert 是防止 **关闭 Rust 后仍错误依赖/包含 Rust 目标** 的局部保护（`chromium-efl/build/rust/std/BUILD.gn:218-226,312-316`），或受 `toolchain_has_rust` 条件保护（`chromium-efl/build/config/rust.gni:340-355,383`）。Tizen spec 默认 `__enable_rust=0` 并传 `enable_rust=false`（`chromium-efl/packaging/chromium-efl.spec:67-70,731`）；历史提交 `46061f7673c2224dc87777ae239247c30572027b` 明确说明修复 standard profile 的 Rust-disabled 构建（原始输出 `version_rust.txt`）。上游注释仍警告：禁用 Rust 的 Chromium 派生项目可能需要 C/C++ 替代实现（`rust.gni:25-27`），所以这里确认的是配置/依赖路径合法，不等同于本次实际全量构建验证。

## Q4c：bundled libc++ 物料与 GN 完整性

结论：**物料存在，`use_custom_libcxx=true` 所需的核心 target/dependency 链在位，`__Cr` namespace 机制在位。**

- `buildtools/third_party/libc++/` 存在 7 个文件（120 KiB），`libc++abi/` 存在 3 个文件（20 KiB）；它们是 GN glue/config。实际源码完整落在 `third_party/libc++/src/`（约 12,062 文件、95 MiB）和 `third_party/libc++abi/src/`（约 161 文件、6.7 MiB）。目录顶层清单见 `libcxx_inventory.txt`。
- true 时全局 compiler config 注入 `//build/config/c++:runtime_library`（`chromium-efl/build/config/compiler/BUILD.gn:1952-1954`），它加 bundled include、`-nostdinc++`/`-nostdlib++`（`chromium-efl/build/config/c++/BUILD.gn:81-92`）；所有 executable/shared-library 的 `common_deps` 依赖 `//buildtools/third_party/libc++`（`chromium-efl/build/config/BUILD.gn:280-293,303-324`）。libc++ target 有源码和 header deps，并在非 Windows 常规路径依赖 libc++abi（`chromium-efl/buildtools/third_party/libc++/BUILD.gn:479-520,616-620,675-679`）；libc++abi target、源码与 config 也存在（`chromium-efl/buildtools/third_party/libc++abi/BUILD.gn:9-19,28-48,76-87`）。
- ABI 隔离定义为 `_LIBCPP_ABI_NAMESPACE __Cr` 与 `_LIBCPP_ABI_VERSION 2`（`chromium-efl/buildtools/third_party/libc++/__config_site:9-21`）。
- downstream 改动已定位：commit `46061f7673c2224dc87777ae239247c30572027b`，题目 `[M138] Fix build errors for tizen standard profile`，把 target 与 host 的两个默认值从 `true` 改为 `!is_tizen`（`libcxx_inventory.txt` 的 git show 原始 diff）。`build/config/c++/BUILD.gn` 的记录历史只有 upstream upload commits，关键 libc++/libc++abi target 与 dependency 行的 blame 也落在 upstream upload/cherry-pick 提交；针对这些 target 文件搜索 `is_tizen` 变更无输出，当前依赖目标未见 downstream 删除（完整 blame 输出见 `libcxx_inventory.txt`）。注意 M144 文件仍保留一段“计划 M138 移除该选项”的过期 warning（`chromium-efl/build/config/c++/c++.gni:173-186`），但开关与目标目前确实仍存在。

## Q4d：binutils-gold 是否被 Clang/LLD 路径实际使用

结论：**Clang 路径不使用 gold；`BuildRequires: binutils-gold` 是当前 spec 的残留依赖。** spec 无条件（除 riscv64）要求它（`chromium-efl/packaging/chromium-efl.spec:145-147`），但 Clang 分支显式设置 `use_lld=true`（`chromium-efl/tizen_src/build/gn_chromiumefl.sh:227-232`），上游配置把它转成 `-fuse-ld=lld`（`chromium-efl/build/config/compiler/BUILD.gn:471-475`）。仓内 Clang 22 的只读 `-###` driver 探测实际选择 `tizen_src/buildtools/llvm-22/bin/ld.lld`，同时链接 `-lstdc++`（`binutils_gold.txt`）。

GCC 分支只选择 `gcc/g++` 且没有设置 `-fuse-ld=gold`（`chromium-efl/tizen_src/build/toolchain/tizen/BUILD.gn:22-32`；`gn_chromiumefl.sh:233-237`）；源树内两份预编译 gold 二进制没有脚本/GN 路径引用。因而未找到 gold 在当前 GCC 分支的主动选择证据，它不是“Clang 仍会间接用到”的依赖，最多是历史 GCC/Tizen 路径遗留。原始搜索和 driver 输出见 `binutils_gold.txt`。

## Q5：downstream 工具链补丁 / GN 覆盖

共列出 **24 项**，未超过 30 行上限，详见 `downstream_toolchain.md`。当前真正控制构建选择的核心点是：Clang 22 路径（`tizen_src/build/config/tizen_features.gni:33-37`）、Tizen GCC/Clang toolchain template（`tizen_src/build/toolchain/tizen/BUILD.gn:9-32`）、GN 参数分叉与 LLD（`tizen_src/build/gn_chromiumefl.sh:227-238`）、RPM `_clang` 入口（`tizen_src/build/common.sh:383-390`）。旧 LLVM 20/21/无版本 bundle、两份 gold 和 jhbuild 兼容补丁也单独标记为并存/legacy 物料。

## EWK 公开 API 纯度

结论：**FAIL / 非零泄漏。** RPM 把 `tizen_src/ewk/efl_integration/public/*.h` 全部安装到 `chromium-ewk` include 目录（`chromium-efl/packaging/chromium-efl.spec:1058-1059`）。82 个安装头中共有 **6 行命中、集中在 1 个头**：`ewk_cookie_parser.h:23` 包含 `<string>`，`:40-43` 暴露四个 `std::string` 成员，`:70` 的导出函数参数为 `const std::string&`。全部命中与命令见 `ewk_api_scan.txt`；因此 EWK 公开 API 不是 C ABI 纯净面，且该头会形成标准库 ABI 边界。

## UNRESOLVED

无请求项处于 UNRESOLVED。按“只读、不构建”的任务边界，Rust 与 bundled libc++ 的结论是源码、GN 图和 driver 的静态确认；未声称已完成全量 GBS 编译验证。

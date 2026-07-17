# 交接状态（2026-07-17）

## 不可误读的当前状态

- 本机不再执行任何 Chromium 编译或构建产物分析。
- attempt12 曾完整构建成功，但它位于 visibility 修复之前；G1 因 5 个 DSO 导出 `_ZNSt4__Cr22__libcpp_verbose_abortEPKcz` 而失败。
- attempt13 加入 `--exclude-libs=libc++.a/libc++abi.a` 后重新构建。本机最终停在 `12250/12257` 的 `libchromium-impl.so` ThinLTO 链接阶段，没有成功日志、没有新 RPM、没有 attempt13 门禁结论。
- 停止时没有 OOM：最后观测到的 attempt13 峰值约 8.31 GiB，资源限制为 2 CPU、12 GiB、零 swap。它是主动放弃本机构建，不是已证明的编译错误。
- postbuild 服务只写入了启动行，没有执行 RPM 解包或门禁。

原始证据：

- `evidence/spike_libcxx/full_gbs_attempt13_visibility.log`
- `evidence/spike_libcxx/full_gbs_attempt13_visibility.time`（空文件，说明 `/usr/bin/time` 未正常收尾）
- `evidence/spike_libcxx/attempt13_postbuild.log`
- `evidence/spike_libcxx/attempt13_node_runtime_ldflags.txt`

## 源码基线和补丁

- 上游/下游源仓库：`git://review.tizen.org/git/platform/framework/web/chromium-efl`
- 基线提交：`394713cfd95e9597793255ec71496aef6ef84574`
- 基线提交说明：`Avoid IsBuildTimely and Enable HSTS Preload for Tizen`
- 补丁：`patches/bundled_libcxx_spike.patch`
- 补丁 SHA-256：`388985d2f1feb6e2ed5852240557b675634e849546eca2fc6296aa97199b32f2`
- 补丁包含 6 个修改文件和 2 个新增文件，已在当前修改工作树上通过反向 `git apply --check`。

补丁的逻辑组成：

1. 独立宏 `__use_bundled_libcxx=1`，注入 `use_custom_libcxx=true` 和 host 同值。
2. bundled libc++ 路径强制 `use_system_icu=false`，并从 system deps 去掉 jsoncpp，解决 mksnapshot 的 system jsoncpp/ICU ABI 混用。
3. 恢复由平台 GCC/libstdc++ 单独构建的 `libwrt-c++wrapper.so` C ABI bridge；独立打包，不复用 `__enable_platform_api_wrapper` 语义。
4. bridge 使用 version script，只导出 C 白名单；GN 侧只链接共享 bridge。
5. EWK export filter 隐藏 libc++ `__libcpp_verbose_abort`。
6. Tizen 静态 libc++/libc++abi 链接增加 `--exclude-libs`，防止 archive 内 runtime 符号从其他 DSO 泄漏。

## 已知门禁基准

attempt12（visibility 修复前）的门禁结果：

| 项目 | 结果 |
|---|---:|
| `.so` payload | 20 |
| ELF payload | 18 |
| G1 导出 `std::__Cr/std::__1` | 5（FAIL） |
| G2 UND `std::__Cr/std::__1` | 0 |
| G3 NEEDED libc++/libc++abi | 0 |
| bridge 白名单实际/期望 | 92/92 |
| bridge 非白名单/缺失 | 0/0 |
| bridge `_ZNSt*` 导出 | 0 |
| bridge NEEDED libstdc++ | 1（预期） |

5 个 G1 命中均为 `_ZNSt4__Cr22__libcpp_verbose_abortEPKcz`，分别来自：

- `libnode-runtime.so`
- `libsplash_screen_plugin.so`
- `libwidget_plugin.so`
- `libwrt-service-override.so`
- `libv8.so`

attempt13 预期验证该符号被 `--exclude-libs` 消除，但尚未得到实际产物，不能写成 PASS。

## 修复配额和停止条件

- 小修复配额已经用完：`5/5`。
- GCC C ABI bridge 是用户批准的结构性修复，不占配额。
- 远端如再遇到编译/链接错误，只采证、分类、报告；不得自行作第 6 处修改。
- 涉及 libc++、libc++abi、llvm-libc、unwind、bridge 依赖结构、打包 ABI 边界的任何新变化，都必须先停下等待用户批准。

## EWK 阳性对照的实际情况

`ewk_parse_cookie` 虽然参数包含 `std::string`，但声明为裸 `extern "C"`，产物符号名是 `ewk_parse_cookie`。因此本版本不会出现原先预期的 `_ZNSt7__cxx11...` 到 `_ZNSt4__Cr...` mangling 对照。远端必须如实记录“阳性对照未形成”，不得伪造 mangled 名。

# Chromium EFL bundled libc++ Stage 2 只读收口报告

日期：2026-07-20

## 结论

本阶段没有重新编译，也没有修改 Chromium 源码、RPM 或既有构建产物。

- libc++abi 归属已经从 `UNRESOLVED` 收口为 `RESOLVED`：attempt8 延续构建树中的
  未剥离 `libchromium-impl.so` 对三个指定 libc++abi 实现符号均给出本地 text
  定义（小写 `t`）。
- 488 条 `std::__Cr` 导出和 libstdc++ 基线 V8/Node provider 导出已形成平台扫描
  交接文件。
- G4 的 131 条 OTHER 已完成前缀聚类；唯一 ICU 导出是 bundled ICU 路径下的预期
  V8 Intl 符号。
- 门禁脚本 v2 已将 G1/G2 改为 demangle 后全签名检查，并将未过白名单的新增导出
  设为硬失败。已用已知负面 attempt12 产物验证它确实报警。
- 仓内源码显示 WRT Node runtime 暴露标准 `.node` native-addon 加载链，且同时支持
  N-API 与 legacy/V8 C++ API，不是 N-API-only。第三方 WGT 是否被平台打包/签名
  政策允许携带 `.node` 仍需平台侧资料。

总体状态仍为 **AMBER**：构建可行性成立，libc++abi 已收口，但 Node/V8 C++ addon
边界和 454 个平台外消费者仍不能视为安全闭环。

## 1. libc++abi 归属

按任务顺序先执行 a，已经成功，因此停止，没有继续用 debuginfo，也没有提出或
执行重链接。

目标文件：

```text
chromium-efl-spike-libcxx-wt/out.chrome.tz_v11.0.standard.armv7l/libchromium-impl.so
```

`file` 显示该 ELF 带 `debug_info` 且 `not stripped`，大小 1,091,251,872 bytes，
Build ID 为 `58c066914d878ae5b1e9a89bf6db6060625461c7`。低优先级执行
`nm --defined-only` 得到：

```text
06a313fb t __cxa_begin_catch
06a3283d t __cxa_guard_acquire
06a314b3 t __cxa_throw
```

三个符号都是定义态 text，满足用户指定的 `T/t` 通过条件。结论：
`LIBCXXABI_OWNERSHIP=RESOLVED_IN_LIBCHROMIUM_IMPL`。

原始证据：
[libcxxabi_nm_evidence.txt](../evidence/stage2/libcxxabi_nm_evidence.txt)

## 2. 平台扫描交接清单

### `export_cr_488.txt`

- 488 行，无表头；每行 `mangled<TAB>demangled`。
- libv8.so 来源 464 条，libnode.so 来源 24 条。
- 字段异常 0，重复 0。
- 486 条正常 demangle；既有 2 条失败保留为 `[DEMANGLE_FAILED]`，没有丢弃。

附件：[export_cr_488.txt](export_cr_488.txt)

### `export_v8node_baseline.txt`

- 19,748 行，无表头；每行 `DSO<TAB>symbol`。
- libv8.so 18,909 条，libnode.so 839 条；字段异常 0，重复 0。
- 来源为基线 `baseline_exports.tsv`。按本项目既定 provider 定义，这一集合是
  `GLOBAL/WEAK 且非 UND`，即运行时可解析的动态导出，而不是丢弃 WEAK 的狭义
  GLOBAL-only 集合。这与平台 ABI 图的 provider 规则一致。

附件：[export_v8node_baseline.txt](export_v8node_baseline.txt)

行数原始校验：
[symbol_handoff_verification.txt](../evidence/stage2/symbol_handoff_verification.txt)

## 3. G4 OTHER 与 ICU

131 条 OTHER 的前缀聚类如下：

| 类别 | 数量 | 判断 |
|---|---:|---|
| `widget_config_*` | 92 | 新增 GCC/libstdc++ C ABI bridge 的白名单 C 导出 |
| V8 C++，签名不含 libc++ namespace | 37 | V8/V8 inspector 内部导出；不属于 `__Cr` 类，但仍受新增导出白名单约束 |
| Node C++，签名不含 libc++ namespace | 2 | Node tracing/builtin loader 导出；同样进入新增导出白名单审查 |

唯一 ICU 符号 demangle 为
`v8::internal::Intl::CompareStrings(..., icu_77::Collator const&, ...)`。
`packaging/chromium-efl.spec:125-133` 在 bundled libc++ 模式强制
`__use_system_icu=0`，并在 `:727-733` 向 GN 传入 `use_system_icu=false`；函数声明
本身位于 `v8/src/objects/intl-objects.h:189-195`。因此它是切换到树内/bundled ICU
后的预期 V8 Intl 导出，不是意外 system-ICU 泄漏。

原始证据：
[g4_other_clusters.txt](../evidence/stage2/g4_other_clusters.txt)、
[g4_other_131.tsv](../evidence/stage2/g4_other_131.tsv)、
[g4_icu_evidence.txt](../evidence/stage2/g4_icu_evidence.txt)

## 4. 门禁脚本 v2 与负面对照

附件：[abi_gate_v2.sh](abi_gate_v2.sh)

主要变化：

1. G1/G2 先批量调用 `c++filt`，再扫描完整 demangled 签名中的 `std::__Cr` 或
   `std::__1`；对 demangle 失败保留 raw-mangling fallback
   `NSt4__Cr|NSt3__1`，因此不会漏掉现有两个 unknown。
2. 保留 G3：任何 DSO NEEDED `libc++.so*` 或 `libc++abi.so*` 均失败。
3. 当前导出集与基线快照求差；任何 added export 不在精确
   `DSO<TAB>symbol` allowlist 中均硬失败。
4. bridge 必须恰好出现一次、C 导出与 92 项白名单一致、无 `_ZNSt*` 导出，且
   NEEDED `libstdc++.so`。
5. 脚本串行扫描，跳过 debuginfo ELF；输入只读。`bash -n` 通过；本机没有
   `shellcheck`，因此该项记为 `UNAVAILABLE`。

负面对照使用本机保存的 attempt12 RPM 解包树，未重新编译。该产物早于 attempt13
visibility 修正，故它有 5 个直接 namespace-prefix 命中；测试目的只是证明 v2 能
报警：

| 指标 | 结果 |
|---|---:|
| v2 G1 全签名命中 | 493 |
| v1 等价 prefix G1 命中 | 5 |
| 仅 v2 发现的嵌套签名 G1 | 488 |
| v2 G2 全签名命中 | 43 |
| v1 等价 prefix G2 命中 | 0 |
| 仅 v2 发现的嵌套签名 G2 | 43 |
| 未过 added allowlist | 730 |
| 脚本退出码 | 1（预期 FAIL） |

原始输出：
[gate_v2_negative_run.log](../evidence/stage2/gate_v2_negative_run.log)；完整 hits 位于
`evidence/stage2/gate_v2_negative/`。

`%check` 草稿：[chromium_efl_check_v2.patch](chromium_efl_check_v2.patch)。
该 patch 只是一份未应用草稿，`git apply --check` 已通过；正式使用前仍需把门禁
脚本、基线 export snapshot、added allowlist 和 bridge allowlist 四项作为受评审
packaging 输入落位。当前候选本来就有 488/43 命中，所以在 ABI 政策收口或导出
隐藏完成前，v2 对它给出硬失败是预期行为。

## 5. Node native addon 支持面

### 仓内可确认事实

- WRT launcher 加载 `libnode-runtime.so` 并调用 `NodeStart`：
  `wrt/src/app/service_launcher_main.cc:31-32,142-160`。
- WRT runtime 用标准 CommonJS `require(startServiceFile)` 启动服务：
  `wrt/src/service/node/node-runtime.js:314-330,351-372`。
- Node 标准 CJS loader 将 `.node` 直接交给 `process.dlopen`：
  `third_party/electron_node/lib/internal/modules/cjs/loader.js:1927-1929`。
- native loader 先接受 legacy/context-aware Node module，再接受 N-API initializer：
  `third_party/electron_node/src/node_binding.cc:435-447,496-517,529-536`。
- WRT 创建 `CommonEnvironmentSetup` 时没有传 `kNoNativeAddons`；
  `CreateEnvironment` 默认是 `kDefaultFlags`，`allow_native_addons` 默认 true：
  `third_party/electron_node/src/node.cc:1633-1666`、
  `third_party/electron_node/src/node.h:730-736,1009-1021`、
  `third_party/electron_node/src/node_options.h:157-162`。对 `wrt/`、`tizen_src/`、
  `packaging/` 的禁用项检索为 0 命中。
- WRT 自身的 `wrtnode` 模块就使用 `NODE_MODULE` 和 `v8::Local`：
  `wrt/src/service/node/wrt_node_extension_api.cc:386-398`。
- spec 安装 `libnode.so`、Node 头和完整 V8 公共头；Node 头在非 TV、非 wearable、
  非 DA profile 下通过 `_support_node_module` 提供：
  `packaging/chromium-efl.spec:395-398,971-974,1071-1072,1214-1216,1567-1575`。
- `node_module_register` 在导出 filter 中显式保留：
  `tizen_src/ewk/chromium-ewk.filter:41-45`。

### 判定

`WRT_NATIVE_ADDON_LOADER=YES`，`API_SURFACE=N_API_AND_V8_CPP`。仓内实现不是
N-API-only；直接 V8/Node C++ addon 是技术上可加载和可构建的支持面。

唯一无法仅靠本仓确认的是平台发行政策：第三方应用的 WGT 签名、架构和安装规则
是否允许携带任意 `.node` ELF。标记为
`UNRESOLVED-需平台侧应用打包/安全策略资料`。在平台证明“不允许第三方 native
addon”或强制“N-API-only”之前，libv8/libnode 的 `std::__Cr` 导出必须按潜在外部
C++ ABI 边界处理，不能因 Chromium RPM 内部无消费者而豁免。

完整源码摘录：
[node_addon_source_evidence.txt](../evidence/stage2/node_addon_source_evidence.txt)

## 四个正式附件

1. [export_cr_488.txt](export_cr_488.txt)
2. [export_v8node_baseline.txt](export_v8node_baseline.txt)
3. [abi_gate_v2.sh](abi_gate_v2.sh)
4. [chromium_efl_check_v2.patch](chromium_efl_check_v2.patch)

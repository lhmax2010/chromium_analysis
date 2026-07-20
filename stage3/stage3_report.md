# Chromium EFL bundled libc++ Stage 3 只读 ABI 收口报告

日期：2026-07-20

## 结论

本阶段没有执行 GN、Ninja、GBS 或任何编译/链接命令，也没有修改 Chromium
源码、RPM 或既有构建产物。集合输入固定在 Gerrit 证据提交
`17d59f3a15e1fbe7e48c119b4f128bf2f228c88d`。

- libv8.so/libnode.so 基线相对候选共有 **584** 条 removed export；其中
  **543** 条成功 demangle 后签名含 `std::`。这 543 条就是已有外部二进制一旦
  UND 引用便会在候选上断链的确定集合。
- 其中 **484/543（89.13%）** 能与 488 条候选 `__Cr` 导出做完整签名的精确
  归一化配对，证明 removed 主体是 libstdc++ → bundled libc++ mangling 迁移，
  不是功能删除。其余 59 条不能据此判成删除或迁移；另有 2 条 demangle 失败，
  已原样保留但未混入 `std::` 子集。
- 当前树的 `NODE_MODULE_VERSION` 是 **137**。legacy/V8 C++ addon 并非只要
  Node 产品版本不同就必然拒载；真正闸门是 addon 的 `nm_version` 是否等于运行时
  module ABI version。值不匹配且找不到当前版本 initializer 时会明确拒载。N-API
  走独立入口并绕过此闸门，但仍受自己的 Node-API version 范围校验。
- 488 条 `__Cr` 导出中有 **34 个唯一符号**被包内其他 DSO 消费，形成 41 条边；
  consumer/provider 全部位于同一个 `chromium-efl-1.1.144-1.armv7l` RPM 根。
  这允许原子升级整个集合，但不改变 ELF 跨 DSO 解析规则：version script 可直接
  收掉 454 条无包内消费者的导出，**不能单靠隐藏规则收掉全部 488 条**，否则 34 个
  provider 符号对应的 UND 会失配。
- 导出收口建议采用“GN 接线、链接期 version script 执行”。现有
  `v8_expose_symbols`/`v8_expose_public_symbols` 是粗粒度编译期开关，并且当前 Tizen
  shared-V8 路径会启用 private+public export，不能表达 34 条内部 allowlist；Node
  已经有 `node.filter` 先例，V8 应补同类 filter。

总体状态仍为 **AMBER**：removed-set 与 addon 版本闸门已证实；要达到零 `__Cr`
动态导出，还必须先消除 41 条包内跨 DSO C++ ABI 边，并明确 legacy native-addon
兼容政策。

## 1. removed-set

### 1.1 算法与输入

从同一证据提交读取 `abi_analysis/baseline_exports.tsv` 与
`abi_analysis/candidate_exports.tsv`，仅保留路径以 `/libv8.so` 或
`/libnode.so` 结尾的记录，按完整 `DSO<TAB>symbol` 去重排序后执行：

```text
removed = baseline - candidate   (comm -23)
```

随后对 584 条 mangled name 批量运行 GNU `c++filt` 2.42，并按完整 demangled
签名是否含字面量 `std::` 形成正式附件。完整命令记录见
[commands.txt](../evidence/stage3/commands.txt)，原始集合见
[removed_all.tsv](../evidence/stage3/removed_all.tsv) 与
[removed_all_demangled.tsv](../evidence/stage3/removed_all_demangled.tsv)。

### 1.2 数量

| 指标 | 数量 |
|---|---:|
| baseline libv8.so + libnode.so 导出 | 19,748 |
| candidate libv8.so + libnode.so 导出 | 19,692 |
| removed | **584** |
| removed / libv8.so | 558 |
| removed / libnode.so | 26 |
| removed 且 demangled 签名含 `std::` | **543** |
| demangle 失败、未参与 `std::` 判定 | 2 |
| candidate 相对 baseline added（补充校验） | 528 |

候选净少 56 条等于 `528 - 584`，与两份快照总数差一致。原始计数见
[removed_counts.txt](../evidence/stage3/removed_counts.txt)。另将这 584 条与候选 RPM
全体 DSO 的 export union 交叉，命中为 0；没有“从 libv8/libnode 移到另一候选
DSO”的假 removed，空结果见
[removed_resolved_elsewhere.tsv](../evidence/stage3/removed_resolved_elsewhere.tsv)。

正式附件 [removed_std_carrying.tsv](removed_std_carrying.tsv) 为 543 行、无表头，
每行 `mangled<TAB>demangled`。两条 `c++filt` 原样返回 mangled name 的失败记录位于
[removed_demangle_unknown.tsv](../evidence/stage3/removed_demangle_unknown.tsv)，没有
静默丢弃，也没有在无法证明时归入 `std::` 子集。

### 1.3 前缀聚类

分类对象是 demangled callable/variable 的主命名空间；函数参数中的命名空间不参与
分类。`OTHER` 包括 `cppgc::`、`v8_inspector::`、`std::`、`unibrow::` 等。

| 类别 | removed 全集 | 其中 std-carrying |
|---|---:|---:|
| `v8::internal::` | 441 | **409** |
| 其余 `v8::` 公共 API | 44 | **43** |
| `node::` | 24 | **22** |
| 其他 | 75 | **69** |
| 合计 | 584 | **543** |

聚类原始输出：
[removed_all_clusters.txt](../evidence/stage3/removed_all_clusters.txt)、
[removed_std_clusters.txt](../evidence/stage3/removed_std_clusters.txt)。

### 1.4 与 `__Cr` 集合的语义配对

配对只做一种可审计的归一化：把完整 demangled 签名中的
`std::__cxx11::`、`std::__Cr::`、`std::__1::` 都替换为 `std::`，然后要求整条签名
完全相等。结果为 542 个 join row；构造/析构 C1/C2 可 demangle 成同一文本，按
mangled name 去重后是 **484 个旧符号 ↔ 484 个新符号**。

抽样的 10 个同函数配对如下；每项的 baseline/candidate mangled name 与两侧完整
demangle 均在
[semantic_pairs_sample10.tsv](../evidence/stage3/semantic_pairs_sample10.tsv)：

1. `cppgc::internal::EnsureGCInfoIndexTrait::EnsureGCInfoIndex`
2. `node::CreateEnvironment`
3. `node::InitializeOncePerProcess`
4. `node::LoadEnvironment`
5. `node::NodeRuntimeEnvironment::SetDelegate`
6. `v8::CppHeap::CollectCustomSpaceStatisticsAtLastGC`
7. `v8::JSON::Parse`
8. `v8::RegisterExtension`
9. `v8::internal::ShortPrint`
10. `v8_inspector::V8DebuggerId::V8DebuggerId`

完整配对集合见
[semantic_pairs_all.tsv](../evidence/stage3/semantic_pairs_all.tsv)，计数见
[semantic_pair_counts.txt](../evidence/stage3/semantic_pair_counts.txt)。该证据支持
“主体是 mangling 迁移”；它不支持把未精确配对的 59 条直接判为功能删除。

## 2. NODE_MODULE_VERSION 闸门

### 2.1 legacy/V8 C++ addon

本树默认值来自 `third_party/electron_node/src/node_version.h:95-99`：
`NODE_MODULE_VERSION=137`。实际 GN 路径在 `node.gni:23-24` 从该头读取值，
`unofficial.gni:64-73` 再定义 `NODE_EMBEDDER_MODULE_VERSION`；本次 resolved args 的
`node_module_version` 也确认为 137。因此这里不是只引用头文件默认值。同一头文件
`:79-84` 明确说明这个数在 C++、V8 或其他依赖发生 ABI 不兼容变化时才应变化，
而且一个 Node major release line 内不会改变它。因此“Node 产品版本不同”不等于
“module ABI version 必然不同”。

legacy loader 读取已注册 module 的 `nm_version`，并在
`third_party/electron_node/src/node_binding.cc:529-554` 执行拒载：

```cpp
// -1 is used for N-API modules
if ((mp->nm_version != -1) && (mp->nm_version != NODE_MODULE_VERSION)) {
  if (auto callback = GetInitializerCallback(dlib)) {
    callback(exports, module, context);
    return true;
  }
  // ... close DSO and THROW_ERR_DLOPEN_FAILED(...)
  return false;
}
```

`GetInitializerCallback()` 在 `node_binding.cc:417-420` 查找当前运行时版本命名的
`node_register_module_v137`。所以准确答案是：

- addon 的 module version 与 137 相同：不会因这一闸门拒载；
- module version 不同：仅当 DSO 仍提供当前版本 initializer 时可走兼容回退，否则
  `:539-554` 关闭 DSO 并报 “compiled against a different Node.js version”；
- 因而 legacy addon **不是跨任意 Node 产品版本必然拒载**，但跨不同
  `NODE_MODULE_VERSION` 且无当前 initializer 时必然拒载。

这对正式迁移有直接影响：若平台保留 legacy addon 支持，bundled libc++ 改变 C++
ABI 后必须分配新的 `NODE_MODULE_VERSION` 或 `NODE_EMBEDDER_MODULE_VERSION`，否则
历史上同为 137、但用 libstdc++ 构建的 addon 可能通过版本闸门后才在符号解析阶段
失败。

### 2.2 N-API addon

N-API 是独立路径。`node_binding.cc:507-517` 先分别查当前 legacy initializer 和
`NAPI_MODULE_INITIALIZER_BASE`，命中 N-API 后调用
`napi_module_register_by_symbol()` 并立即返回。旧式 N-API 自注册也在
`third_party/electron_node/src/node_api.cc:753-773` 被转换成 `nm_version=-1`，正好
绕过上面的 legacy 比较。

因此答案为 **YES：N-API 不走 NODE_MODULE_VERSION=137 闸门**。但这不等于没有
版本检查；它使用独立 `module_api_version`，支持范围由
`node_version.h:101-108` 定义为 1..10（默认 8），不支持版本在
`node_api.cc:674-700` 走 `ThrowNodeApiVersionError`。

完整带行号源码摘录：
[node_module_version_gate.txt](../evidence/stage3/node_module_version_gate.txt)。

## 3. 34 个包内被消费的 `__Cr` 符号

expanded edge 原始表共有 41 行、34 个唯一 `match_symbol`。分布如下：

| consumer → provider | 边数 |
|---|---:|
| libchromium-impl.so → libv8.so | 25 |
| libchromium-impl.so → libnode.so | 7 |
| libnode.so → libv8.so | 9 |
| 合计 | **41** |

- 按 consumer 去重：libchromium-impl.so 消费 32 个，libnode.so 消费 9 个；其中
  7 个 V8 符号同时被两者消费。
- 按 provider 去重：libv8.so 提供 27 个，libnode.so 提供 7 个，合计 34。
- 所有 consumer/provider 路径的 RPM 根都恰为
  `chromium-efl-1.1.144-1.armv7l`，所以答案是 **YES，全部在同一 RPM 集内**。

34 个唯一符号清单见
[internal_cr_34.tsv](../evidence/stage3/internal_cr_34.tsv)，分布与同包证明见
[internal_cr_distribution.txt](../evidence/stage3/internal_cr_distribution.txt)。

但“同一 RPM”只解决发布原子性，不让 hidden/local ELF symbol 跨 DSO 可解析。
因此 version script 方案的可行边界是：

- 可把 454 个当前没有包内 consumer 的 `__Cr` 导出先列入隐藏候选；是否存在平台外
  consumer 仍需平台级扫描确认；
- 34 个内部 provider 符号在现有拓扑下必须保持动态可解析；直接把它们 localize 会
  令相应 consumer 的 UND 在加载时失败；
- 要隐藏 488 全量，必须先把 41 条边改为 DSO 内部调用、C bridge，或合并/静态收口
  provider 与 consumer。**仅加 version script 不可完成 488 全隐藏。**

## 4. version script 方案草稿（未实施）

### 4.1 机制选择

建议选择 **链接期 `--version-script`，由 GN target 显式接线**，不选择
`v8_expose_symbols`：

- `v8/gni/v8.gni:75-80` 说明 `v8_expose_symbols` 已弃用，替代项
  `v8_expose_public_symbols` 也只是“为 Node/Electron native modules 暴露公共符号”
  的布尔/字符串开关；当前 resolved args 仍为 `""`/`false`。
- Tizen 的 V8 shared target 位于 `v8/BUILD.gn:8053-8071`。只要
  `v8_enable_shared_library=true`，`:889-896` 就定义 `BUILDING_V8_SHARED_PRIVATE`；
  `v8/include/v8config.h:822-855` 又令 private build 同时启用 public export。
  因而这个开关无法表达“隐藏 454、暂留 34”的精确集合。
- libnode 已在 `third_party/electron_node/unofficial.gni:249-254` 注入
  `--version-script=node.filter`；`node.filter:2-45` 使用 C++ wildcard allowlist 并
  `local: *`。Tizen EWK 也在 `tizen_src/ewk/efl_integration/BUILD.gn:198-207`
  使用相同接线模式，机制已有仓内先例。

带行号证据：[version_export_controls.txt](../evidence/stage3/version_export_controls.txt)。

### 4.2 建议改动点

以下只是供正式变更评审的草稿，本阶段未应用：

1. **V8 map**：新增受评审的 Tizen 专用 map（例如 `v8/v8_tizen.filter`），在
   `v8/BUILD.gn:8060-8071` 的 shared-library 分支增加 `inputs` 和
   `-Wl,--version-script=...`。第一阶段仅 localize 454 个无包内消费者的 `__Cr`
   符号，并精确保留 `internal_cr_34.tsv` 中由 libv8.so 提供的 27 项。
2. **Node map**：复用并收窄 `third_party/electron_node/node.filter`，把目前
   `node::*` 的宽 wildcard 改为经过 addon 政策批准的 C/C++ surface；现阶段精确
   保留由 libnode.so 提供的 7 个包内 `__Cr` 符号。给
   `unofficial.gni:249-254` 补 `inputs = [ version_script ]`，确保 map 变化触发重链。
3. **allowlist 来源**：34 项按 provider 拆成两份 exact mangled allowlist，禁止用
   `*__Cr*` 形式的 global 通配；每次构建由门禁重新计算 cross-DSO UND→DEF，并要求
   “实际保留集合 = 审批集合”。
4. **legacy addon 决策**：若继续支持 V8 C++ addon，map 必须保留获准的 Node/V8
   addon surface，并为 libc++ ABI 分配新的 module ABI version；若平台正式宣布
   N-API-only，则先用平台打包/加载策略阻断 legacy addon，再收掉相应 C++ 导出。
5. **全量零导出阶段**：逐一消除 41 条内部边后删掉 34 项临时 allowlist，再用 Stage
   2 gate v2 验证 G1/G2 为零。formal build/负载验证应在高性能服务器执行，不在
   本机进行。

map 设计还必须保留 libnode 的 C 入口（如 `node_module_register`、所需 `uv_*`）和
V8/Node 非 `__Cr` 公共 ABI；不能用一个不分类型的 `local: *` 草率替换现有出口。

## 5. 交付物与证据卫生

正式交付物：

1. [stage3_report.md](stage3_report.md)
2. [removed_std_carrying.tsv](removed_std_carrying.tsv) — 543 行

所有原始集合、命令、源码摘录和中间校验均位于 `evidence/stage3/`。相关 Node/V8
源码文件相对工作树 HEAD 的 `git diff --exit-code` 为 0；工作树原有其他 spike
改动未被本阶段触碰。附件哈希与行数见
[attachment_verification.txt](../evidence/stage3/attachment_verification.txt)。

# chromium-efl bundled libc++ 远端执行报告

## 运行身份

- RUN_ID:
- 主机:
- analysis commit:
- Chromium base commit: `394713cfd95e9597793255ec71496aef6ef84574`
- patch SHA-256: `388985d2f1feb6e2ed5852240557b675634e849546eca2fc6296aa97199b32f2`

## 可行性结论

`SUCCESS / FAILED / UNRESOLVED`：

## 构建量化

| 指标 | system-libstdc++ 基线 | bundled libc++ 候选 | 差值 |
|---|---:|---:|---:|
| exit code | | | |
| wall time | | | |
| MemoryPeak | | | |
| RPM 总大小（bytes） | | | |
| libchromium-impl.so（bytes） | | | |

## 实际 GN 参数

| 参数 | 基线 | 候选 |
|---|---|---|
| is_clang | | |
| use_custom_libcxx | | |
| use_custom_libcxx_for_host | | |
| use_lld | | |
| use_thin_lto | | |
| use_system_icu | | |
| enable_rust | | |

## 错误分类

| 类别 | 计数 | 代表样例 | 证据文件 |
|---|---:|---|---|
| A libc++ 编译 | | | |
| B downstream/system libstdc++ ABI | | | |
| C llvm-libc/libc++abi/unwind 链接 | | | |
| D 第三方头冲突 | | | |
| E 其他/环境 | | | |

## 补丁清单与配额

- 小修复配额：`5/5`。
- GCC C ABI bridge：用户批准的结构性修复，不占配额。
- 本次是否产生额外修改：必须为 NO；若不是，停止并解释。

## ABI 门禁

| 门禁 | 命中数 | PASS/FAIL | 证据 |
|---|---:|---|---|
| G1 GLOBAL/WEAK 导出 std namespace | | | |
| G2 UND std namespace | | | |
| G3 NEEDED libc++/libc++abi | | | |
| bridge 非白名单导出 | | | |
| bridge 白名单缺失 | | | |
| bridge `_ZNSt*` 导出 | | | |
| bridge NEEDED libstdc++ | | | |

## G4 全局导出集

- added count:
- removed count:
- full diff:
- 结论:

## ewk_parse_cookie

- 候选实际符号:
- 基线实际符号:
- 是否形成原计划 mangling 阳性对照: NO（预期为裸 `extern "C"`；若实际不同，附证据）

## `__cxa_*` / `Unwind*`

- libc++abi 解析:
- unwind 解析:
- NEEDED 证据:
- dynsym/symtab 证据:

## bridge C 纯度

- header hits:
- export whitelist actual/expected:
- NEEDED libstdc++:

## 遗留事项 / UNRESOLVED

- 无则写 `NONE`。

## 证据索引

| 结论 | 原始证据文件 |
|---|---|
| | |

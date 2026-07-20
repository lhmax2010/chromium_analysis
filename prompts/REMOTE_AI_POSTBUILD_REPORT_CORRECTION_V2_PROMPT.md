# 高性能服务器任务：修正 post-build 审计报告统计（禁止重新编译）

## 目标

修正 Tizen Gerrit `sandbox/lhmax2025/toolchain` 分支 commit
`2f995770ab57c67002c96cbb2a38d75b9013a2da` 中两组已经由独立复核定位的
统计错误。不得重新运行 Chromium/GBS 构建，不得改 Chromium 源码，不得替换
baseline/candidate RPM。

最终状态仍应是 `BUILD_SUCCESS_ABI_UNRESOLVED`。这次工作只修证据表和报告数字，
不能把未解决项改写成已解决。

## 0. 强制 preflight

在 chromium-efl 仓库执行并保存输出：

```bash
git status --short --branch
git rev-parse HEAD
git branch --show-current
```

必须同时满足：

- 当前分支是 `sandbox/lhmax2025/toolchain`，或明确跟踪该 Gerrit 分支；
- `HEAD` 是 `2f995770ab57c67002c96cbb2a38d75b9013a2da`；
- 工作树无未提交修改。

任一项不满足，立即停止并向用户报告实际值；不要继续，不要自行切换、reset、
rebase 或覆盖文件。

## 1. 工作目录和只读输入

```bash
RUN=chromium-libcxx-20260717_143911/analysis/runs/20260717_143911
OLD="$RUN/postbuild_correction"
NEW="$RUN/postbuild_correction_v2"
mkdir -p "$NEW"
```

只读输入：

- `$RUN/abi_analysis/g4_added.tsv`
- `$OLD/g4_classification_corrected.tsv`
- `$OLD/baseline_rpm_inventory.tsv`
- `$OLD/candidate_rpm_inventory.tsv`
- `$OLD/rpm_size_comparison.tsv`
- `$OLD/gate_summary.corrected.txt`
- `$RUN/report.corrected.md`

不要重新解包或修改 RPM。

## 2. 修正 G4 分类

现有错误不是“TSV 行尾差异”或“符号匹配边界差异”。原始
`g4_added.tsv` 有 620 条记录；现有分类文件总共 620 行，但其中 1 行是表头，
所以只有 619 条数据。它漏掉了原始文件第一条：

```text
_ZN4node12wasm_web_api19WasmStreamingObject6CreateEPNS_11EnvironmentENSt4__Cr10shared_ptrIN2v813WasmStreamingEEE
```

重新从全部 620 条原始记录生成分类，不得用现有分类文件作为输入。原始 TSV 第
2 列是符号名。分类优先级固定为：

1. 包含 `NSt4__Cr` 或 `NSt3__1`：`LIBCXX_CR`
2. 否则包含 `NSt7__cxx11` 或 `B5cxx11`：`LIBSTDCXX_CXX11`
3. 否则包含 ICU mangling（本数据中的 `N6icu_`）：`ICU`
4. 其余：`OTHER`

输出 `$NEW/g4_classification_v2.tsv`，格式为表头
`symbol<TAB>classification` 加 620 条数据。

必须用独立命令验证并保存到 `$NEW/g4_verification.txt`：

- 原始行数：620
- 分类数据行数：620（不含表头）
- `LIBCXX_CR=488`
- `LIBSTDCXX_CXX11=0`
- `ICU=1`
- `OTHER=131`
- 四类之和：620
- 原始符号集合与分类符号集合双向 `comm` 均为空
- 无重复或丢失记录

## 3. 修正 RPM 总量

从 inventory 的逐包 bytes 重新求和，不要手抄：

- baseline：`516543236` bytes
- candidate：`534832144` bytes
- delta：`18288908` bytes
- delta：约 `+3.54%`

现有报告的 baseline 少写了 100,000 bytes，因此 delta 和百分比也错了。

重新生成 `$NEW/rpm_size_comparison_v2.tsv`。不得保留现有文件中的伪数据行：

```text
rpmbytessha256            0
```

保存求和与百分比复算命令输出到 `$NEW/rpm_size_verification.txt`。逐包数据必须与
两个 inventory 一致，baseline/candidate 都应是 8 个 RPM。

## 4. 生成 v2 汇总和报告

生成：

- `$NEW/gate_summary.v2.txt`
- `$RUN/report.corrected.v2.md`

报告必须使用下列口径：

- 最终状态：`BUILD_SUCCESS_ABI_UNRESOLVED`
- Expanded ABI：488 exports、43 UND、41 internal edges、454 unmatched exports
- Bridge：actual=92、whitelist=92、unexpected=0、missing=0；禁止 `_ZNSt*`
  导出；NEEDED `libstdc++.so.6` 为预期
- G4 added：620 total、488 LIBCXX_CR、0 LIBSTDCXX_CXX11、1 ICU、131 OTHER
- RPM：baseline 516,543,236，candidate 534,832,144，delta 18,288,908
  （约 +3.54%）
- GNU time Maximum RSS：baseline 16,581,724 KB，candidate 17,480,900 KB
- `41552306` 保持 `UNRESOLVED/UNANCHORED`
- libc++abi 静态链入保持 `UNRESOLVED`
- unwind 由 `libgcc_s.so.1` 解析（直接证据）
- 454 个 unmatched exports 的平台外部消费者范围保持 `UNRESOLVED`
- 2 个无法 demangle 的符号保持 `UNRESOLVED`
- `ewk_parse_cookie` 在 baseline/candidate 都是裸 `extern "C"` 符号；它没有形成
  原计划所说的 mangling 阳性对照

删除“619/487 差 1 可能是行尾或匹配边界”的表述，因为漏行原因已经确定。

## 5. 自检、提交与回报

提交前执行：

```bash
git diff --check
git status --short
git diff --stat
```

只允许新增 `$NEW/` 下的修正证据和 `$RUN/report.corrected.v2.md`。不要改旧证据，
以便保留审计链。

提交说明建议：

```text
Fix post-build audit G4 and RPM totals
```

推送到 `sandbox/lhmax2025/toolchain` 后，只向用户回报：

- 新 commit 完整 SHA；
- G4 五个数字；
- RPM 三个总量数字；
- 最终状态；
- `git diff --check` 结果；
- 明确写出“未重新编译、未修改 RPM、未修改 Chromium 源码”。

# 高性能服务器任务：V3 证据卫生修正（禁止编译）

## 结论先行

Gerrit commit `a9ba89cc760c51d49e80861cb1c71674392f65ef` 的核心统计已经正确，
但它不满足所报告的 `git diff --check clean`：

```text
chromium-libcxx-20260717_143911/analysis/runs/20260717_143911/postbuild_correction_v2/rpm_size_comparison_v2.tsv:2: trailing whitespace.
+rpmbytessha256            0
```

该文件第 2 行还是 V2 prompt 明确要求删除的伪记录。本任务只修这一处证据卫生
问题；不得编译，不得修改 RPM，不得修改 Chromium 源码，不得改变任何统计结论。

## 1. 强制 preflight

在 chromium-efl 仓库执行：

```bash
git status --short --branch
git rev-parse HEAD
git branch --show-current
```

必须满足：

- HEAD 为 `a9ba89cc760c51d49e80861cb1c71674392f65ef`；
- 当前分支是或明确跟踪 `sandbox/lhmax2025/toolchain`；
- 工作树没有未提交修改。

任一项不满足立即停止并报告实际值，不要自行切分支、reset、rebase 或继续工作。

## 2. 唯一数据修正

目标文件：

```text
chromium-libcxx-20260717_143911/analysis/runs/20260717_143911/postbuild_correction_v2/rpm_size_comparison_v2.tsv
```

删除完整的第 2 行伪记录：

```text
rpmbytessha256            0
```

不要改表头和 8 个真实 RPM 行。修正后文件必须恰好 9 行：1 行表头加 8 行数据。

## 3. 生成检查证据

在同目录新增 `hygiene_verification_v3.txt`，至少记录：

```text
rpm_comparison_total_lines=9
rpm_comparison_data_lines=8
malformed_rpmbytessha256_rows=0
blank_package_rows=0
worktree_diff_check_exit=0
cached_diff_check_exit=0
```

注意：不能只写“clean”。必须真实执行检查、捕获退出码，退出码非 0 时停止。建议
顺序：

1. 修正 TSV；
2. 生成证据文件中前四项；
3. 执行 `git diff --check`，确认退出码 0 后记录；
4. `git add` 两个文件；
5. 执行 `git diff --cached --check`，确认退出码 0 后记录；如果为了写入 cached
   检查结果再次更新证据文件，必须重新 `git add` 并再次运行
   `git diff --cached --check`；
6. 提交前再运行一次 `git diff --cached --check`，必须没有输出且退出码为 0。

同时复核但不得改写以下正确值：

- G4：620 total、488 LIBCXX_CR、0 LIBSTDCXX_CXX11、1 ICU、131 OTHER；
- RPM：baseline 516543236、candidate 534832144、delta 18288908；
- 最终状态：`BUILD_SUCCESS_ABI_UNRESOLVED`。

## 4. 范围门禁

提交前 `git status --short` 只允许出现：

- 修改 `postbuild_correction_v2/rpm_size_comparison_v2.tsv`；
- 新增 `postbuild_correction_v2/hygiene_verification_v3.txt`。

任何其他文件变化都必须停止并报告，不得提交。

提交说明建议：

```text
Remove malformed RPM audit row
```

推送到 `sandbox/lhmax2025/toolchain` 后回报：

- 新 commit 完整 SHA；
- `git diff --check HEAD^ HEAD` 的真实退出码和完整输出（无输出也明确写“空”）；
- TSV 总行数、数据行数和伪记录命中数；
- 再次确认未编译、未修改 RPM、未修改 Chromium 源码；
- 最终状态仍为 `BUILD_SUCCESS_ABI_UNRESOLVED`。

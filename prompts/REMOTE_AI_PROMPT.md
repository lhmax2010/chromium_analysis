# 直接复制给高性能 PC 上 AI 的 Prompt

你要在高性能 PC 上完成 `chromium-efl` bundled libc++ 的构建和 ABI 门禁。你执行能力有限，所以不要自行简化、改写或重新设计流程。

开始时，你所在目录的直属子目录中必须已经有两份由用户复制好的完整源码仓库：

- `chromium-efl`：system-libstdc++ 基线，禁止修改、禁止打 patch。
- `chromium-efl_backup`：bundled libc++ 候选，只允许应用本任务指定 patch。

先在这个父目录执行 `export SOURCE_PARENT="$(pwd -P)"`。不要从
`review.tizen.org` 或其他位置 clone、fetch、pull 任何 Chromium 源码，也不要再复制第三份源码。

然后克隆 `git@github.com:lhmax2010/chromium_analysis.git`，完整阅读：

`guides/REMOTE_EXECUTION_GUIDE.md`

严格从第 1 节执行到第 10 节。第 3 节的“双源码硬门禁”必须完整执行并保存输出。该 guide 中的命令、停止条件、目录结构、期望值和报告字段都是任务要求。

双源码硬门禁的期望值：

```text
chromium-efl HEAD        = 394713cfd95e9597793255ec71496aef6ef84574
chromium-efl_backup HEAD = 394713cfd95e9597793255ec71496aef6ef84574
两边 HEAD tree           = 2e121f0da947838cf7242be6a1d6adb9e4b76312
两边 git status --porcelain = 空
两边必须是不同的真实目录和不同的 .git 目录
```

任何一个值不一致或命令失败时，必须立即停止并询问用户。禁止为了“修好”前置条件而执行
`git checkout`、`git reset`、`git clean`、`git restore`、`git fetch`、`git pull`、重新复制、打 patch 或开始构建。

硬规则：

1. 不使用 `git worktree`，不 clone 源码；只使用用户提供的 `chromium-efl` 和 `chromium-efl_backup`，并使用两个独立 GBS root。
2. Chromium 基线提交固定为 `394713cfd95e9597793255ec71496aef6ef84574`。
3. 基线 `chromium-efl` 不应用任何 patch。候选 `chromium-efl_backup` 只应用 `patches/bundled_libcxx_spike.patch`；其 SHA-256 必须是 `388985d2f1feb6e2ed5852240557b675634e849546eca2fc6296aa97199b32f2`。
4. 小修复配额已经 `5/5`。遇到新编译/链接错误，只保存完整诊断、按 A–E 分类、写报告并停止；不允许再改源码。
5. 涉及 libc++、libc++abi、llvm-libc、unwind、C ABI bridge 或打包结构的新变化，必须先停下请求用户批准。
6. 第一个错误必须保存完整翻译单元/链接动作诊断，包含 include 栈；不能只抄最后一行。
7. 所有原始输出写到 `runs/<RUN_ID>/`。对话只报告阶段结果、A–E 计数和每类一个代表样例。
8. 不把 RPM、`.so`、`.a`、`.o` 或 RPM 解包树提交到 GitHub，只提交日志、TSV、diff、SHA-256 和 Markdown 报告。
9. 构建成功后必须运行 `scripts/analyze_rpms.sh`，不能只看 GBS exit code。
10. `ewk_parse_cookie` 在本版本是裸 `extern "C"` 符号，通常不会形成 `_ZNSt7__cxx11` 到 `_ZNSt4__Cr` 的 mangling 对照；必须按实际 readelf 输出记录，不得伪造阳性对照。

最终交付：

- 按 `guides/REPORT_TEMPLATE.md` 完成 `runs/<RUN_ID>/report.md`。
- 把纯文本证据提交到新分支 `results/<RUN_ID>` 并 push。
- 回复用户该分支名、commit、报告路径、构建结果、耗时/体积、A–E 计数、G1–G4 和 bridge 门禁摘要。

如果任何 guide 前置条件不满足，停止并明确写 `UNRESOLVED` 以及缺少的材料，不要猜。

# chromium-efl bundled libc++ 分析迁移包

这个仓库把 `chromium-efl` bundled libc++ spike 的源码补丁、既有证据和远端执行手册集中在一起。原始 Chromium 源树、GBS buildroot、RPM 和 RPM 解包产物不进入 Git 历史。

当前结论不是“构建成功”：本机最后一次 attempt13 在 `12250/12257` 的最终 ThinLTO 链接阶段被任务策略终止，未产生可门禁的新 RPM。后续所有 Chromium 编译及产物分析必须在另一台高性能 PC 上完成。

给远端 AI 的入口：

1. 先让它完整阅读 [`guides/REMOTE_EXECUTION_GUIDE.md`](guides/REMOTE_EXECUTION_GUIDE.md)。
2. 再把 [`prompts/REMOTE_AI_PROMPT.md`](prompts/REMOTE_AI_PROMPT.md) 原样作为任务 prompt 发给它。
3. 最终报告必须按 [`guides/REPORT_TEMPLATE.md`](guides/REPORT_TEMPLATE.md) 填写，并把纯文本证据推回本仓库的新分支。

关键材料：

- `patches/bundled_libcxx_spike.patch`：以 Chromium 基线提交 `394713cfd95e9597793255ec71496aef6ef84574` 为基准的完整 8 文件补丁。
- `config/gbs_llvm.conf`：LLVM 平台底座配置模板；远端必须为基线/候选分别改写 buildroot。
- `evidence/read_only_census/`：GCC/LLVM 线、Rust、bundled libc++ 物料、EWK API 的前期只读证据。
- `evidence/spike_libcxx/`：attempt1–13 的日志、首错、病历、bridge 和 attempt12 门禁证据；不含 2.37 GiB 的 RPM 解包树。
- `scripts/run_gbs_build.sh`：只负责一条构建线并完整落盘日志。
- `scripts/capture_gn_args.sh`：在 GBS 尚未清理 out 目录时归档实际 GN 参数。
- `scripts/analyze_rpms.sh`：候选/基线 RPM 的 ELF 门禁和 G4 对比。

本机停止点与已知结论见 [`HANDOFF_STATE.md`](HANDOFF_STATE.md)。

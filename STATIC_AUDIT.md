# 上传前静态审计

审计日期：2026-07-17。

- 本仓库中的 shell 脚本均通过 `bash -n`。
- 本机未安装 `shellcheck`，因此该项标为 `UNAVAILABLE`；远端 preflight 可补跑。
- 补丁包含 8 个预期 diff sections，SHA-256 与 `patches/MANIFEST.md` 一致。
- 补丁已在干净基线 `394713cfd95e9597793255ec71496aef6ef84574` 上通过正向 `git apply --check`，并在 spike 工作树上通过反向检查。
- 敏感模式扫描未命中 GitHub/AWS token、私钥、Authorization header、URL 内嵌密码或明文 `password=`。
- 没有大于 95 MB 的文件；最大单文件是约 19.6 MB 的 attempt12 构建日志。
- `evidence/spike_libcxx/attempt12_rpm_extract/` 明确未上传。
- 没有 RPM、GBS buildroot 或 Chromium 源树被放入本仓库。
- 本审计没有运行编译，也没有对 attempt13 产物做分析。

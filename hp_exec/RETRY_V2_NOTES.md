# Stage 4 Retry 1 修正说明

## 已证实的首次失败原因

- 首次结果提交：`ff1704193562f208bc05f819206a72d6025911ab`。
- 首次归档 SHA256：`c2291d3ea72c43ba09e29fc2c31f193fc89b9b6bd7b4601b98e7be5740f3b5c2`。
- GBS 在正式 systemd transient service 内访问 Tizen 仓库超时；该服务记录的大小写代理变量均为空。
- 恢复探针在交互 shell 中通过当前代理访问 Base 与 Unified 仓库均得到 HTTP 200，因此问题定位为代理没有进入 transient service，而不是仓库整体不可达。
- 恢复探针执行时只有约 32 GiB `MemAvailable`，低于安全构建预算；不得在该状态启动构建。

## Retry 1 的机械修正

1. `precheck.sh` 同时从当前 shell 和显式继承代理的 systemd user service 访问两个仓库；任一失败即 `[PRECHECK-FAIL]`。
2. `precheck.sh` 要求至少 48 GiB `MemAvailable`，保留 16 GiB 给主机，并按安全内存预算自动计算 `MemoryMax` 与 `-j`。
3. `run_build.sh` 在创建 `build_started.marker` 前重新检查 `MemAvailable` 和预算，并在构建服务环境内再次访问两个仓库。
4. 正式 GBS transient service 显式接收 `HTTP_PROXY`、`HTTPS_PROXY`、`FTP_PROXY`、`NO_PROXY` 及其小写形式。
5. AI 不得自行终止占用内存的进程；资源不足时只回传失败证据并等待管理员处理。

本次修正只涉及执行脚本与文档，不修改 Chromium 源码，不修改输入 TSV/filter/allowlist，也不在低性能 PC 上执行构建。

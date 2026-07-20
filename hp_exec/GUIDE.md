# Stage 4 高性能 PC 零判断执行手册

固定候选源码提交：`111f88ff245928cc9db2a717185267054570300f`。固定基线提交：`394713cfd95e9597793255ec71496aef6ef84574`。

每条命令都在 `chromium_analysis` 仓库根目录执行。每一步只看该步最后的标记行。看到任何 `[PRECHECK-FAIL]` 或 `[STEP-N-FAIL]` 后，立即停止当前流程，不修改文件、不重试、不修复，直接执行 §5。

## §0 机器前置检查

目录必须是三个同级目录：`chromium_analysis/`、`chromium-efl/`、`chromium-efl_backup/`。两个 Chromium 目录都必须是独立且干净的 Git clone；backup 必须位于固定基线提交。工具、版本、输入 SHA256、Git 状态、至少 64 GiB RAM、至少 16 核、至少 350 GiB 可用磁盘和 systemd user service 全由脚本检查。脚本按内存与核数自动生成 `hp_exec/generated/stage4.env`；AI 不填写、不修改该文件。

依次原样执行：

```bash
mkdir -p hp_exec/logs
bash -o pipefail -c 'bash hp_exec/precheck.sh 2>&1 | tee hp_exec/logs/step0-precheck.console.log'
grep -F '[STEP-0-OK]' hp_exec/logs/step0-precheck.console.log
```

机械成功标准：第三条命令恰好输出一行 `[STEP-0-OK]`，且日志中没有 `FAIL`。否则执行 §5。

## §1 固定提交 checkout

脚本只从已校验的 `hp_exec/inputs/chromium_stage4.bundle` 导入提交，然后 detached checkout 固定 SHA；不拉分支、不联网、不打 patch。

```bash
bash -o pipefail -c 'bash hp_exec/checkout_source.sh 2>&1 | tee hp_exec/logs/step1-checkout.console.log'
grep -F '[STEP-1-OK]' hp_exec/logs/step1-checkout.console.log
```

机械成功标准：第二条命令恰好输出一行 `[STEP-1-OK]`，其中 candidate 与 backup SHA 分别等于本页顶部两个固定 SHA，且日志中没有 `FAIL`。否则执行 §5。

## §2 GBS 隔离构建

脚本先重生并比对两个 filter、扫描 bridge 头文件 C 纯度，再用 §0 自动生成的 `MemoryMax`、`MemoryHigh`、`CPUQuota` 和 `-j` 启动 systemd user transient service。构建命令固定为 gbs_llvm.conf、armv7l、`--include-all --overwrite`。不要同时启动其他构建。

```bash
bash -o pipefail -c 'bash hp_exec/run_build.sh 2>&1 | tee hp_exec/logs/step2-build.console.log'
grep -F '[STEP-2-OK]' hp_exec/logs/step2-build.console.log
```

机械成功标准：第二条命令恰好输出一行 `[STEP-2-OK]`，其中 `rpms=8`，且日志中没有 `FAIL`。否则执行 §5。

## §3 全量验收与文本采集

脚本自动解包刚生成的 RPM，运行 gate v2、断言旧 454 条外泄消失、重算 removed/added、记录 RPM 与 ELF section 尺寸、从未剥离产物提取文本符号证据，并以 ARM C probe + QEMU 执行 `LD_BIND_NOW` 的四 DSO `dlopen`。脚本不会复制 RPM、rootfs、out 目录或未剥离 `.so`。

```bash
bash -o pipefail -c 'bash hp_exec/run_verify.sh 2>&1 | tee hp_exec/logs/step3-verify.console.log'
grep -F '[STEP-3-OK]' hp_exec/logs/step3-verify.console.log
```

机械成功标准：第二条命令恰好输出一行 `[STEP-3-OK]`，其中同时出现 `gate=PASS`、`hidden_454=0`、`qemu_ld_bind_now=PASS`，且日志中没有 `FAIL`。否则执行 §5。

## §4 结果打包与推送

原样执行：

```bash
bash hp_exec/collect_results.sh
(cd hp_exec && sha256sum -c results_stage4.tar.gz.sha256)
git switch -C stage4-results-111f88ff
mkdir -p returned_results
cp hp_exec/results_stage4.tar.gz hp_exec/results_stage4.tar.gz.sha256 returned_results/
git add returned_results/results_stage4.tar.gz returned_results/results_stage4.tar.gz.sha256
git commit -m 'results: stage4 chromium libc++ verification'
git push origin HEAD:refs/heads/stage4-results-111f88ff
```

机械成功标准：第一条命令输出 `[STEP-4-OK]`；第二条输出 `OK`；最后一条退出码为 0。只报告远端分支 `stage4-results-111f88ff` 和提交 SHA。

## §5 故障处置

唯一允许的动作是停止、打包已有日志并推送。不要修改 Chromium 源码，不要修改脚本，不要清理目录，不要重试失败步骤。

在 `chromium_analysis` 根目录原样执行以下命令；若 `collect_results.sh` 本身打印 FAIL，只回报该 FAIL 行和此前失败步骤号，不再执行其他命令。

```bash
bash hp_exec/collect_results.sh
(cd hp_exec && sha256sum -c results_stage4.tar.gz.sha256)
git switch -C stage4-results-111f88ff
mkdir -p returned_results
cp hp_exec/results_stage4.tar.gz hp_exec/results_stage4.tar.gz.sha256 returned_results/
git add returned_results/results_stage4.tar.gz returned_results/results_stage4.tar.gz.sha256
git commit -m 'results: stage4 chromium libc++ failure evidence'
git push origin HEAD:refs/heads/stage4-results-111f88ff
```

最终只报告：第一个 FAIL 的完整标记行、失败步骤号、结果提交 SHA。不要附分析或修复建议。

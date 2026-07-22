# Stage 4 Retry 2 高性能 PC 零判断执行手册

固定 Gerrit 起点：`65e8e6d9a338b0ac64521fb04923f234924ecb70`。固定基线提交：`394713cfd95e9597793255ec71496aef6ef84574`。固定目标分支：`sandbox/lhmax2025/toolchain`。

每条命令都在新建的 `chromium_analysis_retry2` 根目录执行。不得修改命令、脚本或源码；源码修正、提交和结果推送全部由脚本完成。看到任何 FAIL 后立即停止当前流程并执行 §5，禁止重试。

## §0 机器与输入预检

三个同级目录必须是 `chromium_analysis_retry2/`、`chromium-efl/`、`chromium-efl_backup/`。脚本验证输入 SHA256、固定 Gerrit HEAD、两个源码仓状态、工具、代理、Tizen 仓库、至少 48 GiB `MemAvailable`、至少 300 GiB磁盘及 systemd user service；自动生成资源上限。

```bash
mkdir -p hp_exec_retry2/logs
bash -o pipefail -c 'bash hp_exec_retry2/precheck.sh 2>&1 | tee hp_exec_retry2/logs/step0-precheck.console.log'
grep -F '[STEP-0-OK]' hp_exec_retry2/logs/step0-precheck.console.log
```

成功标准：第三条恰好输出一行 `[STEP-0-OK]`，其中含 `repositories=OK`，且日志无 FAIL。否则执行 §5。

## §1 固定源码修正

脚本重新生成 354 条稳定非 STL Node 精确导出，验证 Retry 1 的 20 个可见缺失符号全部被覆盖，从固定 Gerrit HEAD detached checkout，生成 filter，并提交且仅提交三个预定源码文件。此步不推送。

```bash
bash -o pipefail -c 'bash hp_exec_retry2/prepare_source.sh 2>&1 | tee hp_exec_retry2/logs/step1-prepare.console.log'
grep -F '[STEP-1-OK]' hp_exec_retry2/logs/step1-prepare.console.log
```

成功标准：第二条恰好输出一行 `[STEP-1-OK]`，同时含 `node_nonstd=354 node_cr=7`，且日志无 FAIL。否则执行 §5。

## §2 GBS 隔离构建

脚本在创建构建标记前复核内存、磁盘、两个仓库和 Node filter 数量，再把代理显式传入受资源限制的 systemd service。构建固定使用 `gbs_llvm.conf`、armv7l、`--include-all --overwrite`。

```bash
bash -o pipefail -c 'bash hp_exec_retry2/run_build.sh 2>&1 | tee hp_exec_retry2/logs/step2-build.console.log'
grep -F '[STEP-2-OK]' hp_exec_retry2/logs/step2-build.console.log
```

成功标准：第二条恰好输出一行 `[STEP-2-OK]`，同时含 `rpms=8 node_nonstd=354 node_cr=7`，且日志无 FAIL。否则执行 §5。

## §3 Gate v2 与运行时验收

脚本运行 Gate v2、454 隐藏断言、removed/added 重算、RPM/ELF 尺寸采集、未剥离文本证据和 QEMU `LD_BIND_NOW` 四 DSO 加载验证。不会回传 RPM、rootfs、out 或未剥离二进制。

```bash
bash -o pipefail -c 'bash hp_exec_retry2/run_verify.sh 2>&1 | tee hp_exec_retry2/logs/step3-verify.console.log'
grep -F '[STEP-3-OK]' hp_exec_retry2/logs/step3-verify.console.log
```

成功标准：第二条恰好输出一行 `[STEP-3-OK]`，同时含 `gate=PASS hidden_454=0 qemu_ld_bind_now=PASS`，且日志无 FAIL。否则执行 §5。

## §4 打包并发布到现有 Gerrit 分支

```bash
bash hp_exec_retry2/collect_results.sh
(cd hp_exec_retry2 && sha256sum -c results_stage4.tar.gz.sha256)
bash -o pipefail -c 'bash hp_exec_retry2/publish_results.sh 2>&1 | tee hp_exec_retry2/logs/step5-publish.console.log'
grep -F '[STEP-5-OK]' hp_exec_retry2/logs/step5-publish.console.log
```

成功标准：第一条输出 `[STEP-4-OK]`，第二条输出 `OK`，第四条恰好输出一行 `[STEP-5-OK]`。脚本只 fast-forward 推送现有 `sandbox/lhmax2025/toolchain`，不创建新分支。最终报告源码修正提交、结果提交和归档 SHA256。

## §5 故障处置

唯一允许动作是收集现有证据并发布。不得修改、清理或重试。若以下任一步 FAIL，立即停止并报告该 FAIL；不要手工执行 Git 命令。

```bash
bash hp_exec_retry2/collect_results.sh
(cd hp_exec_retry2 && sha256sum -c results_stage4.tar.gz.sha256)
bash -o pipefail -c 'bash hp_exec_retry2/publish_results.sh 2>&1 | tee hp_exec_retry2/logs/step5-publish.console.log'
grep -F '[STEP-5-OK]' hp_exec_retry2/logs/step5-publish.console.log
```

最终只报告：最后一个成功 STEP、第一个 FAIL、`[STEP-5-OK]` 原文、Gerrit HEAD 和归档 SHA256。不要附加分析或修复建议。

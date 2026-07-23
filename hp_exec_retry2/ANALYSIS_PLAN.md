# Stage 4 Retry 2 回传分析预案

此文件供回传后的只读收口，不是高性能 PC 的操作说明。

1. 确认 Gerrit `sandbox/lhmax2025/toolchain` 以 fast-forward 方式包含 V2 固定起点 `daef2b191983f49c63b6489ab4ad307588b2fc1a`、三文件源码修正提交以及 `stage4_retry2_v2_results/` 结果提交。
2. 校验 `results_stage4.tar.gz.sha256`，核对 Step 0 至 Step 5 标记链；失败时以第一个 FAIL 为终点，不推断未执行步骤。
3. 源码修正必须只有 `node.filter`、生成脚本和 `node_nonstd_export_allowlist.tsv`；Node filter 必须有 354 个稳定非 STL精确符号、7 个 `__Cr` 精确符号和原 C 接口。
4. Retry 1 可见的 20 个 Node undefined family 必须不再出现；若 lld 仍失败，保存新一轮完整错误集合并与 354 TSV 交叉。
5. 成功构建时沿用 Gate v2 固定预期：G1 34/34/0、G2 41/41/0、G3 0、454 隐藏命中 0、bridge 92/92、QEMU `LD_BIND_NOW` PASS。
6. 核对 added/removed、RPM 总量、主 DSO 体积、`.dynsym/.dynstr`、资源耗时和未剥离 `__cxa_*` 文本归属；无证据项目保持 UNRESOLVED。
7. 全部门禁通过后才形成 PM 结论；仅链接成功不能视为 ABI 收口成功。

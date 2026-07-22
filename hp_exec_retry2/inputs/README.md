# Stage 4 Retry 2 固定输入

- `SOURCE_START_COMMIT`: Retry 2 开始时 Gerrit toolchain 分支必须匹配的固定 SHA。
- `chromium_stage4.bundle`: Retry 1 留存的源码身份输入；Retry 2 不从它 checkout。
- `internal_cr_allowlist.tsv`: 34 条允许留在包内的 libc++ C++ ABI 导出，V8 27、Node 7。
- `node_nonstd_export_allowlist.tsv`: 从固定基线快照机械生成的 354 条稳定非 STL Node 精确导出。
- `retry1_visible_undefined.demangled.txt`: Retry 1 被 lld 报出的 20 个 Node 缺失符号 family。
- `generate_libcxx_export_filters.sh`: Retry 2 源码生成器输入；由准备脚本复制进源码树。
- `v8_tizen.filter` / `node.filter`: 两份 ABI TSV 的确定性生成产物。
- `expected_hidden_cr_exports.tsv`: 旧候选中必须消失的 454 条无内部消费者 `__Cr` 导出。
- `expected_added_exports.tsv`: 166 条新增导出的允许上限；条目可以因收窄而消失，不可出现列表外新增导出。
- `baseline_exports.tsv`: 全 RPM 基线 GLOBAL/WEAK 导出快照。
- `bridge_export_allowlist.txt`: bridge 的 92 条 C 导出白名单。
- `baseline_rpm_inventory.tsv` / `baseline_rpm_total_bytes.txt`: 固定基线 RPM 大小证据，总计 516543236 bytes。
- `removed_59_input.tsv` / `removed_59_triage.tsv`: Stage 4 本机完成的 residual removed 分诊输入与结果。
- `abi_gate_v2.sh`: 带 internal allowlisted-G1/G2 分类的镜像门禁。
- `dlopen_probe.c`: 高性能机以目标 clang 编译、QEMU 执行的 `RTLD_NOW` C probe。

`SHA256SUMS` 覆盖本目录除自身外的全部文件。

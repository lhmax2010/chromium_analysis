# Stage 4 固定输入

- `chromium_stage4.bundle`: 从基线 `394713c...` 到候选 `111f88f...` 的增量 Git bundle；高性能机无需联网拉第二份源码。
- `internal_cr_allowlist.tsv`: 34 条允许留在包内的 libc++ C++ ABI 导出，V8 27、Node 7。
- `v8_tizen.filter` / `node.filter`: 上述 TSV 的确定性生成产物。
- `expected_hidden_cr_exports.tsv`: 旧候选中必须消失的 454 条无内部消费者 `__Cr` 导出。
- `expected_added_exports.tsv`: 166 条新增导出的允许上限；条目可以因收窄而消失，不可出现列表外新增导出。
- `baseline_exports.tsv`: 全 RPM 基线 GLOBAL/WEAK 导出快照。
- `bridge_export_allowlist.txt`: bridge 的 92 条 C 导出白名单。
- `baseline_rpm_inventory.tsv` / `baseline_rpm_total_bytes.txt`: 固定基线 RPM 大小证据，总计 516543236 bytes。
- `removed_59_input.tsv` / `removed_59_triage.tsv`: Stage 4 本机完成的 residual removed 分诊输入与结果。
- `abi_gate_v2.sh`: 带 internal allowlisted-G1/G2 分类的镜像门禁。
- `dlopen_probe.c`: 高性能机以目标 clang 编译、QEMU 执行的 `RTLD_NOW` C probe。

`SHA256SUMS` 覆盖本目录除自身外的全部文件。

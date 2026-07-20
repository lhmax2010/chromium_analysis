# Stage 4 本机只读/静态工作结果

本机未运行 GN gen、Ninja、GBS 或链接命令。

## 59 条 removed 分诊

`removed_59_triage.tsv` 含 1 行表头和 59 行数据：

- `NAMED_ABI_MIGRATION`: 5
- `LIBSTDCXX_REGEX_INTERNAL`: 17
- `LIBSTDCXX_SHARED_PTR_INTERNAL`: 27
- `LIBSTDCXX_OTHER_INTERNAL`: 10

5 条可找到同名/同义候选实现；其余 54 条是 libstdc++ 实现符号，没有可证实的一对一 libc++ symbol。59 条对既有外部二进制均仍属于 removed ABI 风险。

## Stage 4 源码固定点

源码固定提交为 `111f88ff245928cc9db2a717185267054570300f`，基于 `394713cfd95e9597793255ec71496aef6ef84574`。34 条内部 `__Cr` allowlist 由入库 TSV 确定性生成：V8 27 条、Node 7 条；Node embedder module version 在 Tizen bundled-libc++ 路径加 `1000000` 偏移。

## gate v2 修改

Stage 4 gate 在参数/规范化区新增精确 `provider-DSO<TAB>symbol` allowlist，把 G1 分为 allowlisted、unallowlisted、missing，把 G2 分为能解析到批准 provider symbol 的内部引用与未批准引用。只有 allowlisted 的 34 条导出及其 41 条包内引用可通过；新增、遗漏或外部化 `__Cr` 仍为硬失败。

旧候选负面对照的机械分区为 G1 `493/34/459`、G2 `43/41/2`，状态仍为 FAIL，详见 `evidence/stage4_gate/gate_v2_negative_partition.txt`。

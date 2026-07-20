# Stage 4 回传结果一次性分析预案

此文件供结果回传后的本地收口使用，不是高性能 PC 的操作说明。

## 1. 包完整性与执行链

1. 对 `results_stage4.tar.gz` 执行随包 SHA256 校验。
2. 查 `collection_summary.txt` 与四份 console log；正常链必须各出现一次 `[STEP-0-OK]`、`[STEP-1-OK]`、`[STEP-2-OK]`、`[STEP-3-OK]`，并有 `[STEP-4-OK]`，不得出现任何 FAIL。
3. 核对 `repository_state.txt`：候选必须是 `111f88ff245928cc9db2a717185267054570300f`，backup 必须是 `394713cfd95e9597793255ec71496aef6ef84574`。
4. 核对 `RETURN_MANIFEST.tsv`，确认无 RPM、rootfs/out、ELF、未剥离 `.so`；未剥离信息只能以 `nm/readelf` 文本存在。

## 2. 门禁预期表

| 项目 | PASS 预期 |
|---|---:|
| G1 full-signature | 34 |
| G1 allowlisted / unallowlisted / missing | 34 / 0 / 0 |
| G2 full-signature | 41 |
| G2 allowlisted / unallowlisted | 41 / 0 |
| G3 NEEDED libc++/libc++abi | 0 |
| 原 454 条无内部消费者 `__Cr` 仍导出 | 0 |
| 新增导出 | 34..166，全部在上限 allowlist 内 |
| bridge actual / whitelist | 92 / 92 |
| bridge unexpected / missing / `_ZNSt*` | 0 / 0 / 0 |
| bridge NEEDED libstdc++ | 至少 1 条，gate 计数为 1 |
| QEMU + LD_BIND_NOW 四 DSO dlopen | PASS |
| embedder module version | 1000137 |

若 gate summary 与表不符，直接以对应 TSV 为证据分类，不向高性能机补要二进制。

## 3. removed/added 与 59 条分诊合并

1. 用 `verify_results/removed_exports.tsv` 对 `package_inputs/removed_59_triage.tsv` 的 `baseline_mangled` 做 symbol join；59 条必须全部仍在 removed 集。
2. 保留原分诊四类计数：named ABI migration 5、regex internal 17、shared_ptr internal 27、other internal 10。
3. 对 5 条 named replacement 再与 Stage 4 candidate exports join：预期仅 `ValidateAndCanonicalizeUnicodeLocaleId` 的 `__Cr` 新符号属于 34 条内部 allowlist；其余 4 条应被 version script 隐藏。此项以回传 TSV 实测为准。
4. 将 Stage 4 新增导出按 `LIBCXX_CR / ICU / OTHER` 重新聚类；任何不在 `expected_added_exports.tsv` 的条目为硬失败，allowlist 内但消失的条目只记为收口收益。

## 4. libc++abi、unwind 与体积

1. 在 `unstripped_runtime_symbol_ownership.tsv` 查 `libchromium-impl.so` 的 `__cxa_throw`、`__cxa_begin_catch`、`__cxa_guard_acquire`；类型 `T/t` 才能把 libc++abi 静态归属从 UNRESOLVED 收口为 CONFIRMED。
2. 结合 packaged dynamic dump 确认无 libc++/libc++abi NEEDED；用 `Unwind*` 文本与 NEEDED `libgcc_s` 对照。
3. 从 `rpm_size_summary.txt` 读取候选总量，与固定基线 `516543236` bytes 比较；从 `primary_dso_sizes.tsv` 读取 `libchromium-ewk.so` 大小；从 `dyn_sections.tsv` 汇总 `.dynsym/.dynstr`。
4. 从 `build_resource_time.txt` 与 `build_service_result.txt` 报 wall time、max RSS/MemoryPeak、CPU 限额和退出状态。旧的 `41552306` 数字仍不得作为有来源的基线。

## 5. 最终状态判定

- 全部门禁和 QEMU 均 PASS，454 为零，且三项 `__cxa_*` 在未剥离 `libchromium-impl.so` 为 `T/t`：可从 AMBER 推进到“构建与镜像门禁通过，libc++abi 归属已证实”，外部消费者风险单列。
- 构建成功但任一 ABI 门禁失败：保持 `BUILD_SUCCESS_ABI_UNRESOLVED`，逐项引用失败 TSV。
- 构建或 QEMU 失败：保持 AMBER，不推断根因，只引用首个完整错误与资源记录。

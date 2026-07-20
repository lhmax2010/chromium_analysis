# 给高性能服务器 AI：bundled libc++ 构建后修正审计（禁止重编）

你只执行构建后的证据补采和报告修正。不得运行 `gbs build`、`ninja`、
`gn gen`、编译器或链接器；不得修改 Chromium 源码、spec、patch 或既有原始证据。

## 0. 已知状态与任务边界

- Gerrit 仓库：`platform/framework/web/chromium-efl`
- 结果分支：`sandbox/lhmax2025/toolchain`
- 当前结果 HEAD：`bdde5088b4ef3401d71d2199735531e9e8005ece`
- RUN_ID：`20260717_143911`
- Chromium 基线：`394713cfd95e9597793255ec71496aef6ef84574`
- 原报告：`chromium-libcxx-20260717_143911/analysis/runs/20260717_143911/report.md`

当前已确认基线和候选都构建成功。你不是来重新构建，也不是来修源码，而是修正
ABI 门禁覆盖范围、证据链和报告表述。

硬停止条件：

1. 当前分支或 HEAD 与上面不一致时，停止询问用户。
2. 基线/候选 RPM 任一缺失或 SHA-256 校验失败时，停止询问用户。
3. 原始构建目录或 RPM 已被删除，导致某项无法补证时，不得重编；将该项标
   `UNRESOLVED`，报告缺失材料并停止等待用户决定。
4. 不覆盖 `report.md`、`gate_summary.txt` 或其他既有证据。
5. 不删除任何输入、RPM、构建目录或既有日志。

## 1. 定位输入并建立全新输出目录

在 Gerrit sandbox 工作树根目录执行：

```bash
set -euo pipefail

export RUN_ID=20260717_143911
export EXPECTED_HEAD=bdde5088b4ef3401d71d2199735531e9e8005ece
export SANDBOX_REPO="$(git rev-parse --show-toplevel)"
export ANALYSIS_ROOT="$SANDBOX_REPO/chromium-libcxx-$RUN_ID/analysis"
export COMMITTED_RUN="$ANALYSIS_ROOT/runs/$RUN_ID"
export OUT="$COMMITTED_RUN/postbuild_correction"
export ARTIFACT_ROOT="$HOME/chromium-libcxx-$RUN_ID/artifacts"
export BASELINE_RPMS="$ARTIFACT_ROOT/baseline_rpms"
export CANDIDATE_RPMS="$ARTIFACT_ROOT/candidate_rpms"

test "$(git branch --show-current)" = sandbox/lhmax2025/toolchain
test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"
test -f "$COMMITTED_RUN/report.md"
test -d "$BASELINE_RPMS"
test -d "$CANDIDATE_RPMS"
test ! -e "$OUT"
mkdir -p "$OUT"

{
  date --iso-8601=seconds
  uname -a
  git rev-parse HEAD
  git status --short --branch
  printf 'analysis_root=%s\n' "$ANALYSIS_ROOT"
  printf 'committed_run=%s\n' "$COMMITTED_RUN"
  printf 'baseline_rpms=%s\n' "$BASELINE_RPMS"
  printf 'candidate_rpms=%s\n' "$CANDIDATE_RPMS"
} > "$OUT/preflight.txt" 2>&1
```

如果实际目录不同，不得全盘搜索或猜测；停止询问用户给出路径。

## 2. RPM 身份、大小与 SHA-256

两边都必须恰好有 8 个 `chromium-efl*.armv7l.rpm`。生成：

- `baseline_rpm_inventory.tsv`
- `candidate_rpm_inventory.tsv`
- `rpm_size_comparison.tsv`
- `rpm_checksum_verification.txt`

inventory 固定列：

```text
rpm	bytes	sha256
```

每个 RPM 的 bytes 必须来自 `stat -c %s`，SHA-256 必须现场重算。分别求总和，
不要从旧报告复制数字。再执行既有：

```bash
sha256sum -c "$COMMITTED_RUN/baseline_rpm_sha256.txt"
sha256sum -c "$COMMITTED_RUN/candidate_rpm_sha256.txt"
```

完整输出写入 `rpm_checksum_verification.txt`。任何失败立即停止；不要继续扫描。

## 3. 在仓库外串行解包 RPM

新建唯一 scratch；不得使用或删除既有解包树：

```bash
export SCRATCH="$(mktemp -d "$HOME/chromium-postbuild-$RUN_ID.XXXXXX")"
printf '%s\n' "$SCRATCH" > "$OUT/scratch_path.txt"
mkdir -p "$SCRATCH/baseline" "$SCRATCH/candidate"
```

对每个 RPM 串行执行 `rpm2cpio | cpio -idm --quiet`，分别解到以 RPM 文件名命名
的子目录。命令和完整 stderr/stdout 写入 `rpm_extract.log`。不要并行解包。

## 4. 扩大 C++ ABI 门禁：匹配符号任意位置

旧 G1/G2 只匹配符号开头的 `^_ZNSt4__Cr|^_ZNSt3__1`，会漏掉：

```text
_ZN4node...NSt4__Cr...
```

必须新建并保存 `$OUT/scan_expanded_abi.sh`，先用 `bash -n` 检查，再运行。
脚本必须对候选 RPM 内全部真实 ELF `.so`/`.so.*` 串行执行：

```bash
readelf --dyn-syms -W
```

原始输出写入 `$OUT/candidate_dynsym_raw/`。规则：

- 只处理以 `_Z` 开头的 C++ 符号。
- libc++ 模式必须是 `NSt4__Cr|NSt3__1`，不得加 `^` 锚点。
- 导出：GLOBAL/WEAK 且 Ndx 非 UND。
- 消费：Ndx 为 UND。
- 匹配依赖边时去掉 `@VERSION` 后缀，但原始符号仍要保留。
- 每个符号必须调用 `c++filt`；失败或输出仍等于输入时写
  `unknown_symbols.txt`，不得丢弃。

生成：

- `candidate_expanded_exports.tsv`：
  `dso,bind,raw_symbol,match_symbol,demangled`
- `candidate_expanded_und.tsv`：同列结构
- `candidate_expanded_edges.tsv`：
  `consumer_dso,provider_dso,match_symbol,demangled`
- `candidate_expanded_unmatched_exports.tsv`
- `candidate_expanded_counts_by_dso.tsv`
- `candidate_expanded_summary.txt`
- `unknown_symbols.txt`

若 B 的 UND `match_symbol` 能在 A 的导出集中解析，建立 `B -> A`。多 provider
时每个 provider 单独一行，不得任意挑一个。

最低自检：

- 候选导出中含 `NSt4__Cr|NSt3__1` 的数量不得少于 488。
- 既有 G4 已知 `libv8.so=464`、`libnode.so=24`；若新结果不一致，先检查脚本，
  不得写结论。

用相同方法扫描基线的 `NSt7__cxx11|B5cxx11`，输出
`baseline_cxx11_exports.tsv`、`baseline_cxx11_und.tsv` 和按 DSO 统计。

边界分类：

- `INTERNAL_RESOLVED`：provider 和 consumer 都在本次候选 RPM 集合。
- `EXPORTED_NO_INTERNAL_CONSUMER`：有导出但本 RPM 集合内无消费者；这是潜在外部
  ABI 暴露，不能写 PASS。
- `UND_UNRESOLVED_IN_SET`：候选 UND 在本集合找不到 provider。

本任务没有完整 Tizen rootfs 时，不得声称“没有外部消费者”。必须明确扫描范围只覆盖
本次 chromium-efl RPM。

## 5. 重算 bridge 白名单

旧结果的 2 个 unexpected 是排序 locale 假阳性。用同一 locale 对两侧规范化：

```bash
LC_ALL=C sort -u +  "$COMMITTED_RUN/abi_analysis/bridge_exports.actual.txt" +  > "$OUT/bridge_exports.actual.canonical.txt"

LC_ALL=C sort -u +  "$ANALYSIS_ROOT/evidence/spike_libcxx/wrt_bridge_export_whitelist.standard.txt" +  > "$OUT/bridge_exports.whitelist.canonical.txt"

comm -23 "$OUT/bridge_exports.actual.canonical.txt" +  "$OUT/bridge_exports.whitelist.canonical.txt" +  > "$OUT/bridge_exports.unexpected.corrected.txt"

comm -13 "$OUT/bridge_exports.actual.canonical.txt" +  "$OUT/bridge_exports.whitelist.canonical.txt" +  > "$OUT/bridge_exports.missing.corrected.txt"
```

预期：actual=92、whitelist=92、unexpected=0、missing=0。实际不符则如实报告并停止，
不得修改白名单。

## 6. G4 分类修正

基于既有 `g4_added.tsv`、`g4_removed.tsv`，生成
`g4_classification_corrected.tsv` 和按 DSO 统计。至少分类：

- `LIBCXX_CR`：`NSt4__Cr|NSt3__1`
- `LIBSTDCXX_CXX11`：`NSt7__cxx11|B5cxx11`
- `ICU`
- `OTHER`

已知自检值：

- added 总数 620
- added `LIBCXX_CR` 488，其中 libv8.so=464、libnode.so=24
- removed 总数 1062
- removed `LIBSTDCXX_CXX11` 352

不得继续写“差异主要由 ICU 引起”；分类数字必须进入修正版报告。

## 7. 修正内存和体积证据

从 `baseline_build/build.time` 与 `candidate_build/build.time` 原样提取 GNU time：

- baseline Maximum resident set size：16581724 kbytes
- candidate Maximum resident set size：17480900 kbytes

把提取命令和输出写 `memory_evidence.txt`。这两个值是 GNU time 的最大进程 RSS，
不得称为 cgroup aggregate MemoryPeak。

搜索所有既有文本证据中的 `41552306`。若它只存在于旧 `report.md`，则将
`~41552306 link peak` 标 `UNRESOLVED/UNANCHORED`，不得继续当原始测量。

RPM 总大小只采用第 2 节现场 `stat` 总和。

## 8. libc++abi 与 unwind 解析

unwind：只有 UND `_Unwind*` 与同一 DSO 的 NEEDED `libgcc_s.so.1` 对得上时才写
“由 libgcc_s 解析”。

libc++abi：以下事实不够证明静态链入：

- 构建日志出现 `AR .../libc++abi.a`
- DSO 没有 NEEDED `libc++abi.so`
- 只有 `__cxa_atexit@GLIBC_2.4` 之类 UND

必须从现存构建目录采到至少一种直接证据：

1. `libchromium-impl.so` 最终 link command/rsp 明确包含 `libc++abi.a`；或
2. 完整 `readelf -Ws`、未剥离文件、debug 文件或 link map 显示 libc++abi
   实现符号由该 DSO 定义。

命令输出写入 `libcxxabi_resolution_evidence.txt`。如果构建目录/RSP/link map
不存在或产物已剥离而无法证明，结论必须是 `UNRESOLVED`，不得重编。

## 9. 重生成数值 gate summary

旧 `gate_summary.txt` 中部分字段是未展开的字面量 `$(wc -l ...)`。不要覆盖它，
新建 `gate_summary.corrected.txt`，每一项都必须是实际整数并能由对应 TSV
`wc -l` 重算。

## 10. 生成修正版报告

保留原 `report.md`，新建：

`$COMMITTED_RUN/report.corrected.md`

必须包含：

1. 构建成功事实与 exit code。
2. 原始 prefix G1/G2 结果，以及 expanded-anywhere G1b/G2b 结果。
3. 488 个 `__Cr` 导出的 DSO 分布、内部依赖边和 unmatched 暴露。
4. bridge canonical set 比较结果。
5. 修正后的 G4 分类。
6. 有证据的 RPM 大小、GNU time RSS；无证据值标 UNRESOLVED。
7. libc++abi/unwind 的证据强度。
8. 扫描范围限制。

只允许以下最终状态：

- `BUILD_SUCCESS_ABI_ACCEPTED`：expanded 边界全部解释，且没有未知外部 ABI 暴露。
- `BUILD_SUCCESS_ABI_RISK`：存在明确跨边界 `std::__Cr` 消费或未隔离公开 ABI。
- `BUILD_SUCCESS_ABI_UNRESOLVED`：外部消费者范围或关键证据缺失。

仅凭当前 chromium RPM 集合无法排除外部消费者时，默认
`BUILD_SUCCESS_ABI_UNRESOLVED`，不是 `SUCCESS`。

## 11. 提交纯文本证据

只提交：

- `postbuild_correction/`
- `report.corrected.md`

提交前：

```bash
git status --short
find "$OUT" -type f -size +95M -print
git add "$OUT" "$COMMITTED_RUN/report.corrected.md"

if git diff --cached --name-only | +  rg '\.(rpm|src\.rpm|so(\..*)?|a|o|tar(\..*)?|zip)$|_rpm_extract/'; then
  echo 'STOP: binary or extraction tree staged' >&2
  exit 1
fi

git diff --cached --check
git commit -m "Correct bundled libc++ post-build ABI audit"
git push origin sandbox/lhmax2025/toolchain
```

若 `find ... -size +95M` 有输出，停止询问，不得删除或拆分后擅自提交。

最终对话只报告：commit、最终状态、expanded export/UND/edge 数、按 DSO 分布、
bridge 结果、G4 分类、内存/体积修正、libc++abi 状态和所有 UNRESOLVED。

# 高性能 PC 执行手册：chromium-efl bundled libc++ 构建与 ABI 门禁

本手册面向执行能力有限的自动化 AI。必须按顺序执行，不得跳步，不得把推测写成结论。所有原始输出落盘，对话只汇报阶段结果、错误分类计数和每类一个样例。

## 0. 任务边界

目标有两个：

1. 在 `gbs_llvm.conf` 线上，用本仓库补丁构建 bundled libc++ 候选 RPM。
2. 用同一基线提交的正常 system-libstdc++ RPM 做 G4 基线，完成 G1–G4、bridge、`__cxa/Unwind`、体积和耗时对比。

禁止事项：

- 不得修改补丁以外的 Chromium 文件。
- 不得 force-push、覆盖已有 evidence、删除输入源树或 GBS root。
- 小修复配额已是 `5/5`；遇到任何新源码错误时只采证并停下。
- 不得把本机 attempt13 写成成功；它没有完成链接。
- 不得把 RPM、`.so`、解包树提交到 `chromium_analysis` Git 仓库。

## 1. 机器预检

推荐最低资源：32 GiB RAM、300 GiB 可用磁盘。推荐 64 GiB RAM、500 GiB 可用磁盘。先执行：

```bash
set -o pipefail
date --iso-8601=seconds
uname -a
free -h
df -h "$HOME"
nproc
command -v git gbs rpm rpm2cpio cpio readelf c++filt file systemd-run
gbs --version
```

若 RAM 少于 32 GiB 或可用磁盘少于 300 GiB，停止并报告，不要尝试构建。

构建并发建议：

| RAM | `JOBS` | service `MemoryMax` |
|---:|---:|---:|
| 32–47 GiB | 4 | 24G |
| 48–63 GiB | 6 | 36G |
| ≥64 GiB | 8 | 48G |

不要把 `JOBS` 设为 `nproc`；Chromium ThinLTO 会产生显著内存和磁盘压力。

## 2. 建立运行目录并克隆分析仓库

```bash
export RUN_ID="$(date +%Y%m%d_%H%M%S)"
export RUN_ROOT="$HOME/chromium-libcxx-$RUN_ID"
mkdir -p "$RUN_ROOT"
cd "$RUN_ROOT"

git clone git@github.com:lhmax2010/chromium_analysis.git analysis
cd analysis
git rev-parse HEAD | tee "$RUN_ROOT/analysis_commit.txt"
sha256sum patches/bundled_libcxx_spike.patch
```

SHA-256 必须等于：

```text
388985d2f1feb6e2ed5852240557b675634e849546eca2fc6296aa97199b32f2
```

不相等就停止。

创建结果分支；不要直接提交到 `main`：

```bash
git switch -c "results/$RUN_ID"
mkdir -p "runs/$RUN_ID"
export RESULT_DIR="$RUN_ROOT/analysis/runs/$RUN_ID"
```

## 3. 验证用户提供的两个独立源码副本

由于源码体积和网络限制，本任务不 clone、fetch 或 pull Chromium。用户会在同一个父目录下提供：

- `chromium-efl`：system-libstdc++ 基线，禁止修改。
- `chromium-efl_backup`：bundled libc++ 候选，只允许应用本任务 patch。

开始第 2 节前应已在该父目录执行 `export SOURCE_PARENT="$(pwd -P)"`。若变量未设置或目录名不符，停止询问用户；不要猜路径。

执行下面的完整硬门禁。它检查 commit、tree、全部未跟踪文件、真实 `.git` 目录以及会被 patch 修改的文件是否共享 inode：

```bash
: "${SOURCE_PARENT:?STOP: SOURCE_PARENT 未设置，请询问用户}"

export EXPECTED_COMMIT=394713cfd95e9597793255ec71496aef6ef84574
export EXPECTED_TREE=2e121f0da947838cf7242be6a1d6adb9e4b76312
export BASELINE_SRC="$(readlink -f "$SOURCE_PARENT/chromium-efl")"
export CANDIDATE_SRC="$(readlink -f "$SOURCE_PARENT/chromium-efl_backup")"
export SOURCE_VALIDATION="$RESULT_DIR/source_pair_validation.txt"

validation_failed=0
BASE_GIT_DIR=
CAND_GIT_DIR=

check_source_repo() {
  local role=$1
  local path=$2
  local head tree status git_dir common_dir

  echo "[$role] path=$path"
  if [[ ! -d "$path" ]]; then
    echo "FAIL: missing directory"
    validation_failed=1
    return
  fi
  if [[ ! -d "$path/.git" ]]; then
    echo "FAIL: .git is missing or is a linked-worktree gitfile"
    validation_failed=1
    return
  fi

  head=$(git -C "$path" rev-parse HEAD 2>&1) || {
    echo "FAIL: rev-parse HEAD: $head"
    validation_failed=1
    return
  }
  tree=$(git -C "$path" rev-parse 'HEAD^{tree}' 2>&1) || {
    echo "FAIL: rev-parse tree: $tree"
    validation_failed=1
    return
  }
  status=$(git -C "$path" status --porcelain --untracked-files=all 2>&1) || {
    echo "FAIL: git status: $status"
    validation_failed=1
    return
  }
  git_dir=$(readlink -f "$(git -C "$path" rev-parse --absolute-git-dir)")
  common_dir=$(readlink -f "$(git -C "$path" rev-parse --path-format=absolute --git-common-dir)")

  echo "HEAD=$head"
  echo "TREE=$tree"
  echo "GIT_DIR=$git_dir"
  echo "COMMON_DIR=$common_dir"
  echo "STATUS_LINES=$(printf '%s\n' "$status" | sed '/^$/d' | wc -l)"

  [[ "$head" == "$EXPECTED_COMMIT" ]] || {
    echo "FAIL: HEAD mismatch; expected $EXPECTED_COMMIT"
    validation_failed=1
  }
  [[ "$tree" == "$EXPECTED_TREE" ]] || {
    echo "FAIL: tree mismatch; expected $EXPECTED_TREE"
    validation_failed=1
  }
  [[ -z "$status" ]] || {
    echo "FAIL: worktree/index/untracked files are not clean"
    printf '%s\n' "$status"
    validation_failed=1
  }

  if [[ "$role" == baseline ]]; then
    BASE_GIT_DIR=$git_dir
  else
    CAND_GIT_DIR=$git_dir
  fi
}

{
  check_source_repo baseline "$BASELINE_SRC"
  check_source_repo candidate "$CANDIDATE_SRC"

  [[ "$BASELINE_SRC" != "$CANDIDATE_SRC" ]] || {
    echo "FAIL: baseline and candidate resolve to the same directory"
    validation_failed=1
  }
  [[ -n "$BASE_GIT_DIR" && -n "$CAND_GIT_DIR" && "$BASE_GIT_DIR" != "$CAND_GIT_DIR" ]] || {
    echo "FAIL: baseline and candidate do not have independent .git directories"
    validation_failed=1
  }

  for rel in \
    build/config/c++/BUILD.gn \
    packaging/chromium-efl.spec \
    tizen_src/build/gn_chromiumefl.sh \
    tizen_src/ewk/chromium-ewk.filter \
    wrt/BUILD.gn \
    wrt/cxx_wrapper/BUILD.gn; do
    base_inode=$(stat -c '%d:%i' "$BASELINE_SRC/$rel") || {
      echo "FAIL: cannot stat baseline $rel"
      validation_failed=1
      continue
    }
    cand_inode=$(stat -c '%d:%i' "$CANDIDATE_SRC/$rel") || {
      echo "FAIL: cannot stat candidate $rel"
      validation_failed=1
      continue
    }
    echo "INODE $rel baseline=$base_inode candidate=$cand_inode"
    [[ "$base_inode" != "$cand_inode" ]] || {
      echo "FAIL: source files are hardlinked: $rel"
      validation_failed=1
    }
  done

  if (( validation_failed == 0 )); then
    echo "SOURCE_PAIR_STATUS=PASS"
  else
    echo "SOURCE_PAIR_STATUS=FAIL"
  fi
} > "$SOURCE_VALIDATION" 2>&1

cat "$SOURCE_VALIDATION"
if (( validation_failed != 0 )); then
  echo "STOP: source validation failed. Ask the user; do not repair or continue." >&2
  exit 3
fi
```

任何检查失败时，立即停止并询问用户。禁止执行 `git checkout`、`git reset`、`git clean`、`git restore`、重新复制、打 patch 或构建来尝试修复。

只对候选副本应用补丁：

```bash
cd "$CANDIDATE_SRC"
git apply --check "$RUN_ROOT/analysis/patches/bundled_libcxx_spike.patch"
git apply "$RUN_ROOT/analysis/patches/bundled_libcxx_spike.patch"
git status --short | tee "$RESULT_DIR/candidate_git_status.txt"
git diff --check | tee "$RESULT_DIR/candidate_diff_check.txt"
git diff --stat | tee "$RESULT_DIR/candidate_diff_stat.txt"

git -C "$BASELINE_SRC" status --porcelain --untracked-files=all \
  | tee "$RESULT_DIR/baseline_status_after_candidate_patch.txt"
test ! -s "$RESULT_DIR/baseline_status_after_candidate_patch.txt" || {
  echo "STOP: candidate patch affected baseline; ask the user" >&2
  exit 4
}
```

`candidate_git_status.txt` 应只有以下 8 项：

```text
 M build/config/c++/BUILD.gn
 M packaging/chromium-efl.spec
 M tizen_src/build/gn_chromiumefl.sh
 M tizen_src/ewk/chromium-ewk.filter
 M wrt/BUILD.gn
 M wrt/cxx_wrapper/BUILD.gn
?? wrt/cxx_wrapper/build.sh
?? wrt/cxx_wrapper/wrt-c++wrapper.map
```

多一项或少一项都停止。

## 4. 构建前 bridge C 纯度门禁

在候选源码目录执行：

```bash
cd "$CANDIDATE_SRC"
{
  echo '$ rg -n C++/STL patterns in bridge headers'
  rg -n 'std::|#include[[:space:]]*<(string|vector|map|memory|list|deque|set|unordered_map|unordered_set|filesystem)>' \
    wrt/cxx_wrapper/wgt_manifest_handlers.h \
    wrt/cxx_wrapper/tv/settings_api.h || true
} > "$RESULT_DIR/bridge_header_c_purity.txt" 2>&1

hits=$(rg -c '^[^$].*:[0-9]+:' "$RESULT_DIR/bridge_header_c_purity.txt" || true)
echo "bridge_header_cpp_hits=${hits:-0}" | tee "$RESULT_DIR/bridge_header_c_purity.summary.txt"
```

预期 `bridge_header_cpp_hits=0`。非零立即停止；不要开始构建。

同时保存 bridge 实现和打包机制的锚点：

```bash
rg -n '__use_bundled_libcxx|cxx_wrapper/build.sh|libwrt-c\+\+wrapper|use_custom_libcxx|use_system_icu' \
  packaging/chromium-efl.spec tizen_src/build/gn_chromiumefl.sh \
  wrt/BUILD.gn wrt/cxx_wrapper/BUILD.gn wrt/cxx_wrapper/build.sh \
  > "$RESULT_DIR/prebuild_patch_anchors.txt"
```

## 5. 为基线和候选创建独立 GBS root

```bash
export BASE_GBS_ROOT="$HOME/GBS-ROOT-CHROMIUM-BASE-$RUN_ID"
export CAND_GBS_ROOT="$HOME/GBS-ROOT-CHROMIUM-LIBCXX-$RUN_ID"

sed "s#^buildroot =.*#buildroot = $BASE_GBS_ROOT#" \
  "$RUN_ROOT/analysis/config/gbs_llvm.conf" \
  > "$RUN_ROOT/gbs_baseline.conf"

sed "s#^buildroot =.*#buildroot = $CAND_GBS_ROOT#" \
  "$RUN_ROOT/analysis/config/gbs_llvm.conf" \
  > "$RUN_ROOT/gbs_libcxx.conf"

cp "$RUN_ROOT/gbs_baseline.conf" "$RESULT_DIR/"
cp "$RUN_ROOT/gbs_libcxx.conf" "$RESULT_DIR/"
```

严禁让两条构建线共用 buildroot，否则 RPM 和中间产物会互相覆盖。

## 6. 构建 system-libstdc++ 基线

若已有同一提交、同一 spec 版本、同一 `gbs_llvm.conf` repo 快照的正常 RPM，可跳过编译，但必须把来源、SHA-256 和构建日志写入报告。仅“版本号看起来相同”不能当基线。

没有合格基线时，先构建基线。假设机器 ≥64 GiB，示例使用 `JOBS=8`、`MemoryMax=48G`；资源较小时按第 1 节表格调整：

```bash
export JOBS=8
export BASE_UNIT="chromium-baseline-$RUN_ID"

systemd-run --user --unit="$BASE_UNIT" \
  --property=CPUQuota=$((JOBS * 100))% \
  --property=MemoryMax=48G \
  --property=MemorySwapMax=4G \
  --property=IOWeight=50 \
  --property=Nice=5 \
  -- /bin/bash "$RUN_ROOT/analysis/scripts/run_gbs_build.sh" \
    "$BASELINE_SRC" \
    "$RUN_ROOT/gbs_baseline.conf" \
    "$RESULT_DIR/baseline_build" \
    "$JOBS"
```

另开终端执行 GN 参数采集；它会等待 `args.gn` 出现：

```bash
sudo -v
bash "$RUN_ROOT/analysis/scripts/capture_gn_args.sh" \
  "$BASE_GBS_ROOT/local/BUILD-ROOTS/scratch.armv7l.0" \
  "$RESULT_DIR/baseline_gn" \
  21600
```

监控只用轻量命令，每 60 秒最多一次：

```bash
systemctl --user show "$BASE_UNIT.service" \
  -p ActiveState -p SubState -p MemoryCurrent -p MemoryPeak \
  -p CPUUsageNSec -p TasksCurrent -p NRestarts -p Result -p ExecMainStatus
tail -n 5 "$RESULT_DIR/baseline_build/build.log"
```

服务结束后保存最终状态：

```bash
systemctl --user show "$BASE_UNIT.service" \
  -p ActiveState -p SubState -p MemoryPeak -p CPUUsageNSec \
  -p NRestarts -p Result -p ExecMainStatus \
  > "$RESULT_DIR/baseline_build/service_final.txt"
cat "$RESULT_DIR/baseline_build/exit_code.txt"
```

只有 `exit_code=0` 才继续。立即快照 RPM，防止后续覆盖：

```bash
mkdir -p "$RUN_ROOT/artifacts/baseline_rpms"
cp -a "$BASE_GBS_ROOT/local/repos/tizen_unified_standard/armv7l/RPMS/"chromium-efl*.armv7l.rpm \
  "$RUN_ROOT/artifacts/baseline_rpms/"
sha256sum "$RUN_ROOT/artifacts/baseline_rpms/"*.rpm \
  > "$RESULT_DIR/baseline_rpm_sha256.txt"
```

检查基线 GN 关键值，应为：

```text
is_clang = true
use_custom_libcxx = false
use_custom_libcxx_for_host = false
use_lld = true
use_thin_lto = true
enable_rust = false
```

## 7. 构建 bundled libc++ 候选

候选必须使用独立 GBS root：

```bash
export CAND_UNIT="chromium-libcxx-$RUN_ID"

systemd-run --user --unit="$CAND_UNIT" \
  --property=CPUQuota=$((JOBS * 100))% \
  --property=MemoryMax=48G \
  --property=MemorySwapMax=4G \
  --property=IOWeight=50 \
  --property=Nice=5 \
  -- /bin/bash "$RUN_ROOT/analysis/scripts/run_gbs_build.sh" \
    "$CANDIDATE_SRC" \
    "$RUN_ROOT/gbs_libcxx.conf" \
    "$RESULT_DIR/candidate_build" \
    "$JOBS"
```

另开终端采集 GN 参数：

```bash
sudo -v
bash "$RUN_ROOT/analysis/scripts/capture_gn_args.sh" \
  "$CAND_GBS_ROOT/local/BUILD-ROOTS/scratch.armv7l.0" \
  "$RESULT_DIR/candidate_gn" \
  21600
```

关键值必须是：

```text
is_clang = true
use_custom_libcxx = true
use_custom_libcxx_for_host = true
use_lld = true
use_thin_lto = true
use_system_icu = false
enable_rust = false
```

少一项或值不对，停止构建并报告 GN 参数未生效。

服务结束后保存状态：

```bash
systemctl --user show "$CAND_UNIT.service" \
  -p ActiveState -p SubState -p MemoryPeak -p CPUUsageNSec \
  -p NRestarts -p Result -p ExecMainStatus \
  > "$RESULT_DIR/candidate_build/service_final.txt"
cat "$RESULT_DIR/candidate_build/exit_code.txt"
```

### 7.1 构建失败时

不要修代码。完整 `candidate_build/build.log` 已是首错保真证据，必须保留 include 栈和链接器上下文。再执行：

```bash
rg -n 'FAILED:|(^|[[:space:]])error:|undefined symbol:|ld\.lld: error:|collect2: error:' \
  "$RESULT_DIR/candidate_build/build.log" \
  > "$RESULT_DIR/candidate_build/error_index.txt" || true

sed -n '1,120p' "$RESULT_DIR/candidate_build/error_index.txt"
```

人工从第一个 `FAILED:` 动作前 5 行开始，复制到该动作完整诊断结束，写入 `first_error_full.txt`。不能只复制最后一行。

分类规则：

- A：libc++ 自身编译错误。
- B：downstream/system libstdc++ 硬依赖或 `std::__cxx11`/`std::__Cr` 不匹配。
- C：链接错误，涉及 llvm-libc、libc++abi、unwind。
- D：第三方头冲突。
- E：环境、工具或其他。

在报告中给每类计数和一个样例。修复配额已为 `5/5`，所以失败后必须停止并推送报告，不得第 6 次修改。

### 7.2 构建成功时

若一次通过，明确写：`未复现新的 libc++ 阻塞；46061f7 规避的问题已由当前补丁集合收敛。`

快照候选 RPM：

```bash
mkdir -p "$RUN_ROOT/artifacts/candidate_rpms"
cp -a "$CAND_GBS_ROOT/local/repos/tizen_unified_standard/armv7l/RPMS/"chromium-efl*.armv7l.rpm \
  "$RUN_ROOT/artifacts/candidate_rpms/"
sha256sum "$RUN_ROOT/artifacts/candidate_rpms/"*.rpm \
  > "$RESULT_DIR/candidate_rpm_sha256.txt"
```

## 8. RPM ELF 门禁、G4 和体积对比

只在候选构建成功后执行：

```bash
bash "$RUN_ROOT/analysis/scripts/analyze_rpms.sh" \
  "$RUN_ROOT/artifacts/candidate_rpms" \
  "$RESULT_DIR/abi_analysis" \
  "$RUN_ROOT/artifacts/baseline_rpms"
```

脚本会串行解包并生成：

- `gate_summary.txt`
- `g1_export_hits.tsv`
- `g2_und_hits.tsv`
- `g3_needed_hits.tsv`
- `bridge_*`
- `g4_full.diff`、`g4_added.tsv`、`g4_removed.tsv`
- `candidate_runtime_abi_symbols.tsv`、`candidate_needed.tsv`
- `candidate_ewk_parse_cookie.tsv`
- `candidate_size_summary.txt`、`baseline_size_summary.txt`
- 全部 dynsym/dynamic 原始输出。

门禁期望：

| 门禁 | 期望 |
|---|---|
| G1 导出 `_ZNSt4__Cr` / `_ZNSt3__1` | 0 |
| G2 UND `_ZNSt4__Cr` / `_ZNSt3__1` | 0 |
| G3 NEEDED libc++ / libc++abi | 0 |
| bridge 非白名单导出 | 0 |
| bridge 白名单缺失 | 0 |
| bridge `_ZNSt*` 导出 | 0 |
| bridge NEEDED libstdc++ | ≥1，预期行为 |

G1/G2/G3 或 bridge 白名单失败时，不做新修复，只报告。

G4 必须使用本次基线 RPM 全量对比 GLOBAL/WEAK 非 UND 动态导出集。`g4_full.diff` 全量保留；对话只报新增/删除计数。

`ewk_parse_cookie` 特别说明：本版本实际是裸 `extern "C"` 名，因此预期看到 `ewk_parse_cookie`，而不是两种 C++ mangling。报告必须注明“原计划阳性对照未形成”，这不单独算门禁失败。

## 9. `__cxa_*` / `Unwind*` 解析结论

查看：

```bash
rg -n '__cxa_|_Unwind|Unwind' "$RESULT_DIR/abi_analysis/candidate_runtime_abi_symbols.tsv"
rg -n 'libgcc_s|libc\+\+|libc\+\+abi' "$RESULT_DIR/abi_analysis/candidate_needed.tsv"
```

按实际输出写结论：

- 没有 NEEDED `libc++abi.so` 且 DSO 内有相应定义，才可写“libc++abi 静态链入”。
- UND `_Unwind*` 且 NEEDED `libgcc_s.so.1`，才可写“unwind 由 libgcc_s 解析”。
- 证据不完整就标 `UNRESOLVED`，不得根据经验补全。

## 10. 报告、纯文本证据和推送

复制模板并填写：

```bash
cp "$RUN_ROOT/analysis/guides/REPORT_TEMPLATE.md" "$RESULT_DIR/report.md"
```

报告必须包含：

1. 可行性结论。
2. 基线/候选构建结果、耗时、峰值内存、RPM 总大小、`libchromium-impl.so` 大小。
3. 实际 GN 参数。
4. A–E 错误分类表。
5. 必要补丁清单，注明小修复配额 `5/5` 和 bridge 不占配额。
6. G1–G4、bridge、`__cxa/Unwind`。
7. `ewk_parse_cookie` 裸 C 符号事实。
8. 所有 `UNRESOLVED` 项和缺失材料。

提交前排除二进制和解包树。`analyze_rpms.sh` 生成的
`candidate_rpm_extract/`、`baseline_rpm_extract/` 是门禁临时工作树，仓库的
`.gitignore` 会忽略它们；不要强制添加：

```bash
cd "$RUN_ROOT/analysis"
find "runs/$RUN_ID" -type f -size +95M -print
```

第一个命令必须无输出；若有大日志，停止并把文件名、字节数写入报告，不得尝试提交。然后只按正常忽略规则暂存，并检查实际暂存清单：

```bash
git status --short
git add "runs/$RUN_ID"
if git diff --cached --name-only | rg '/(candidate|baseline)_rpm_extract/|\.(rpm|src\.rpm|so(\..*)?|a|o|tar(\..*)?|zip)$'; then
  echo 'ERROR: staged binary or RPM extraction tree' >&2
  exit 1
fi
git diff --cached --check
git commit -m "Add remote bundled libc++ run $RUN_ID"
git push -u origin "results/$RUN_ID"
```

最终只向用户回复：分支名、commit、构建成功/失败、A–E 计数、G1–G4 计数、bridge 结果、体积/耗时差异和 `report.md` 路径。

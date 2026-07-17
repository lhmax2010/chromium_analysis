# 检查点 0：病历结论与构建前预判

## 阶段状态

- 未翻转 `use_custom_libcxx`，未执行 GN/GBS 构建，源码修改数 0。
- 活跃隔离 worktree：`chromium-efl-spike-libcxx-wt`，branch `spike/libcxx-m144`，HEAD `394713cfd95e9597793255ec71496aef6ef84574`，`git status --short` 无输出。
- 当前为 checkpoint-0 所需路径的 sparse checkout；收到确认后、构建前再扩展完整工作树。

## 病历结论

1. `46061f7` 不是只改 `c++.gni`：共修改 188 文件（+510/-347）。完整 diff、逐文件 numstat 和逐文件 clue tags 已分别落到 `46061f7_full.diff`、`46061f7_file_inventory.tsv`、`46061f7_clue_inventory.tsv`。
2. 该 commit 的主病历是 “Rust disabled” 的 M138 standard-profile 稳定化：16 个文件保护 Rust/CXX bridge，另有 121 个 Tizen guards、26 个 `EWK_BRINGUP` 屏蔽，以及 WRT JS/multimedia/TBM 的关闭。
3. 与标准库直接相关的改动只有 `build/config/c++/c++.gni` 两行 `true -> !is_tizen`。完整 diff 中没有保留 libc++ 编译错误、失败符号、libc++abi/unwind 修复或 libstdc++ 私有 API 修复。因此可确认它是 blanket workaround，但不能仅凭 commit 还原当年的首个 libc++ 诊断。
4. 当前 M144 `third_party/llvm-libc/` 物料存在（6,124 文件）。`llvm-libc-shared` label 存在，但它是只传播 include path 和 `LIBC_NAMESPACE=__llvm_libc_cr` 的 `group`，不产出库文件。
5. libc++ 对 `llvm-libc-shared` 的依赖无条件存在，仓内没有 `use_llvm_libc` 类 arg；该 target 也没有 `enable_rust/toolchain_has_rust` 分支。libc++ `from_chars` 所需的三个 shared headers 全部存在。

## 失败点预判（尚非实测错误）

按首次新增构建路径排序：

1. **A 候选（最早可能出现）**：`//buildtools/third_party/libc++:libc++` 自身编译。代表路径是 `charconv.cpp -> from_chars_floating_point.h -> third_party/llvm-libc/src/shared/*.h`。物料已齐，因此不是“目录/头缺失”的确定失败，只是翻转后最早新增的编译边。
2. **C 候选（A 通过后）**：libc++ 静态拉入 libc++abi，再由系统工具链提供 unwind。当前 Tizen `use_custom_libunwind=false`（`build/config/unwind.gni:3-6`），所以预期不会构建仓内 libunwind；若出错，应集中在 `__cxa_*`/`Unwind*`/`libgcc_s` 解析，而不是 `llvm-libc-shared` 链接（它没有库产物）。
3. **B/D 候选**：downstream 对 libstdc++ 私有实现的硬依赖、或系统头与 libc++ wrapper 冲突，只能由实际编译诊断确认；`46061f7` 没有给出可提前点名的文件。
4. **Rust 不是本轮预判首错**：spec 继续传 `enable_rust=false`；`llvm-libc-shared` 无 Rust 条件，翻转 libc++ 不会自行打开 Rust。

## A–E 当前实测计数

```text
A=0  B=0  C=0  D=0  E=0
```

原因：按任务要求在检查点 0 前不构建。收到确认后进入第 1 步并产生第一轮实测分类。

## 后续最小翻转建议

建议不 revert 整个 `46061f7`，也不改全局默认的 `c++.gni`；在隔离 worktree 的 `packaging/chromium-efl.spec` 调用 `gn_chromiumefl.sh` 时显式增加：

```text
use_custom_libcxx=true
use_custom_libcxx_for_host=true
```

理由：wrapper 把全部位置参数保存为 `EXTRA_GN_ARGS` 并原样并入 GN `--args`（`tizen_src/build/gn_chromiumefl.sh:51,365-374`），所以这两行只影响当前 GBS spec build；它保持 188 文件中的 Rust-off/Tizen bringup 修复及其他调用路径不变，回退成本也低于改全局默认值。第 1 步收到确认后才实施该两行修改。

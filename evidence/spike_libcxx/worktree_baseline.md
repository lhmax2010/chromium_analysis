# Spike worktree baseline

- Main checkout: `/home/linhao/Toolchain/plan_evaluation/chromium-efl`, branch `tizen`, HEAD `394713cfd95e9597793255ec71496aef6ef84574`; initial `git status --short` had no entries.
- Spike branch: `spike/libcxx-m144`, created from the same HEAD.
- Active isolated worktree: `/home/linhao/Toolchain/plan_evaluation/chromium-efl-spike-libcxx-wt`, clean branch `spike/libcxx-m144`, same HEAD.
- To avoid another 845k-file full-checkout stall before checkpoint 0, the active worktree is initially sparse with `build/`, `buildtools/`, `packaging/`, `third_party/llvm-libc/`, and `tizen_src/build/`. It will be expanded only after checkpoint 0 confirmation and before the GBS build.
- The first attempted path `/home/linhao/Toolchain/plan_evaluation/chromium-efl-spike-libcxx` became orphaned while its worker was stuck in kernel I/O wait; it is not registered as a Git worktree and is not used for investigation or builds. No source edits or build actions were performed there.

## Step 1 transition

- After checkpoint 0 confirmation, `git sparse-checkout disable` completed successfully and populated the full source tree before any edit/build.
- The only source change is the two-line GN-arg injection in `packaging/chromium-efl.spec`; raw diff: `spec_injection.diff`.
- `git diff --check` passed; `git diff --stat` reports `1 file changed, 2 insertions(+)`.

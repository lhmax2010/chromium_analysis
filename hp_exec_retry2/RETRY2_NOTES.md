# Stage 4 Retry 2 修正说明

Retry 1 在 `libnode.so` 已完成后，于最终 `libchromium-impl.so` 链接暴露 20 条
`node::*` 未定义符号并触发 lld error limit。根因是 Retry 1 生成的
`node.filter` 仅导出 7 个 `__Cr` 精确符号并以 `local: *;` 隐藏全部其余
Node C++ ABI，连基线中不携带 STL 的稳定符号也被删除。

Retry 2 从固定 `baseline_exports.tsv` 机械生成 354 条可 demangle、完整签名不含
`std::` 的 libnode C++ 精确导出；它们与既有 7 条内部 `__Cr` 白名单共同生成
Node filter。22 条 STL-carrying 基线导出和 2 条 demangle unknown 不会恢复。

执行包固定从 Gerrit `sandbox/lhmax2025/toolchain` 的
`65e8e6d9a338b0ac64521fb04923f234924ecb70` 开始。高性能 PC 的脚本负责提交
三文件源码修正、构建、验收、打包，并将源码修正和结果目录以 fast-forward
推送回同一分支。任何远端 HEAD 漂移都会在写入前机械停止。

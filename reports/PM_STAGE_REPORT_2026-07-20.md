# Chromium EFL bundled libc++ Spike 阶段汇报

日期：2026-07-20

## 一句话结论

bundled libc++ 构建可行性已经证明：基线和候选均成功产出 RPM，未遇到新的
libc++ 编译或链接阻塞；但 ABI 隔离验收尚未完成，因此当前状态是
“构建阶段完成、生产导入待 ABI 收口”，不是正式放行。

## 已完成

- 固定同一 Chromium 基线和两份独立源码完成对照构建。
- system-libstdc++ 基线与 bundled libc++ 候选均构建成功，exit code 为 0。
- 候选确认启用仓内 libc++、libc++ for host、LLD 和 ThinLTO。
- 候选 DSO 没有动态依赖 `libc++.so` 或 `libc++abi.so`。
- GCC 构建的 C ABI bridge 已进入 RPM，导出集合与 92 项白名单实际一致，
  无 C++ mangled export，并按预期依赖 `libstdc++.so.6`。
- `ewk_parse_cookie` 保持裸 C 符号，没有发生预期之外的 C++ mangling。
- 候选 `libchromium-impl.so` 比基线增加约 1.0 MiB（约 0.9%）。
- 候选完整构建耗时 3:14:22，基线 3:23:40；本次数据未显示构建时间退化。

## 当前风险

旧门禁只检查“符号名以 std namespace 开头”，覆盖范围不足。全局导出 diff 显示：

- 候选新增导出 620 个。
- 其中 488 个导出签名内部携带 `std::__Cr`。
- 这 488 个中，`libv8.so` 占 464 个，`libnode.so` 占 24 个。

这些符号可能只是 Chromium RPM 内部、同一 libc++ 域内的依赖，也可能形成对外
C++ ABI 暴露。现有证据还没有覆盖完整 UND 消费者和平台外部消费者，不能直接判定
安全或失败。

## 已识别的报告修正

- 原报告中的 bridge “2 个非白名单导出”是排序 locale 导致的假阳性。对 actual
  和 whitelist 同时执行 `LC_ALL=C sort -u` 后，92/92 完全一致，unexpected=0、
  missing=0。
- 候选约 41.5 GB link peak 缺少原始输出锚点。现存 GNU time 证据记录的候选最大
  进程 RSS 是 17,480,900 kB；两者口径不同，不能混用。
- 基线 RPM 总大小的逐包 bytes 没有随报告提交，需要从服务器现存 RPM 重新
  `stat`。
- “libc++abi 已静态进入 libchromium-impl.so”目前只有 archive 生成和无动态
  NEEDED 的间接证据，仍需要最终 link command、link map 或完整符号表。

## PM 状态建议

状态：AMBER

- 可以确认技术路线能够构建，不需要启动新的编译 spike。
- 暂不建议宣告 libc++ ABI 隔离验收通过，也不建议直接进入量产切换。
- 剩余工作是一次基于现有 RPM/构建目录的只读后处理，不需要重新编译。

## 下一检查点

高性能服务器完成以下一次性补采后给出最终技术状态：

1. 扫描符号任意位置的 `NSt4__Cr|NSt3__1`，建立 export/UND 依赖边。
2. 区分 RPM 内部闭环、未匹配导出和集合外消费者风险。
3. 补齐 RPM bytes、内存口径和 libc++abi 解析证据。
4. 生成 `report.corrected.md`，最终状态只能是
   `BUILD_SUCCESS_ABI_ACCEPTED`、`BUILD_SUCCESS_ABI_RISK` 或
   `BUILD_SUCCESS_ABI_UNRESOLVED`。

在该检查点完成前，对外表述统一为：

> bundled libc++ 候选已构建成功，未发现新的工具链阻塞；ABI 隔离正在做最后的
> 消费者边界核验，尚未进入正式放行状态。

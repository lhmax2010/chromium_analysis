# Chromium EFL bundled libc++ Spike 阶段汇报

日期：2026-07-20

## 一句话结论

bundled libc++ 构建可行性已经证明：基线和候选均成功产出 RPM，未遇到新的
libc++ 编译或链接阻塞；构建后审计最终状态为
`BUILD_SUCCESS_ABI_UNRESOLVED`。当前可以结束构建 spike，但不能据此批准生产
切换，后续重点是确认平台外部 ABI 消费者范围。

## 已完成

- 固定同一 Chromium 基线和两份独立源码完成对照构建。
- system-libstdc++ 基线与 bundled libc++ 候选均构建成功，exit code 为 0。
- 候选确认启用仓内 libc++、libc++ for host、LLD 和 ThinLTO。
- 候选 DSO 没有动态依赖 `libc++.so` 或 `libc++abi.so`。
- GCC 构建的 C ABI bridge 已进入 RPM，导出集合与 92 项白名单实际一致，
  无 C++ mangled export，并按预期依赖 `libstdc++.so.6`。
- `ewk_parse_cookie` 保持裸 C 符号，没有发生预期之外的 C++ mangling。
- 候选 8 个 RPM 合计 534,832,144 bytes，基线为 516,543,236 bytes，增加
  18,288,908 bytes（约 3.54%）。
- 候选完整构建耗时 3:14:22，基线 3:23:40；本次数据未显示构建时间退化。
- GNU time 最大进程 RSS：候选 17,480,900 KB，基线 16,581,724 KB，增加
  899,176 KB（约 5.42%）。

## 当前风险

旧门禁只检查“符号名以 std namespace 开头”，覆盖范围不足。全局导出 diff 显示：

- 候选新增导出 620 个。
- 其中 488 个导出签名内部携带 `std::__Cr`。
- 这 488 个中，`libv8.so` 占 464 个，`libnode.so` 占 24 个。

进一步的 expanded ABI 扫描得到 43 个 UND 和 41 条 RPM 集合内解析边，但仍有
454 个导出没有集合内消费者（libv8.so=437、libnode.so=17）。这些符号可能没有
外部使用，也可能形成对外 C++ ABI 暴露；由于本次没有完整 Tizen rootfs，不能
排除平台外部消费者。

## 已识别的报告修正

- 原报告中的 bridge “2 个非白名单导出”是排序 locale 导致的假阳性。对 actual
  和 whitelist 同时执行 `LC_ALL=C sort -u` 后，92/92 完全一致，unexpected=0、
  missing=0。
- 候选约 41.5 GB link peak 缺少原始输出锚点。现存 GNU time 证据记录的候选最大
  进程 RSS 是 17,480,900 kB；两者口径不同，不能混用。
- G4 原始 added 集合是 620 条：488 条 `LIBCXX_CR`、1 条 ICU、131 条 OTHER。
  Gerrit commit `2f995770ab57` 的修正分类误漏原始第一行，因此报告中的
  619/487/0/131 不是正确最终数字。
- Gerrit 报告把 baseline RPM 总量少写了 100,000 bytes；正确总量及增量是
  516,543,236、534,832,144、+18,288,908（约 +3.54%）。
- “libc++abi 已静态进入 libchromium-impl.so”目前只有 archive 生成和无动态
  NEEDED 的间接证据，仍需要最终 link command、link map 或完整符号表。
- 2 个包含 `std::__Cr` 的 Node 模板符号无法由现有 GNU `c++filt` 解码，已单列
  unknown，未静默丢弃。

## PM 状态建议

状态：AMBER / `BUILD_SUCCESS_ABI_UNRESOLVED`

- 可以确认技术路线能够构建，不需要启动新的编译 spike。
- 暂不建议宣告 libc++ ABI 隔离验收通过，也不建议直接进入量产切换。
- 当前无需再做 Chromium 编译。Gerrit 报告尚需一次纯文档/统计修正；该修正不改变
  技术状态。

## 后续工作

1. 先按 `prompts/REMOTE_AI_POSTBUILD_REPORT_CORRECTION_V2_PROMPT.md` 修正 Gerrit
   报告数字；无需重编译。
2. 使用完整 Tizen rootfs/RPM 集合，对 454 个 unmatched exports 做平台范围的
   provider/consumer ABI 图扫描。
3. 如果正式门禁必须证明 libc++abi 静态归属，保留最终链接 rsp/link map 或未剥离
   符号证据；现有 stripped RPM 无法完成该证明。
4. 决定 Node/V8 的 `std::__Cr` 导出是需要隐藏、白名单豁免，还是要求所有消费者
   同步进入同一 bundled libc++ ABI 域。

对外表述建议统一为：

> bundled libc++ 候选已经成功构建，未发现新的工具链阻塞；C bridge 隔离门禁
> 通过，但 Node/V8 仍存在 488 个携带 `std::__Cr` 的导出，其中 454 个尚未在
> Chromium RPM 集合内找到消费者。构建 spike 可以结束，生产切换需等待平台范围
> ABI 消费者核验和 libc++abi 证据收口。

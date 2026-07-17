# 46061f7 病历调查

## 原始材料

- 完整 `git show --format=fuller --stat --patch 46061f7...`：`46061f7_full.diff`（3,812 行，164,014 bytes）。
- 逐文件 numstat：`46061f7_file_inventory.tsv`（188 行）。
- 逐文件线索分类：`46061f7_clue_inventory.tsv`（188 行；列为 additions、deletions、path、clue tags）。该表逐个记录 commit 修改的全部文件，没有只抽取 `c++.gni`。

```text
$ git show --stat --oneline 46061f7673c2224dc87777ae239247c30572027b
46061f7673c2 [M138] Fix build errors for tizen standard profile
188 files changed, 510 insertions(+), 347 deletions(-)
```

commit message 的正文只有：

```text
Fix standard profile build errors with rust disabled.
```

## 逐文件线索分类计数

分类来自每个 diff section 的新增/删除行；多标签文件会进入多个计数。

```text
121 TIZEN_GUARD
 26 BRINGUP_STUB
 25 UPSTREAM_API_PORT
 16 RUST_OFF
  6 BUILD_GRAPH_PORT
  1 LIBCXX_DEFAULT
```

完整 188 文件明细见 `46061f7_clue_inventory.tsv`。其中直接关系 Rust 关闭路径的 16 个文件是 `base/BUILD.gn`、`base/json/json_reader.cc`、`base/logging.cc`、`base/test/BUILD.gn`、`build/config/rust.gni`、`build/rust/rust_target.gni`、`chrome/browser/webauthn/BUILD.gn`、`skia/BUILD.gn`、`skia/ext/font_utils.cc`、`skia/skia.gni`、`third_party/blink/common/BUILD.gn`、`third_party/blink/common/chrome_debug_urls.cc`、`third_party/blink/renderer/platform/fonts/skia/sktypeface_factory.cc`、`third_party/blink/renderer/platform/image-decoders/BUILD.gn`、`third_party/breakpad/BUILD.gn`、`tizen_src/build/config/BUILD.gn`。

## 与 bundled libc++ 直接相关的改动

对完整 diff 搜索 `libstdc|libc++|_GLIBCXX|__gnu|std::__cxx|__Cr|nostdlib|use_custom_libcxx|llvm-libc|libcxxabi|unwind`，唯一实质命中是 `build/config/c++/c++.gni` 的两个默认值：

```diff
-  use_custom_libcxx = true
+  use_custom_libcxx = !is_tizen
-  use_custom_libcxx_for_host = true
+  use_custom_libcxx_for_host = !is_tizen
```

没有编译器诊断、失败符号、libc++ 源码修复、libc++abi/unwind 修复或 `_GLIBCXX` 硬依赖改动被记录在该 commit 中。因此该 commit 能证明“当时通过整体关闭 bundled libc++ 绕过问题”，但不能从 diff 单独还原具体的 libc++ 首错。

## 同一 commit 的其他直接线索

- `build/config/rust.gni` 同时把 `enable_rust` 与 `enable_chromium_prelude` 改成 `build_with_chromium && !is_tizen`；16 个文件增加 Rust/CXX bridge 关闭保护。这与 commit message 一致，是主要病历主题。
- `packaging/chromium-efl.spec` 除版本升级外把 `__enable_wrt_js` 从 1 改为 0。
- `tizen_src/build/gn_chromiumefl.sh` 把 `tizen_multimedia` 与 `tizen_tbm_support` 从 true 改为 false。
- 26 个文件增加 `EWK_BRINGUP` 临时屏蔽；121 个文件增加或修正 Tizen platform guards；其余多为 M130→M138 API/BUILD graph 迁移。

这说明 `46061f7` 是一次广泛的 M138 standard-profile 稳定化提交，不是一个只针对 C++ 标准库的单点修复。当前 spike 只翻转两个 libc++ 默认值、继续保持 Rust/WRT/multimedia 等现状，才能隔离重现被该 blanket workaround 掩盖的 libc++ 问题。


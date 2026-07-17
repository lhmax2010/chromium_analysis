# 补丁清单

- 基线提交：`394713cfd95e9597793255ec71496aef6ef84574`
- 补丁文件：`bundled_libcxx_spike.patch`
- 字节数：`7093`
- SHA-256：`388985d2f1feb6e2ed5852240557b675634e849546eca2fc6296aa97199b32f2`
- diff section：8
- 当前修改工作树反向 `git apply --check`：PASS

包含路径：

1. `build/config/c++/BUILD.gn`
2. `packaging/chromium-efl.spec`
3. `tizen_src/build/gn_chromiumefl.sh`
4. `tizen_src/ewk/chromium-ewk.filter`
5. `wrt/BUILD.gn`
6. `wrt/cxx_wrapper/BUILD.gn`
7. `wrt/cxx_wrapper/build.sh`（新增）
8. `wrt/cxx_wrapper/wrt-c++wrapper.map`（新增）

`bundled_libcxx_spike.stat.txt` 只统计 6 个已跟踪文件；两个新增文件由 patch 的 `/dev/null` sections 完整携带。

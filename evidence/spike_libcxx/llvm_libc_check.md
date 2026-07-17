# third_party/llvm-libc 物料与依赖核查

检查位置：独立 worktree `/home/linhao/Toolchain/plan_evaluation/chromium-efl-spike-libcxx-wt`，HEAD `394713cfd95e9597793255ec71496aef6ef84574`。

## 目录物料

```text
$ test -d third_party/llvm-libc && printf 'directory=present\n'
directory=present
$ find third_party/llvm-libc -type f | wc -l
6124
$ find third_party/llvm-libc -type d | wc -l
400
$ find third_party/llvm-libc -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
BUILD.gn
OWNERS
README.chromium
README.md
src
```

libc++ `from_chars` 当前直接使用的三份 shared headers 均存在：

```text
$ for f in shared/fp_bits.h shared/str_to_float.h shared/str_to_integer.h; do test -f "third_party/llvm-libc/src/$f" && printf '%s\tpresent\n' "$f"; done
shared/fp_bits.h	present
shared/str_to_float.h	present
shared/str_to_integer.h	present
```

消费证据：`third_party/libc++/src/src/include/from_chars_floating_point.h:12-15` 包含上述三个 header，`:202-203` 起使用 `LIBC_NAMESPACE::shared::*`。

## llvm-libc-shared target 原文

```text
$ nl -ba third_party/llvm-libc/BUILD.gn
     1  # Copyright 2024 The Chromium Authors
     2  # Use of this source code is governed by a BSD-style license that can be
     3  # found in the LICENSE file.
     4
     5  config("config") {
     6    visibility = [ ":*" ]
     7    include_dirs = [ "src" ]
     8    defines = [ "LIBC_NAMESPACE=__llvm_libc_cr" ]
     9  }
    10
    11  group("llvm-libc-shared") {
    12    # llvm-libc is only used as a dependency of libc++.
    13    visibility = [ "//buildtools/third_party/libc++" ]
    14
    15    public_configs = [ ":config" ]
    16  }
```

核查结论有两层：

- GN label 是完整可解析的：target、visibility 和 public config 都存在，且源码/所需 shared headers 在 tarball 内。
- 它不是一个会产出 `.a/.so` 的 library target，而是仅传播 `third_party/llvm-libc/src` include path 与 `LIBC_NAMESPACE=__llvm_libc_cr` 的 interface `group`。所以本 spike 不应预期出现名为 llvm-libc 的链接输入；相关首错若发生，更可能是 libc++ 编译这些 shared headers 时的 A/D 类错误。

## Rust 条件与可绕过开关

```text
$ rg -n 'enable_rust|toolchain_has_rust' third_party/llvm-libc/BUILD.gn
[no output]
rust_condition_rg_exit=1

$ rg -n 'use_llvm_libc|use_llvm-libc|enable_llvm_libc|enable_llvm-libc' build buildtools third_party/llvm-libc tizen_src/build -g '*.gn' -g '*.gni' -g '*.sh'
[no output]
rg_exit=1
```

因此 `llvm-libc-shared` 不受 `enable_rust=false` 或 `toolchain_has_rust=false` 影响，也没有 `use_llvm_libc` 类 GN arg。

## libc++ 依赖是否可条件绕过

```text
$ nl -ba buildtools/third_party/libc++/BUILD.gn | sed -n '604,625p'
   604    # Enable exceptions and rtti for libc++, but disable them in modules targets
   605    # so that modules can be used for other chromium targets which don't enable
   606    # exception and rtti.
   607    configs -= configs_to_remove + [
   608                 "//build/config/compiler:no_exceptions",
   609                 "//build/config/compiler:no_rtti",
   610               ]
   611    configs += configs_to_add + [
   612                 "//build/config/compiler:exceptions",
   613                 "//build/config/compiler:rtti",
   614               ]
   615
   616    deps = [
   617      ":custom_headers",
   618      ":libcxx_headers",
   619      "//third_party/llvm-libc:llvm-libc-shared",
   620    ]
   621
   622    if (use_clang_modules) {
   623      # TODO(https://github.com/llvm/llvm-project/issues/127012): We don't enable
   624      # Clang modules for libc++ as libc++'s iostream.cpp has ODR issue
   625      # (https://crbug.com/40440396#comment81). Also we don't take care about the
```

该依赖是无条件 deps，没有现成开关可绕过。若后续构建证明必须断开它，属于用户定义的结构性改动，必须先停下报告方案；检查点 0 不修改它。

补充：Tizen 的 `is_linux=false`，不在 `clang_modules_platform_supported` 列表内（`build/config/clang/clang.gni:42-47`），因此这里预计不会先进入 libc++ Clang modules 分支。


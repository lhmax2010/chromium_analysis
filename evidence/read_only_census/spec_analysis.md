# chromium-efl.spec toolchain / GN evidence

Scope: `chromium-efl/packaging/chromium-efl.spec` (the only `packaging/*.spec`).

## Extraction commands

```text
rg -n '^BuildRequires:' chromium-efl/packaging/chromium-efl.spec
awk 'BEGIN{p=0} /^%build([[:space:]]|$)/{p=1} p{printf "%6d\t%s\n", NR, $0} p && /^%(install|check|clean)([[:space:]]|$)/{exit}' chromium-efl/packaging/chromium-efl.spec
rg -n -i -C 2 'clang|llvm|lld|libc\+\+|stdlib|is_clang|use_custom_libcxx|toolchain|gcc|gn ' chromium-efl/packaging/chromium-efl.spec
```

## BuildRequires: toolchain/build-tool entries

Raw relevant lines:

```text
145:%ifnarch riscv64
146:BuildRequires: binutils-gold
147:%endif
148:BuildRequires: at-spi2-atk-devel, bison, edje-tools, expat-devel, flex, gettext, gperf, libatk-bridge-2_0-0, libcap-devel, libcurl
149:BuildRequires: libjpeg-turbo-devel, ninja, perl, python3, python3-xml, which
150:%if 0%{?__enable_platform_api_wrapper}
151:BuildRequires: cmake
152:%endif
251:%ifarch armv7l
252:BuildRequires: python-accel-armv7l-cross-arm
253:%endif
254:%ifarch armv7hl
255:BuildRequires: python-accel-armv7hl-cross-arm
256:%endif
257:%ifarch aarch64
258:BuildRequires: python-accel-aarch64-cross-aarch64
259:%endif
260:%ifarch riscv64
261:BuildRequires: python-accel-riscv64-cross-riscv64
262:%endif
```

Findings:

- Direct compiler/linker requirement: `binutils-gold`, except on `riscv64` (`145–147`).
- Build generators/helpers: `bison`, `flex`, `gperf`, `ninja`, `perl`, `python3`, `python3-xml`, `which` (`148–149`).
- `cmake` is required only when `__enable_platform_api_wrapper != 0` (`150–152`); that wrapper defaults disabled (`110–113`) and, if enabled, is explicitly built separately with GCC (`630–633`).
- Python accelerator package is selected per target architecture (`251–262`).
- There is no `BuildRequires` whose package name contains `gcc`, `g++`, `clang`, `llvm`, `libc++`, or `libstdc++`. Compiler availability therefore comes from the GBS project/rootstrap and/or checked-in buildtools, not an explicit spec dependency.

## clang/LLVM condition macro resolution

Raw relevant lines:

```text
344:%{!?_clang: %define _clang 1}
352:%if "%{?_clang}" == "1"
353:%define __use_clang 1
354:%else
355:%define __use_clang 0
356:%endif
714:%if %{__use_clang} == 1
715:  "is_clang=true" \
716:%else
717:  "is_clang=false" \
718:%endif
```

Static expansion:

- Neither workspace GBS config defines `_clang`; the spec default is `_clang=1`, hence `__use_clang=1` and the GN argument is `is_clang=true`.
- An external RPM macro override `_clang=0` selects the `%else` branch and sends `is_clang=false`; this override is possible but is not present in either checked configuration.
- No spec condition directly names `llvm`, `lld`, `libc++`, `use_custom_libcxx`, `clang_base_path`, or `clang_use_chrome_plugins`.
- The wrapper receives `is_clang=true` and then adds Clang host/snapshot toolchains, `use_lld=true`, and `use_thin_lto=true` (`tizen_src/build/gn_chromiumefl.sh:227–232`).

## GN arguments from `%build`

The call is `./tizen_src/build/gn_chromiumefl.sh` at spec lines `663–764`. `%define macro_to_bool()` at line 659 maps a numeric RPM macro to literal GN `true`/`false`.

### Always emitted on the default spec path

```text
is_tizen=true
lib_ro_root_dir="%{CHROMIUM_LIB_DIR}"
app_ro_root_dir="%{TZ_SYS_RO_APP}/%{_pkgid}"
app_rw_root_dir="%{TZ_SYS_RW_APP}/%{_pkgid}"
package_id="%{_pkgid}"
tizen_version=%{tizen_version}
tizen_version_major=%{tizen_version_major}
tizen_version_minor=%{tizen_version_minor}
tizen_version_patch=%{tizen_version_patch}
exclude_unwind_tables=%{macro_to_bool __tizen_release_build}
enable_mlgo=%{macro_to_bool _enable_mlgo}
is_clang=true
tizen_release_build=%{macro_to_bool __tizen_release_build}
build_chrome=true
tizen_video_assistant=true
enable_rust=false
enable_ewk_interface=true
ozone_auto_platforms=false
enable_wrt_js=true
enable_process_group=%{macro_to_bool __enable_process_group}
tizen_atmos_decoder_enable=%{macro_to_bool _tizen_atmos_decoder_enable}
enable_platform_api_wrapper=false
disable_node_v8_component=%{macro_to_bool __disable_node_v8_component}
enable_toolkit_views=%{macro_to_bool _enable_toolkit_views}
```

Default values used above are anchored as follows: `__build_chrome=1` (`49–52`), `__enable_rust=0` unless `_enable_rust` overrides it (`67–70`), `__enable_platform_api_wrapper=0` unless enabled (`110–113`), `_clang=1` unless overridden (`344–356`), `__enable_wrt_js=1` unless `_disable_wrt_js` is set (`358–361`), and `__enable_ewk_interface=1` (`403`). `__tizen_release_build`, `__enable_process_group`, `_tizen_atmos_decoder_enable`, `__disable_node_v8_component`, `_enable_mlgo`, and `_enable_toolkit_views` depend on profile/architecture/external build macros, so their final booleans cannot be expanded from the two GBS config files alone.

The spec does not pass `use_custom_libcxx`. Its GN default is `use_custom_libcxx = !is_tizen` (`build/config/c++/c++.gni:10–18`), so the emitted `is_tizen=true` resolves it to `false` for the target toolchain.

### `%if` / architecture branches

| Condition | GN arguments emitted by that branch |
|---|---|
| `profile == tv` (`668–671`) | `lib_upgrade_root_dir`, `app_upgrade_root_dir` |
| `armv7hl` (`677–679`) | `arm_float_abi="hard"` |
| `_remove_webcore_debug_symbols` is defined (`0%{?...:1}`, `680–682`) | `remove_webcore_debug_symbols=true`; absent by default |
| `_with_wayland == 1` (`685–687`) | `use_wayland=true` |
| repository is `emulator` or `emulator32-x11` (`688–690`) | `tizen_emulator_support=true` |
| Tizen profile is TV (`691–703`) | `tizen_product_tv=true`; if next-browser is enabled, also its product flags, API key and versions |
| `__tizen_product_da` (`704–706`) | `tizen_product_da=true` |
| qualifying TV product (`707–710`) | `tizen_vd_accessory=true`, `tizen_vd_webhid=true` |
| `component_build` (`711–713`) | `component="shared_library"` |
| `__use_clang == 1` / else (`714–718`) | `is_clang=true` / `is_clang=false`; default branch is true |
| `__use_system_icu == 1` / else (`719–723`) | `use_system_icu=true` / `false` |
| `__build_chrome || next-browser` / else (`725–730`) | `build_chrome=true` plus `tizen_video_assistant=true` / `build_chrome=false`; default branch is true |
| profile is TV (`732–734`) | `lib_dir_path="%{_libdir}"` |
| `_ttrace == 1` (`735–737`) | `use_ttrace=true` |
| `__enable_ewk_interface` (`738–740`) | `enable_ewk_interface=true`; default is enabled |
| `__enable_wrt_js` (`745–748`) | xwalk extension paths; default is enabled |
| `__enable_network_camera` (`749–751`) | `enable_network_camera=true` |
| `__enable_gamepad_latency_test` (`752–754`) | `enable_gamepad_latency_test=true` |
| 64-bit DRM MAPI + TV + Tizen >= 8 (`755–757`) | `drm_mapi_aarch_64=true` |
| `_vd_cfg_licensing == y` (`758–760`) | `tizen_license_tv=true` |

### Wrapper-added compiler arguments

The wrapper parses the spec's `is_clang=true` at `tizen_src/build/gn_chromiumefl.sh:84–86`. On the Tizen Clang branch it adds:

```text
host_toolchain="//tizen_src/build/toolchain/tizen:tizen_clang_$host_arch"
v8_snapshot_toolchain="//tizen_src/build/toolchain/tizen:tizen_clang_$host_arch"
use_lld=true
use_thin_lto=true
```

The `%else` branch uses `tizen_$host_arch` GCC toolchains and adds `use_system_libjpeg=true` (`tizen_src/build/gn_chromiumefl.sh:227–238`).

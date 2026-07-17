# Checkpoint 1 update: isolated resume and second ABI blocker

## Previous interruption root cause

- The host did not reboot. The build and Codex processes were killed at
  `2026-07-14 23:51:30 +0800` by `systemd-oomd` as members of the same VS Code
  scope.
- The journal explicitly names build PID `434050 (qemu-arm)` and reports that
  the scope peaked at `23.7G` memory and `2.0G` swap before 81 processes were
  killed.
- Raw journal evidence: `host_failure_journal_probe.txt`.

## Mitigation and verification

- Attempt 8 ran as independent user service
  `chromium-libcxx-attempt8.service`, outside the VS Code scope.
- Resource controls: two CPUs (`taskset 0,1`), `ninja -j2`, `MemoryMax=12G`,
  `MemorySwapMax=0`, low CPU/IO weights. The VS Code scope was marked
  `ManagedOOMPreference=omit` for the duration of this spike session.
- The build ran for `1:10:37`, used zero swap, and reached a measured service
  memory peak of `10080251904` bytes (about 9.39 GiB). It ended normally with a
  linker exit code, not OOM.
- Runner: `run_incremental_attempt8.sh`.
- Raw log/time: `incremental_build_attempt8_isolated.log` and
  `incremental_build_attempt8_isolated.time`.

## Build result

- Result: **FAILED at action 194/197**, linking `libchromium-impl.so`.
- Full link command and all diagnostics are preserved in
  `first_error_attempt8_libchromium_full.txt` (82 lines).
- There are 18 undefined-symbol diagnostic groups. All are calls from
  `wrt/cxx_wrapper/wgt_manifest_handlers.cc` into the platform package
  `wgt-manifest-handlers-1.11.1-1.armv7l`.
- Representative missing symbol:
  `wgt::parse::WidgetConfigParser::GetManifestData(std::__Cr::basic_string<...> const&) const`.
- The installed platform library exports the counterpart with
  `std::__cxx11::basic_string`; its `Key()` methods carry `[abi:cxx11]`, and
  `ParseManifest` accepts `std::filesystem::__cxx11::path`.
- Raw comparison: `wgt_manifest_system_abi_probe.txt`.

## Classification and quota

| Class | Count | Evidence summary |
|---|---:|---|
| A: libc++ compile | 0 | none |
| B: downstream/system libstdc++ ABI | 2 failed link actions / 25 undefined diagnostics | mksnapshot: 7 (system jsoncpp/ICU); libchromium-impl: 18 (system wgt-manifest-handlers) |
| C: libc++abi/llvm-libc/unwind | 0 | none |
| D: third-party header conflict | 0 | none |
| E: environment/infrastructure | 5 confirmed events | linked-worktree GBS issue; stale repo ACL; `/dev/shm`; Node PATH; systemd-oomd scope kill |

Code-fix quota used: **2/5**. The OOM isolation and Node PATH changes are
external run controls and do not consume the source-code fix quota.

## Structural change gate

The existing `wrt/cxx_wrapper` header is C-only, but its implementation is now
a GN `static_library`, so bundled-libc++ compiles the platform-facing side with
`std::__Cr` and defeats the intended ABI isolation.

Repository history contains the matching isolation design:

- Before/at `b8b64066af3a`, `wrt/cxx_wrapper` was built by platform GCC as
  `libwrt-c++wrapper.so`, and Chromium linked to it through a C-only interface.
- `8ec088bc5db4` deliberately converted it to a static GN library to avoid
  packaging the extra `.so`; that optimization assumes Chromium and the
  platform library share the same C++ standard library.
- The current spec still has install/file-list entries for
  `libwrt-c++wrapper.so`, gated by `__enable_platform_api_wrapper`.

Proposed next repair (requires approval because it changes the stdlib boundary
and link structure): restore the historical GCC-built shared C ABI bridge,
wire `wrt_lib` to the bridge group instead of the static library, and package
the bridge for bundled-libc++ builds without enabling unrelated platform
wrapper behavior.

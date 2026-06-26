# Swift 6.4 FreeBSD/aarch64 cross-build patches (macOS host)

Patches produced while cross-building the Swift 6.4 stdlib for FreeBSD 15.1/aarch64 on
macOS and verifying [swiftlang/swift#90143] on hardware. See
[`../VERIFICATION-macos-cross-6.4.md`](../VERIFICATION-macos-cross-6.4.md) for the full
write-up.

All patches apply to a `release/6.4.x` `swift` checkout (`git apply` from the `swift/`
repo root). Verified against `ce057fc` (2026-06-25).

## 0001-pr90143-with-freebsd-compile-fixes.patch  → push to PR #90143

The complete, **build-correct** FreeBSD `Synchronization.Mutex` change: PR #90143 plus
two fixes without which the PR does **not** compile on FreeBSD.

- `_SynchronizationShims.h`: add `#include <stddef.h>` — the FreeBSD futex shim calls
  `_umtx_op(..., NULL, NULL)`; `NULL` was only available via a transitive include in the
  native build, not in an isolated cross C-module compile.
- `Synchronization/CMakeLists.txt`: add `Mutex/SpinLoopHint.swift` to
  `SWIFT_SYNCHRONIZATION_FREEBSD_SOURCES`. `FreeBSDImpl.swift` calls `_spinLoopHint()`,
  but that file was registered only for the **Linux** source set → `cannot find
  '_spinLoopHint' in scope`.
- (plus PR #90143's `FreeBSDImpl.swift` futex Mutex itself.)

Apply to a clean `release/6.4.x` (do **not** also apply PR #90143 — this supersedes it).

## 0002-build-script-impl-wire-FREEBSD_USE_TOOLCHAIN_FILE.patch  → fold into arm64-freebsd-cross.patch

Wires the `FREEBSD_USE_TOOLCHAIN_FILE` env var (set by `build-freebsd.sh`) into the
per-product cmake configure, scoped to `freebsd-*` hosts. Without this the FreeBSD
LLVM/cmark/libdispatch/swift sub-projects silently configure for the macOS host
(Mach-O) instead of FreeBSD aarch64 ELF.

Injected at the configure call site rather than in `set_build_options_for_host`, because
the per-host `*_cmake_options` arrays are reassigned after that function runs. Layers on
top of `arm64-freebsd-cross.patch` (which only adds `freebsd-*` to the cross-host
allowlist); ideally merge this hunk into that patch.

## 0003-OPTIONAL-strip-diagnose-for-older-host.patch  → host-version workaround only

Removes 15 `@diagnose(...)` attribute usages from the stdlib. **Not an upstream fix** —
it is only needed when the macOS host frontend predates the `@diagnose` attribute.
The clean alternative is to use a host snapshot new enough to know `@diagnose` yet old
enough to still provide `Builtin.cancelAsyncTask` (i.e. matched to the `release/6.4.x`
branch point). The attribute only suppresses cosmetic "useless availability check"
warnings, so stripping it is behaviorally safe. Skip this if your host matches.

## Apply order

```sh
cd swift                      # release/6.4.x checkout
git apply ../patches-6.4/0001-pr90143-with-freebsd-compile-fixes.patch
git apply ../swift-freebsd/arm64-freebsd-cross.patch
git apply ../patches-6.4/0002-build-script-impl-wire-FREEBSD_USE_TOOLCHAIN_FILE.patch
# only if the host frontend predates @diagnose:
git apply ../patches-6.4/0003-OPTIONAL-strip-diagnose-for-older-host.patch
```

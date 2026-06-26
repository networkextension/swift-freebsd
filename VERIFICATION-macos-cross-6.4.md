# Verification: Swift 6.4 FreeBSD/aarch64 stdlib cross-built on macOS + PR #90143 Mutex fix

**Date:** 2026-06-26
**Host:** macOS 14.1 (Apple M3 Max, `Mac15,10`)
**Target:** FreeBSD 15.1 / aarch64 (board **swift-64**, `192.168.11.64`)
**Result:** ✅ Full stdlib cross-built; PR #90143 (Synchronization.Mutex deadlock fix)
compiled in and **verified deadlock-free under contention on real hardware**.

---

## 1. Summary

The Swift 6.4 standard library + runtime overlays were cross-compiled **from macOS
(Apple Silicon) for FreeBSD 15.1 aarch64**, with [swiftlang/swift#90143] applied. The
result is 22 `.so` + 21 `.swiftmodule` as FreeBSD aarch64 ELF. A contended-`Mutex`
stress test compiled against this stdlib was deployed to the board and ran to
completion with a correct result and no deadlock — confirming the fix on hardware.

> Only the stdlib/runtime is cross-built. The Swift *compiler* is not cross-compiled;
> it continues to run natively on the board.

---

## 2. Toolchain matrix

| Role | Component | Why |
|---|---|---|
| Host Swift frontend | swiftly `main-snapshot-2026-05-04` (**6.4-dev**) | Must match `release/6.4.x`. This is the **exact 6.4 branch-point** snapshot. `2026-06-24` (6.5-dev) is too new (`Builtin.cancelAsyncTask` removed); a 6.3-dev snapshot is too old. |
| Cross C/C++ + linker | `swift-6.3.1-RELEASE.xctoolchain` | Provides **clang 21** (modulemap has `_Builtin_float`) and **`ld.lld`** (macOS `ld64` cannot emit FreeBSD ELF). |
| Sysroot | `/opt/freebsd15-aarch64-sysroot` | `usr/{include,lib}` + `lib` rsynced from board .64; zstd aliases + `<stddef.h>` reachable. |
| Build tools | `cmake` + `ninja` (Python venv `~/swift-build-venv`) | — |
| Sources | `swift` `release/6.4.x` (`ce057fc`) + peers via `update-checkout --scheme release/6.4.x` | Internally consistent cross-repo set. |

Layout root: `/Users/local/swift64-cross/` (`build-freebsd.sh`,
`freebsd-aarch64-toolchain.cmake`, `cmake-stubs/zstd/`, `swift/`, peer repos).

---

## 3. Build

```sh
cd /Users/local/swift64-cross
bash build-freebsd.sh build      # macOS LLVM → macOS Swift 6.4 → FreeBSD stdlib
```

Output (`build/Ninja-ReleaseAssert/swift-freebsd-aarch64/lib/swift/freebsd/`):

```
$ file libswiftCore.so libswiftSynchronization.so libswift_Concurrency.so
libswiftCore.so:            ELF 64-bit LSB shared object, ARM aarch64, (FreeBSD), for FreeBSD 15.1
libswiftSynchronization.so: ELF 64-bit LSB shared object, ARM aarch64, (FreeBSD), for FreeBSD 15.1
libswift_Concurrency.so:    ELF 64-bit LSB shared object, ARM aarch64, (FreeBSD), for FreeBSD 15.1

$ llvm-nm -D libswiftSynchronization.so | grep umtx
                 U _umtx_op@FBSD_1.0          # PR #90143 futex Mutex linked in
```

22 `.so` total (Core, Glibc, Synchronization, _Concurrency, dispatch, BlocksRuntime,
Observation, Distributed, RegexBuilder, _StringProcessing, _RegexParser,
_Differentiation, _Volatile, _Builtin_float, SwiftOnoneSupport, + private test libs)
and 21 `.swiftmodule`.

### Fixes required (not in the published recipe — all real gaps)

1. **`build-script-impl` toolchain-file wiring (the critical one).** The committed
   `arm64-freebsd-cross.patch` only adds `freebsd-*` to the cross-host allowlist; it
   does **not** wire `FREEBSD_USE_TOOLCHAIN_FILE`. Without it the FreeBSD
   LLVM/cmark/swift sub-projects silently configure for macOS (Mach-O). Fix: inject
   the toolchain file at the per-product cmake-configure call, scoped to FreeBSD:

   ```sh
   # utils/build-script-impl, just before the `call env ... "${CMAKE}" ... ${source_dir}`
   if [[ "${host}" == freebsd-* ]] && [[ -n "${FREEBSD_USE_TOOLCHAIN_FILE:-}" ]]; then
       cmake_options+=( -DCMAKE_TOOLCHAIN_FILE="${FREEBSD_USE_TOOLCHAIN_FILE}" )
   fi
   ```
   (Editing `set_build_options_for_host` does **not** work — the per-host option
   arrays are reassigned afterwards.)

2. **Generator tools missing from the nightly** (`swift-compatibility-symbols`,
   `swift-def-to-strings-converter`, `swift-serialize-diagnostics`): symlink the
   build's own `swift-macosx-arm64/bin` copies into `~/swift-host-tools`.

3. **Macro `-plugin-path` resolution**: `~/swift-host-tools/../lib/swift/host/plugins`
   must exist — symlink `/Users/local/lib/swift` → the build's `swift-macosx-arm64/lib/swift`.

4. **`@diagnose` attribute** (15 usages in `release/6.4.x` HEAD, newer than the 05-04
   host): stripped — purely warning-suppression, cosmetic.

Note: the FreeBSD LLVM stays Mach-O; harmless — it's used only as a cmake package
(`find_package(LLVM/Clang)`), and the stdlib is compiled by the host frontend.

---

## 4. PR #90143 verification

### 4a. Compile gaps found in the PR (it would not build on FreeBSD as submitted)

| File | Problem | Fix |
|---|---|---|
| `stdlib/public/SwiftShims/swift/shims/_SynchronizationShims.h` | uses `NULL` (in `_umtx_op(..., NULL, NULL)`) without including it | add `#include <stddef.h>` to the `#if defined(__FreeBSD__)` block |
| `stdlib/public/Synchronization/CMakeLists.txt` | `FreeBSDImpl.swift` calls `_spinLoopHint()`, but `SpinLoopHint.swift` is registered only for **Linux** sources | add `Mutex/SpinLoopHint.swift` to `SWIFT_SYNCHRONIZATION_FREEBSD_SOURCES` |

Both compiled natively on the board only via transitive includes / a different source
set; an isolated FreeBSD cross-compile surfaces them. **Recommend pushing both to the PR.**

### 4b. Runtime test (the deadlock fix)

`mutextest/mutex_test.swift` — 16 OS threads (pthread), 100,000 `Mutex.withLock`
increments each on a shared counter. The pre-fix `UMTX_OP_MUTEX_LOCK`-on-`uint32`
implementation deadlocks under this contention; the futex implementation does not.

Cross-compiled against the new stdlib and run on swift-64:

```
=== uname ===
15.1-RELEASE arm64
=== running contended Mutex stress test (PR #90143) ===
threads=16 iters=100000 final=1600000 expected=1600000
PASS: contended Mutex completed, no deadlock, count correct
[exit 0]
```

A 60-second watchdog was armed to catch a hang; it never fired. **1,600,000/1,600,000
correct, no deadlock — PR #90143 verified on hardware.**

The same (FreeBSD-15-built) bundle was also run on **swift-29 (FreeBSD 14.4 arm64)** —
identical PASS (1,600,000/1,600,000, no deadlock, exit 0). The 15.1→14.4 `libutil`
soname skew does not affect this path (the bundled Swift `.so` + system
`libc.so.7`/`libthr` are compatible across 14/15). So the fix is verified on **both**
boards:

| board | OS | result |
|---|---|---|
| swift-64 | FreeBSD 15.1 / aarch64 | PASS — 1,600,000/1,600,000, no deadlock |
| swift-29 | FreeBSD 14.4 / aarch64 | PASS — 1,600,000/1,600,000, no deadlock |

---

## 5. Reproduce: cross-compile a program against the new stdlib

```sh
HOST=~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-04-a.xctoolchain
XCTC=~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain
RES=/Users/local/swift64-cross/build/Ninja-ReleaseAssert/swift-freebsd-aarch64/lib/swift
SYS=/opt/freebsd15-aarch64-sysroot

# one-time: mirror the runtime into the sysroot so swiftc finds swiftrt.o via -sdk
mkdir -p "$SYS/usr/lib/swift/freebsd/aarch64"
cp -R "$RES/freebsd/aarch64/." "$SYS/usr/lib/swift/freebsd/aarch64/"
cp -R "$RES/freebsd/"*.swiftmodule "$SYS/usr/lib/swift/freebsd/"

"$HOST/usr/bin/swiftc" \
  -target aarch64-unknown-freebsd15 -sdk "$SYS" -resource-dir "$RES" \
  -use-ld="$XCTC/usr/bin/ld.lld" \
  -L "$RES/freebsd/aarch64" -L "$SYS/usr/lib" \
  -Xlinker -rpath -Xlinker '$ORIGIN/lib' \
  prog.swift -o prog
```

> Pitfall: do **not** pass `-tools-directory <6.3.1>` — that swaps in the 6.3.1
> frontend, which cannot read the 6.4 `.swiftmodule`s. Use the 05-04 frontend and
> only redirect the linker via `-use-ld=<6.3.1>/ld.lld`.

### Deploy + run on the board

```sh
# bundle: prog + the 22 .so under ./lib (binary rpath = $ORIGIN/lib)
scp bundle.tgz swift@192.168.11.64:/tmp/
ssh swift@192.168.11.64 '/bin/sh -c "cd /tmp && tar xzf bundle.tgz && \
  LD_LIBRARY_PATH=/tmp/lib ./prog"'
```

(Board shell is csh — wrap remote commands in `/bin/sh -c`. Board reachable directly,
no jump host. Ship the **new** 6.4 `.so` and set `LD_LIBRARY_PATH`; the board's own
6.3.2 runtime is ABI-incompatible.)

---

## 6. Artifacts

- Stdlib: `/Users/local/swift64-cross/build/Ninja-ReleaseAssert/swift-freebsd-aarch64/lib/swift/freebsd/`
- Test + bundle: `/Users/local/swift64-cross/mutextest/`
- Build scripts + toolchain file: `/Users/local/swift64-cross/`

# DRAFT: FreeBSD port for Swift 6.x with aarch64 support

A starting point for a `lang/swift` (6.x) port that builds on **FreeBSD aarch64** (and
amd64), derived from the existing **`lang/swift510`** port. Intended for discussion with
the `lang/swift510` maintainer and FreeBSD ports reviewers — **not a finished port**.

## The bootstrap "chicken-and-egg" — 6.3 REQUIRES a prebuilt host toolchain

> **CORRECTION (verified building 6.3.2 on FreeBSD aarch64, 2026-06).** The earlier
> assumption — that `build-script`'s multi-stage `--bootstrapping bootstrapping` lets the
> port self-bootstrap from just system clang, as `lang/swift510` does — **does not hold for
> Swift 6.3.** It worked for 5.10 only because 5.10's standard library had no macros.

Swift 6.3's standard library uses **Swift macros** (`stdlib/public/core/SwiftMacros`), which
require `swift-syntax` / Swift-parser integration (`SWIFT_BUILD_SWIFT_SYNTAX=ON`). And
`swift/CMakeLists.txt` (≈line 1041) hard-enforces:

```cmake
# Only "HOSTTOOLS" is supported in Linux when Swift parser integration is enabled.
if(SWIFT_HOST_VARIANT_SDK MATCHES "LINUX|OPENBSD|FREEBSD" AND NOT BOOTSTRAPPING_MODE STREQUAL "HOSTTOOLS")
  message(WARNING "Force setting BOOTSTRAPPING=HOSTTOOLS ...")
  ... message(SEND_ERROR "No Swift compiler found ...")
```

So on FreeBSD/Linux, a macro-using (6.3) stdlib can **only** be built with
`--bootstrapping=hosttools` + a **prebuilt host Swift compiler**. Pure
`--bootstrapping bootstrapping` (no host Swift) errors with `SwiftMacros ... missing and no
known rule to make it` (syntax off) or `No Swift compiler found` (syntax on).

**Worse — the host must be VERSION-MATCHED.** In hosttools mode the host compiler builds the
target stdlib, so the stdlib gets stamped with the *host's* version. If you host-build
6.3.2 with, say, a 6.3-dev host, you get a **6.3.2 compiler + a 6.3-stamped stdlib**, and the
6.3.2 compiler then rejects its own stdlib:
`error: module compiled with Swift 6.3 cannot be imported by the Swift 6.3.2 compiler`.
Official Linux toolchains avoid this by downloading a host snapshot of the *same* version.

**Consequence for this port:** like `lang/rust` ships a stage0, **`lang/swift` 6.3 must
ship/depend on a version-matched 6.3.x bootstrap toolchain distfile** (`BUILD_DEPENDS` on a
`swift-bootstrap` distfile, or `USES=...`). It cannot self-bootstrap from system clang alone.

Creating that *first* matched bootstrap toolchain is a one-time effort, documented in
[BUILD-NOTES-6.3.md](BUILD-NOTES-6.3.md) (the "regen-from-`.swiftinterface`" trick turns a
near-version host build into a version-consistent one). Once one exists, subsequent port
builds use it as the hosttools seed.

## What carries over from lang/swift510 vs. what's new

`lang/swift510` already carries ~80 FreeBSD patches (CoreFoundation, libdispatch kqueue
plumbing, `SwiftConfigureSDK.cmake`, `targets.py`, `build-script-impl`, etc.). Those are
the bulk of the FreeBSD porting work and **carry forward** to 6.x (with rebasing).

This draft adds:

- **Makefile delta** ([Makefile](lang/swift/Makefile)): DISTVERSION → **6.3.2**, and
  `GH_TUPLE` gains the components 6.x introduced — `swift-build` (SwiftBuild),
  `swift-testing`, `swift-foundation`, `swift-foundation-icu`, `swift-toolchain-sqlite`.
  (Foundation is now split into `swift-foundation` + `swift-corelibs-foundation`.)
  Most repos use the coherent `swift-6.3.2-RELEASE` tag; the exceptions are pinned to the
  exact refs from swift-6.3.2's `utils/update_checkout/update-checkout-config.json`
  (`release/6.3` scheme):
  - `swift-toolchain-sqlite` → **1.0.7** (its own semver tags, no `swift-X.Y.Z-RELEASE`).
  - apple/*: argument-parser **1.6.1**, asn1 **1.3.2**, certificates **1.10.1**, collections
    **1.1.6**, crypto **3.12.5**, nio **2.65.0**, system **1.5.0**.
  - `Yams` is no longer listed in the 6.3 scheme (swift-format dropped it) — kept pending
    verification, remove if unused.
- **`files/start-build.sh`** ([start-build.sh](lang/swift/files/start-build.sh)): rewritten
  for `--bootstrapping=hosttools` seeded by a version-matched bootstrap toolchain
  (`SWIFT_BOOTSTRAP_TOOLCHAIN`) — **not** the swift510 `--bootstrapping bootstrapping`, which
  6.3 cannot use on FreeBSD (see above). Also serializes links for small-board stability.
- **A small set of 6.x-relevant patches** in `files/`.
- **[BUILD-NOTES-6.3.md](BUILD-NOTES-6.3.md)**: the full from-scratch build write-up
  (coherent checkout, hosttools/version-matched-host wall, the regen-from-`.swiftinterface`
  bootstrap trick, memory/thermal knobs).

## Important: cross-compile fixes vs. native-port fixes

The patches in this repo's top-level [`arm64-freebsd-cross.patch`](../arm64-freebsd-cross.patch)
were for **cross-compiling** the first toolchain from x86 (see [BOOTSTRAP.md](../BOOTSTRAP.md)).
A port does a **native multi-stage build**, so most of those cross-only fixes
(`build-script-impl` cross-host allowlist, `Libdispatch.cmake` cross args,
`CMakeLists.txt` arch hardcode) are **not** what the port needs.

The fixes that ARE relevant to a native 6.x build are included here:

- `files/patch-swift_lib_Macros_Sources_SwiftMacros_DebugDescriptionMacro.swift` —
  avoids `String.replacing` under `-disable-implicit-string-processing-module-import`
  (hit when building the macro plugins). *Upstream is aware; the proper fix may differ.*
- `files/patch-swift_cmake_modules_AddSwift.cmake` — orders the arch-specific host lib
  dir before the generic one so `-lswiftCore` resolves the right arch. Low-risk, may also
  help other platforms.

### Resource-dir / `LIBRARY_PATH` workarounds — NOT needed in the port

When we hand-assembled an *uninstalled* toolchain, `import Foundation` / `import Dispatch`
failed until we manually placed their **clang underlying modules** in the resource dir
(`dispatch/` + a sibling `os/` + `Block/`; the Foundation client modules `_FoundationCShims`,
`CoreFoundation`, `_foundation_unicode`) and set `LIBRARY_PATH=<resource-dir>/<platform>/<arch>`.

**The port does not need any of that.** `files/start-build.sh` runs `build-script ...
--install-all true`, the same proper install path `lang/swift510` uses on amd64. The install
step lays out the clang modules and shared libs in the correct resource-dir locations
itself, so there are **no** ad-hoc `LIBRARY_PATH` / module-copy steps in this port — those
were artifacts of the hand-assembled toolchain only.

## Provenance / validation

- aarch64 build verified end-to-end; compiler validation suite: **84% pass, 26 failures**
  out of 21,177 tests — swiftlang/swift#89943 (now tracked on the official
  "Swift on FreeBSD" project board).
- Built against `swift-DEVELOPMENT-SNAPSHOT-2026-02-02-a` (swift `3f8c798cfe`,
  LLVM `972b6285835`). A real submission should target a `-RELEASE` tag.

## Next steps

1. Rebase the `lang/swift510` patch set (~80 FreeBSD patches) onto `swift-6.3.2-RELEASE`.
2. Build on a FreeBSD aarch64 host with poudriere (see [POUDRIERE.md](POUDRIERE.md)),
   iterate on whatever new 6.x patches surface; regenerate `distinfo` and `pkg-plist`.
3. Verify the Yams dependency: drop it from `GH_TUPLE` if the 6.3.2 build never fetches it.
4. Coordinate with the `lang/swift510` maintainer (jgopensource@proton.me) and Xin LI.

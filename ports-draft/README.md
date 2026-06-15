# DRAFT: FreeBSD port for Swift 6.x with aarch64 support

A starting point for a `lang/swift` (6.x) port that builds on **FreeBSD aarch64** (and
amd64), derived from the existing **`lang/swift510`** port. Intended for discussion with
the `lang/swift510` maintainer and FreeBSD ports reviewers — **not a finished port**.

## The bootstrap "chicken-and-egg" — already solved

Building Swift needs a Swift compiler (the compiler contains Swift code,
`SwiftCompilerSources`). The port does **not** need a pre-existing Swift toolchain:
`build-script`'s **multi-stage bootstrapping** first builds a stage-0 C++-only compiler
(with the system clang), then uses that to compile `SwiftCompilerSources` into the final
compiler. This is exactly how `lang/swift510` builds on amd64 today; this port extends it
to aarch64. (Optionally, a prebuilt bootstrap toolchain could be shipped as a distfile —
like `lang/rust` does — to speed builds, but it is not required.)

## What carries over from lang/swift510 vs. what's new

`lang/swift510` already carries ~80 FreeBSD patches (CoreFoundation, libdispatch kqueue
plumbing, `SwiftConfigureSDK.cmake`, `targets.py`, `build-script-impl`, etc.). Those are
the bulk of the FreeBSD porting work and **carry forward** to 6.x (with rebasing).

This draft adds:

- **Makefile delta** ([Makefile](lang/swift/Makefile)): DISTVERSION → 6.x, and `GH_TUPLE`
  gains the components 6.x introduced — `swift-build` (SwiftBuild), `swift-testing`,
  `swift-foundation`, `swift-foundation-icu`, `swift-toolchain-sqlite`. (Foundation is now
  split into `swift-foundation` + `swift-corelibs-foundation`.)
- **A small set of 6.x-relevant patches** in `files/`.

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

### Build/install-step fix (not a source patch)

`import Foundation` / `import Dispatch` need their **clang underlying modules** laid out in
the toolchain's resource dir. In a from-scratch native build the install step handles this;
when assembling a usable toolchain we had to place, under `lib/swift/`:

- `dispatch/` (the libdispatch public headers + `module.modulemap`) and a **sibling**
  `os/` directory (the headers use `#include <os/...>`), plus `Block/`.
- the Foundation client clang modules `_FoundationCShims`, `CoreFoundation`,
  `_foundation_unicode`.

And set `LIBRARY_PATH=<resource-dir>/<platform>/<arch>` so the linker finds
`libFoundation.so` / `libswiftDispatch.so`. These belong in `files/start-build.sh` /
the install stage rather than as source patches.

## Provenance / validation

- aarch64 build verified end-to-end; compiler validation suite: **84% pass, 26 failures**
  out of 21,177 tests — swiftlang/swift#89943 (now tracked on the official
  "Swift on FreeBSD" project board).
- Built against `swift-DEVELOPMENT-SNAPSHOT-2026-02-02-a` (swift `3f8c798cfe`,
  LLVM `972b6285835`). A real submission should target a `-RELEASE` tag.

## Next steps

1. Rebase the `lang/swift510` patch set onto the 6.x release tag.
2. Wire the resource-dir / `LIBRARY_PATH` fixes into `files/start-build.sh`.
3. Build on a FreeBSD aarch64 host (poudriere), iterate on new 6.x patches.
4. Coordinate with the `lang/swift510` maintainer (jgopensource@proton.me) and Xin LI.

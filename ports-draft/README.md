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
- **`files/start-build.sh`** ([start-build.sh](lang/swift/files/start-build.sh)): adapted
  verbatim from swift510, adding only `--swift-testing true`.
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

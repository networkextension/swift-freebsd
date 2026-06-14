# Native-built full toolchain (v0.3.0) — usage

This is the **complete Swift 6.3-dev toolchain built natively on arm64 FreeBSD**
(stage-2 bootstrap output), including the standard library, Concurrency, Dispatch,
the full Foundation family, XCTest, and swift-testing — all compiled natively on the
board, not cross-compiled.

Asset: `swift-6.3-dev-freebsd-arm64-native-full-*.tar.gz`

## Layout

```
usr/bin/        swift-frontend, swiftc, clang-21(+clang/clang++), lld(+ld.lld), swift-* tools
usr/lib/swift/freebsd/          141 .swiftmodule (stdlib + Foundation/Dispatch/XCTest/Testing)
usr/lib/swift/freebsd/aarch64/  32 .so/.a + swiftrt.o
usr/lib/swift/host/compiler/    compiler plugin modules (lib_Compiler*.so)
usr/lib/clang/21/               clang resource headers
```

## Core (works out of the box)

Compiler + full standard library + Concurrency are directly usable:

```sh
T=/path/to/usr
RES=$T/lib/swift; RDA=$RES/freebsd/aarch64
export LD_LIBRARY_PATH=$RDA:$RES/host/compiler
$T/bin/swiftc -resource-dir $RES -L $RDA -Xlinker -rpath -Xlinker $RDA -use-ld=lld hello.swift -o hello
LD_LIBRARY_PATH=$RDA ./hello
```

Verified: `print`, collections, async/await + TaskGroup, Regex/_StringProcessing.

## Foundation / Dispatch / XCTest / swift-testing

The libraries and `.swiftmodule`s are included. Because `build-script` on FreeBSD does
not yet wire the Foundation/Dispatch *clang* underlying modules into the resource-dir
install layout, `import Foundation` currently needs the module-map/include flags that the
libraries were built with (these are proven — they are exactly what built swift-testing):

```sh
SRC=/path/to/source-checkout   # swift-foundation, swift-foundation-icu, swift-corelibs-*
B=/path/to/build/Ninja-ReleaseAssert
FLAGS="\
 -I $B/foundation-freebsd-aarch64/swift \
 -I $B/libdispatch-freebsd-aarch64/src/swift/swift \
 -L $B/foundation-freebsd-aarch64/lib -L $B/libdispatch-freebsd-aarch64 \
 -Xcc -fmodule-map-file=$SRC/swift-corelibs-foundation/Sources/CoreFoundation/include/module.modulemap \
 -Xcc -I$SRC/swift-corelibs-foundation/Sources/CoreFoundation/include \
 -Xcc -fmodule-map-file=$SRC/swift-foundation-icu/icuSources/include/_foundation_unicode/module.modulemap \
 -Xcc -I$SRC/swift-foundation-icu/icuSources/include \
 -Xcc -fmodule-map-file=$SRC/swift-foundation/Sources/_FoundationCShims/include/module.modulemap \
 -Xcc -I$SRC/swift-foundation/Sources/_FoundationCShims/include \
 -Xcc -fmodule-map-file=$SRC/swift-corelibs-libdispatch/dispatch/module.modulemap \
 -Xcc -I$SRC/swift-corelibs-libdispatch -Xcc -I$SRC/swift-corelibs-libdispatch/src/swift/shims \
 -Xcc -ivfsoverlay -Xcc $B/libdispatch-freebsd-aarch64/dispatch-vfs-overlay.yaml"
swiftc $FLAGS ... your-foundation-using-code.swift
```

Proper out-of-the-box `import Foundation` (installing those clang modules into the
resource-dir layout the way the Linux toolchain install does) is the remaining
packaging follow-up.

## Provenance

Built by the cross-compiled seed compiler (see [BOOTSTRAP.md](BOOTSTRAP.md)) running on a
real arm64 FreeBSD 14.4 board, from the matched `swift-DEVELOPMENT-SNAPSHOT-2026-02-02-a`
component set. Target triple `aarch64-unknown-freebsd14.4`.

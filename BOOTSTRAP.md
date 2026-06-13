# Native self-hosting bootstrap — Swift compiler for FreeBSD arm64

This documents stage 2 of the project: cross-building the **Swift compiler itself**
(`swift-frontend`, not just the stdlib) for `aarch64-unknown-freebsd`, and validating it
by running it natively on real arm64 FreeBSD hardware to compile and run Swift.

> Stage 1 (the stdlib + a `swiftc-arm64` cross wrapper) is in [README.md](README.md).
> This stage produces a **seed toolchain** that runs *on* arm64.

## Result (validated 2026-06-13)

The cross-built aarch64 `swift-frontend` runs on a real arm64 FreeBSD 14.4 board and
natively compiles + runs Swift:

```
$ swift-frontend --version
Swift version 6.3-dev (LLVM 972b62858355d07, Swift 3f8c798cfe25bbb)
Target: aarch64-unknown-freebsd14.3

$ swiftc hello.swift -o hello && ./hello
Hello from NATIVELY self-hosted Swift on FreeBSD arm64!
sorted: [1, 2, 3, 5, 8, 9]
arch: arm64 verified
```

The output binary is `ELF aarch64 … for FreeBSD 14.4` — i.e. built natively on the board.

## Matched component revisions (critical)

The single most important lesson: **do not pin dependency repos by calendar date on `main`.**
Main-by-date is *not* a consistent set and produces SPI/API mismatches deep into the build
(e.g. `AccessorDeclSyntax.modifiers` missing, `preamble is inaccessible due to @_spi`).

Use the official **snapshot tags** — they are cut as consistent cross-repo sets. For the
Feb 3 2026 toolchain (`swift 6.3-dev`, the swift.org FreeBSD CI nightly) the matched set is:

| repo | revision | note |
|---|---|---|
| swift | `3f8c798cfe25bbb04f2bae2ec81a46259f5f637b` | = toolchain's `swift --version` hash |
| llvm-project | `972b62858355d0714921cbf489de6598376e914a` | = toolchain's LLVM hash |
| swift-syntax | `edbbad240dfcc4a9a791c1e4261f52fe08342e53` | tag `swift-DEVELOPMENT-SNAPSHOT-2026-02-02-a` |
| swift-experimental-string-processing | `733e1ac1379fcabef9202c7f2c5973e20d07178f` | has `swiftCompilerLexRegexLiteral` |

When a host-tools Swift compile fails with *"cannot find X in scope"*, *"X is inaccessible
due to @_spi"*, or *"missing required module"*, it is a swift-syntax / string-processing
version mismatch — realign to the snapshot tag, `rm -rf <builddir>/_deps` (swift-syntax is
FetchContent-inlined), reconfigure, rebuild.

## Build invocation

Same prerequisites as stage 1 (x86 host toolchain at `/usr/local/swift`, arm64 sysroot at
`/opt/freebsd-arm64-sysroot`, aarch64 stdlib resources at `/opt/swift-aarch64-resources`).
Apply [`arm64-freebsd-cross.patch`](arm64-freebsd-cross.patch), then:

```sh
./swift/utils/build-script --release \
  --cross-compile-hosts=freebsd-aarch64 \
  --stdlib-deployment-targets=freebsd-aarch64 \
  --native-swift-tools-path=/usr/local/swift/bin \
  --native-clang-tools-path=/usr/local/swift/bin \
  --skip-test-swift --skip-build-benchmarks \
  --extra-cmake-options="-DSWIFT_SDK_FREEBSD_ARCH_aarch64_PATH=/opt/freebsd-arm64-sysroot \
    -DEXECINFO_LIBRARY=/opt/freebsd-arm64-sysroot/usr/lib/libexecinfo.so \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCMAKE_Swift_COMPILER=/usr/local/swift/bin/swiftc"
```

### build-script doesn't pass cross args to sub-projects

`build-script` silently builds **LLVM, cmark, and libdispatch for the host arch** when
cross-compiling for FreeBSD (it only wired the cross args for Windows/Darwin). Each must be
wiped and hand-configured with real cross args. Example for the aarch64 LLVM/cmark:

```sh
cmake -G Ninja <src> \
  -DCMAKE_SYSTEM_NAME=FreeBSD -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_SYSTEM_VERSION=14.3 \
  -DCMAKE_SYSROOT=/opt/freebsd-arm64-sysroot \
  -DCMAKE_C_COMPILER_TARGET=aarch64-unknown-freebsd14.3 \
  -DCMAKE_CXX_COMPILER_TARGET=aarch64-unknown-freebsd14.3 \
  -DCMAKE_FIND_ROOT_PATH=/opt/freebsd-arm64-sysroot \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DLLVM_NATIVE_TOOL_DIR=<x86 llvm bin>   # for LLVM: run tblgen with the host build
```

Verify every produced `.a`/`.so` is actually aarch64 (`ar x … && file …`) — a host-arch
object only surfaces at the final `swift-frontend` link as
`… is incompatible with /opt/freebsd-arm64-sysroot/usr/lib/crt1.o`.

### The winning Swift cross-compile flags for host tools

ASTGen / SwiftCompilerSources (Swift code with C++ interop) needs, in `CMAKE_Swift_FLAGS`
and `SWIFT_COMPILER_SOURCES_SDK_FLAGS`:

```
-sysroot <SR> -resource-dir /opt/swift-aarch64-resources
-Xcc -nostdlibinc
-Xcc -isystem -Xcc <SR>/usr/include/c++/v1
-Xcc -isystem -Xcc <SR>/usr/include
-Xcc -fmodule-map-file=<SR>/usr/include/swift-glibc.modulemap
```

Use swift's `-sysroot`, **never `-sdk`** (its include synthesis is broken for FreeBSD cross,
and the two together fight). Any directory containing C standard headers must NOT appear as a
user-level `-I`/`-isystem` in a C++ compile — it jumps ahead of libc++'s internal headers
(`<cstddef> tried including <stddef.h> but didn't find libc++'s`). That includes
`find_library`/`find_path` host results: repoint `LibEdit_INCLUDE_DIRS`, `ZLIB_INCLUDE_DIR`,
`UUID_INCLUDE_DIR` cache vars into the sysroot.

Build-time generator tools missing from the nightly (`swift-compatibility-symbols`,
`swift-def-to-strings-converter`, `swift-serialize-diagnostics`) must be hand-compiled as
native x86 (single `.cpp` + `LocalizationFormat.cpp` + x86 LLVM libs) into the host
toolchain's `bin`.

## Assembling a runnable seed toolchain

The seed `swift-frontend` is itself written in Swift (SwiftCompilerSources), so to *run* it
on arm64 you need a complete runtime, not just the binary:

1. **bin/** — `swift-frontend` (+ `swift`,`swiftc` symlinks), `clang-21` (+`clang`,`clang++`),
   `lld` (+`ld.lld`), `swift-plugin-server`, `swift-autolink-extract`
2. **stdlib** — aarch64 `.so` in `<res>/freebsd/aarch64`
3. **the compiler's own Swift modules** — the 14 `lib_Compiler*.so` from
   `swift-freebsd-aarch64/lib/swift/host/compiler/` (easy to forget)
4. **shims/** — `tar -czh` to dereference the symlink
5. **ports libs** — `libuuid.so.1`, `libzstd.so.1`

Run on the board:

```sh
export LD_LIBRARY_PATH=<res>/freebsd/aarch64:<res>/host/compiler
swiftc -resource-dir <res> -L <res>/freebsd/aarch64 \
  -Xlinker -rpath -Xlinker <res>/freebsd/aarch64 \
  -use-ld=lld hello.swift -o hello
```

The `release` asset `seed-toolchain-aarch64-freebsd.tar.gz` bundles 1–5 already.

## Troubleshooting log (build 1 → 36)

| symptom | cause / fix |
|---|---|
| `_Float16 is not supported` (compiler-rt i386) | `COMPILER_RT_DEFAULT_TARGET_ONLY=ON`; also delete `COMPILER_RT_DEFAULT_TARGET_TRIPLE` from the builtins CMakeCache (mutually exclusive) |
| `Unknown host to cross-compile for: freebsd-aarch64` | add `freebsd-*` to the allowlist at `build-script-impl:1108` (line 2933 already had it — upstream fixed only one) |
| `No CMAKE_Swift_COMPILER` | pass `-DCMAKE_Swift_COMPILER=/usr/local/swift/bin/swiftc` |
| `PunnedPointer … getFromOpaqueValue` | pin llvm-project to the toolchain LLVM commit |
| `libdispatch.so is incompatible with crt1.o` | `Libdispatch.cmake` FreeBSD cross-args branch |
| `… is incompatible with crt1.o` (LLVM/cmark libs) | hand-configure those sub-projects with cross args (above) |
| `cstddef … didn't find libc++'s stddef.h` | `-sysroot` not `-sdk`; sysroot includes via the flag recipe above; no host C-header `-I` |
| `cannot find 'modifiers'` / `'preamble' is @_spi` | swift-syntax version mismatch → snapshot tag |
| `cannot find 'swiftCompilerLexRegexLiteral'` | string-processing → `733e1ac` |
| phantom `ByteCodeGen+DSLList.swift` | stale file list in build.ninja → `rm -rf <builddir>/stdlib <builddir>/_deps`, reconfigure |
| `Shared object "lib_Compiler*.so" not found` at runtime | ship `lib/swift/host/compiler/` (point 3 above) |

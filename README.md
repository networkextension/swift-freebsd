# Swift on FreeBSD arm64 — Cross-Compilation Toolchain

[中文版 / Chinese version](README.zh-CN.md)

Cross-compile Swift programs from an **x86 FreeBSD 14.x** host to **FreeBSD arm64 (aarch64)**, validated on real arm64 hardware.

> swift.org ships no Swift distribution for FreeBSD aarch64, and FreeBSD ports only carries Swift 5.10.1 (x86).
> This project cross-compiles the aarch64 Swift runtime + stdlib from source to fill that gap.

> **🎉 Update (2026-06-13): native self-hosting achieved.** The whole Swift *compiler*
> (`swift-frontend`, not just the stdlib) has been cross-built for arm64 and now runs on a
> real arm64 FreeBSD board, natively compiling and running Swift. See **[BOOTSTRAP.md](BOOTSTRAP.md)**
> and the `seed-toolchain-aarch64-freebsd.tar.gz` release asset.

> **🎉 Update (2026-06-20): native 6.3.2 toolchain + swiftly.** Beyond the cross-compile
> bring-up below, this repo now ships a **complete native `swift-6.3.2-RELEASE` toolchain**
> for FreeBSD 15.1/aarch64 (compiler + stdlib + Foundation + Dispatch + XCTest + swift-testing
> + SwiftPM) and the FreeBSD port to build it — and **swiftly itself now builds and runs on
> FreeBSD**. Two legs:
>
> - **Toolchain** → releases ([v0.4.1](https://github.com/networkextension/swift-freebsd/releases/tag/v0.4.1)) · port: [`ports-draft/lang/swift632`](ports-draft/lang/swift632)
> - **swiftly** (toolchain manager) → [`swiftly/`](swiftly) — `FreeBSDPlatform` + dependency patches (incl. a full SwiftNIO FreeBSD port)
>
> FreeBSD Swift work is tracked on the official [Swift on FreeBSD](https://github.com/orgs/swiftlang/projects/16) board.

## Validation Results (2026-06-11)

Real hardware — NXP DPAA2 board, FreeBSD 14.4-RELEASE arm64:

```
=== Test 1: hello_arm64 ===
Hello from Swift on FreeBSD arm64!
arch check: arm64 ✓
sorted: [1, 1, 2, 3, 4, 5, 6, 9]
[PASS] hello

=== Test 2: async_arm64 (Swift Concurrency) ===
concurrency works: [1, 4, 9, 16, 25, 36, 49, 64]
[PASS] async
```

stdlib, async/await, and TaskGroup concurrency all work.

## Architecture

```
x86 FreeBSD 14.4 (build host)
├── /usr/local/swift              Swift 6.3-dev x86 nightly toolchain (swiftc is already a cross-compiler)
├── /opt/freebsd-arm64-sysroot    FreeBSD 14.3 arm64 headers + libs (extracted from official base.txz)
├── /opt/swift-aarch64-resources  Self-built aarch64 Swift runtime/stdlib resource directory
└── /usr/local/bin/swiftc-arm64   One-command cross-compile wrapper script
```

```sh
# Usage: one command to produce an arm64 binary
swiftc-arm64 hello.swift -o hello
file hello   # → ELF 64-bit LSB executable, ARM aarch64, FreeBSD 14.3
```

## Setup Steps

### 1. Install the x86 host toolchain

The swift.org CI nightly (the only Swift 6.x binary available for FreeBSD):

```sh
fetch https://download.swift.org/tmp-ci-nightly/development/freebsd-14_ci_latest.tar.gz
mkdir -p /usr/local/swift
tar -xzf freebsd-14_ci_latest.tar.gz -C /usr/local/swift --strip-components=1
pkg install -y cmake ninja python311 bash git rsync libuuid icu libedit libxml2 sqlite3
ln -sf /usr/local/bin/python3.11 /usr/local/bin/python3
```

### 2. Prepare the arm64 sysroot

```sh
fetch https://download.freebsd.org/releases/arm64/aarch64/14.3-RELEASE/base.txz
mkdir -p /opt/freebsd-arm64-sysroot
tar -xf base.txz -C /opt/freebsd-arm64-sysroot ./lib ./usr/lib ./usr/include ./usr/libdata
```

### 3. Check out Swift sources (MUST match the toolchain commit!)

```sh
mkdir /build/swift-project && cd /build/swift-project
git clone --depth 1 https://github.com/swiftlang/swift.git swift
# Critical: sources must be pinned to the toolchain's commit (the hash in `swift --version`),
# otherwise you get frontend-flag incompatibilities
cd swift && git fetch --depth 1 origin <toolchain-commit-full-sha> && git checkout FETCH_HEAD && cd ..
./swift/utils/update-checkout --clone --skip-history --scheme main
```

### 4. Apply the patch

Apply [`arm64-freebsd-cross.patch`](arm64-freebsd-cross.patch) from this repo (two upstream bugs, see below):

```sh
cd /build/swift-project/swift && git apply /path/to/arm64-freebsd-cross.patch
```

### 5. Cross-compile the stdlib

```sh
cd /build/swift-project
./swift/utils/build-script --release \
  --build-swift-tools=0 \
  --native-swift-tools-path=/usr/local/swift/bin \
  --native-clang-tools-path=/usr/local/swift/bin \
  --skip-build-llvm --skip-build-cmark \
  --stdlib-deployment-targets=freebsd-aarch64 \
  --swift-primary-variant-sdk=FREEBSD --swift-primary-variant-arch=aarch64 \
  --skip-test-swift --skip-build-benchmarks \
  --extra-cmake-options="-DSWIFT_SDK_FREEBSD_ARCH_aarch64_PATH=/opt/freebsd-arm64-sysroot -DEXECINFO_LIBRARY=/opt/freebsd-arm64-sysroot/usr/lib/libexecinfo.so"
```

⚠️ If a CMakeCache already exists, `-DEXECINFO_LIBRARY` will NOT override the cached value —
edit CMakeCache.txt by hand to point it at the aarch64 copy inside the sysroot.

### 6. Install the artifacts

```sh
BUILD=/build/swift-project/build/Ninja-ReleaseAssert/swift-freebsd-x86_64
# Resource directory (tar -h dereferences symlinks)
mkdir -p /opt/swift-aarch64-resources
tar -C $BUILD/lib/swift -chf - . | tar -C /opt/swift-aarch64-resources -xf -
# Mirror swiftrt.o & runtime into the sysroot (the linker looks there via -sdk)
mkdir -p /opt/freebsd-arm64-sysroot/usr/lib/swift/freebsd
cp -R /opt/swift-aarch64-resources/freebsd/aarch64 /opt/freebsd-arm64-sysroot/usr/lib/swift/freebsd/
```

⚠️ **Never** rsync build artifacts onto the top level of `/usr/local/swift/lib/swift/freebsd/` —
it clobbers the host x86 libraries with aarch64 ones, and swift-driver (written in Swift itself)
will stop loading entirely.

### 7. Wrapper script

```sh
cat > /usr/local/bin/swiftc-arm64 << 'EOF'
#!/bin/sh
exec /usr/local/swift/bin/swiftc \
  -target aarch64-unknown-freebsd14.3 \
  -sdk /opt/freebsd-arm64-sysroot \
  -resource-dir /opt/swift-aarch64-resources \
  -use-ld=lld \
  "$@"
EOF
chmod +x /usr/local/bin/swiftc-arm64
```

## Upstream Bugs Found (see patch)

1. **`CMakeLists.txt`** — the FreeBSD SDK configuration hard-codes
   `configure_sdk_unix("FreeBSD" "${SWIFT_HOST_VARIANT_ARCH}")`, registering only the host
   architecture. The downstream allowlist in `SwiftConfigureSDK.cmake` already accepts
   `aarch64|x86_64`, but the entry point never passes it through.
   Note: configuring both arches (`"x86_64;aarch64"`) breaks at the archive-merge step
   (no lipo on non-Darwin; `cmake -E copy <multiple sources> → <single file>` fails),
   so configure aarch64 only.

2. **`cmake/modules/Libdispatch.cmake`** — the libdispatch ExternalProject only passes
   cross-compilation arguments (`CMAKE_C_COMPILER_TARGET`) **on Windows**. When
   cross-compiling for FreeBSD, libdispatch silently builds for the host architecture,
   and the failure only surfaces later when linking `_Concurrency`. The patch adds a
   FREEBSD branch passing the target triple + sysroot + `CMAKE_SYSTEM_NAME`.

## Troubleshooting Log

| Problem | Symptom | Fix |
|---|---|---|
| Source/toolchain version mismatch | `unknown argument: '-solver-enable-crash-on-valid-salvage'` | Check out the swift repo at the toolchain's commit |
| Dual-arch lipo merge | `Target (for copy command) ... is not a directory` | Configure aarch64 as the only arch |
| find_library picks host lib | `libexecinfo.so is incompatible with crti.o` | Point `EXECINFO_LIBRARY` into the sysroot (mind the CMakeCache) |
| libdispatch built as x86 | `libdispatch.so is incompatible with crti.o` | Libdispatch.cmake patch + delete the stale prefix dir to reconfigure |
| swiftrt.o not found | `no such file: .../sysroot/usr/lib/swift/freebsd/aarch64/swiftrt.o` | Mirror the aarch64 runtime into the sysroot |
| Linking against host x86 stdlib | `libswiftCore.so is incompatible with crt1.o` | Separate `-resource-dir` pointing at the aarch64 resources |

## Built libraries — now complete

✅ **Standard library & core**: Core, _Concurrency, Glibc, dispatch (C), Synchronization,
Distributed, Observation, RegexBuilder, _StringProcessing, _RegexParser, _Differentiation,
SwiftOnoneSupport, and more.

✅ **Higher-level libraries (all built natively on arm64 in the v0.3.0 toolchain)**:
libswiftDispatch (Swift overlay), FoundationEssentials, FoundationInternationalization,
_FoundationICU, Foundation, FoundationXML (libxml2), FoundationNetworking (curl), XCTest,
swift-testing. See [USAGE-full-toolchain.md](USAGE-full-toolchain.md) and the
`v0.3.0-native-full` release.

> Historical note: these were originally missing in the cross-compiled v0.1.0 stdlib. They
> were completed during the native stage-2 bootstrap ([BOOTSTRAP.md](BOOTSTRAP.md)) by
> building them from source with the native compiler on the board (no sysroot needed —
> native libxml2/curl/icu from `pkg`).

## Release Assets

- `swift-freebsd-arm64-cross-env.tar.gz` — complete cross-compilation environment
  (sysroot + aarch64 resources + wrapper script); extract and go (you still need the x86
  nightly toolchain from Step 1)
- `swift-arm64-test.tar.gz` — test package for real hardware (2 test binaries + 11 runtime
  libraries + one-shot script)

## Environment

- Build host: FreeBSD 14.4-RELEASE amd64, 8 cores / 32GB
- Toolchain: Swift 6.3-dev nightly (commit `3f8c798cfe`, 2026-02-03)
- Target: `aarch64-unknown-freebsd14.3`
- Validation hardware: NXP DPAA2 arm64, FreeBSD 14.4-RELEASE

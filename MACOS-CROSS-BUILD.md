# Cross-Compiling Swift 6.4 for FreeBSD aarch64 on macOS M3 Max

Cross-compile the Swift 6.4 stdlib and runtime libraries from macOS (Apple Silicon)
targeting a FreeBSD 15 aarch64 board. The result is a set of `.so` libraries and
`.swiftmodule` files that can run natively on the board.

**What this produces:** the stdlib (`libswiftCore.so`, `libswiftGlibc.so`,
`libswiftSynchronization.so`, etc.) and all overlays, as FreeBSD ELF aarch64 binaries.
It does **not** cross-compile the Swift compiler itself — that runs on the board using the
existing 6.3.2 toolchain as hosttools for bootstrapping.

---

## Prerequisites

### 1. Source checkout

```sh
mkdir ~/swift64-cross && cd ~/swift64-cross
git clone https://github.com/apple/swift swift
cd swift && utils/update-checkout --scheme release/6.4.x --clone-with-ssh
cd ..
```

### 2. Swift 6.3.1 RELEASE toolchain (cross-compiler)

Download from swift.org and install:

```
~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/
```

This provides `clang`, `clang++`, `ld.lld`, `llvm-ar`, etc. at clang version 21,
which can target `aarch64-unknown-freebsd15` and produce correct FreeBSD ELF output.
The CLT's clang (15.0.0, from Xcode Command Line Tools) cannot be used as the
cross-compiler because its `_Builtin_float` module map is too old.

Verify:
```sh
~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/clang \
  --target=aarch64-unknown-freebsd15 --version
# clang version 21.0.0 ...
```

### 3. macOS 6.4-dev swift-frontend (host compiler)

Build the macOS Swift 6.4 host toolchain first (or use a nightly). Place symlinks in
`~/swift-host-tools/` pointing to the 6.4-dev `swift-frontend`, `swiftc`, etc.:

```sh
mkdir -p ~/swift-host-tools
MACOS_BUILD=~/swift64-cross/build/Ninja-ReleaseAssert/swift-macosx-arm64
for b in swift-frontend swiftc swift clang clang++; do
  ln -sf "$MACOS_BUILD/bin/$b" ~/swift-host-tools/
done
```

The `swift-frontend` here is the 6.4-dev compiler that actually compiles Swift stdlib
sources; it runs on macOS but emits code for the FreeBSD target.

### 4. cmake and ninja via venv

```sh
python3 -m venv ~/swift-build-venv
~/swift-build-venv/bin/pip install cmake ninja
```

### 5. FreeBSD aarch64 sysroot

Rsync the board's root filesystem headers and libraries:

```sh
sudo mkdir -p /opt/freebsd15-aarch64-sysroot
rsync -av --rsync-path="sudo rsync" \
  -e "ssh -J local@10.88.0.1" \
  --include='*/' \
  --include='/usr/include/**' \
  --include='/usr/lib/**' \
  --include='/lib/**' \
  --exclude='*' \
  swift@192.168.11.64:/ \
  /opt/freebsd15-aarch64-sysroot/
```

**Post-sync fixups** — FreeBSD's LLVM was built with an internal `libprivatezstd`; add
the standard name as a symlink, and remove any prebuilt Swift 6.3.2 modules (they would
conflict with the 6.4 build):

```sh
SYSROOT=/opt/freebsd15-aarch64-sysroot

# zstd aliases
sudo ln -sf libprivatezstd.a   $SYSROOT/usr/lib/libzstd.a
sudo ln -sf libprivatezstd.so.5 $SYSROOT/usr/lib/libzstd.so.5
sudo ln -sf libprivatezstd.so.5 $SYSROOT/usr/lib/libzstd.so

# zstd header
sudo mkdir -p $SYSROOT/usr/include
sudo ln -sf private/zstd/zstd.h $SYSROOT/usr/include/zstd.h

# Remove Swift 6.3.2 prebuilt modules — they cause version-mismatch failures
# when swift-frontend 6.4 uses -sdk $SYSROOT and finds them in usr/lib/swift/
sudo mv $SYSROOT/usr/lib/swift/freebsd \
        $SYSROOT/usr/lib/swift/freebsd-632-backup
```

### 6. cmake stub for zstd

The macOS LLVM build exports `zstd::libzstd_shared` from `LLVMExports.cmake`. When
cmake cross-configures the FreeBSD Swift project, it re-imports LLVM targets and
requires this target to exist. The FreeBSD sysroot has zstd under the private name;
a cmake stub provides the canonical target name.

Create `~/swift64-cross/cmake-stubs/zstd/zstdConfig.cmake`:

```cmake
cmake_minimum_required(VERSION 3.16)
if(NOT TARGET zstd::libzstd_shared)
  add_library(zstd::libzstd_shared SHARED IMPORTED GLOBAL)
  set_target_properties(zstd::libzstd_shared PROPERTIES
    IMPORTED_LOCATION /opt/freebsd15-aarch64-sysroot/usr/lib/libzstd.so
    INTERFACE_INCLUDE_DIRECTORIES /opt/freebsd15-aarch64-sysroot/usr/include)
endif()
if(NOT TARGET zstd::libzstd_static)
  add_library(zstd::libzstd_static STATIC IMPORTED GLOBAL)
  set_target_properties(zstd::libzstd_static PROPERTIES
    IMPORTED_LOCATION /opt/freebsd15-aarch64-sysroot/usr/lib/libzstd.a
    INTERFACE_INCLUDE_DIRECTORIES /opt/freebsd15-aarch64-sysroot/usr/include)
endif()
set(zstd_FOUND TRUE)
```

---

## CMake toolchain file

`~/swift64-cross/freebsd-aarch64-toolchain.cmake` configures cmake for the FreeBSD
cross-compilation target. Every cmake variable here works around a specific failure;
the comments explain the WHY.

Key points:

- `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER` — XCTC61 clang 21 (not CLT clang 15).
  CLT 15's module.modulemap doesn't define `_Builtin_float`; 21's does.
- `CMAKE_SYSROOT` — the FreeBSD sysroot; sets `-isysroot` for all C/C++ compilations.
- Linker flags use the full path to `ld.lld` from XCTC61 because macOS `ld64` cannot
  produce FreeBSD ELF. `SWIFT_USE_LINKER=lld` (set by Swift cmake) adds a short-form
  `-fuse-ld=lld`; having XCTC61/usr/bin in PATH makes `lld` resolve to `ld.lld` there.
- `CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH` — lets cmake find packages in non-sysroot
  locations (the cmake stub for zstd is on the macOS host, not in the sysroot).
- `zstd_DIR` / `zstd_LIBRARY` — the stub dir; `zstd_LIBRARY` must be the `.so` because
  `Findzstd.cmake` skips creating `zstd::libzstd_shared` if the path ends in `.a`.
- `SWIFT_SDK_FREEBSD_ARCH_aarch64_PATH` — tells Swift cmake where the FreeBSD SDK is.
  Without this, Swift cmake defaults to `/` which makes `swiftc -sdk /` look for
  `semaphore.h`, `float.h`, etc. in the macOS host filesystem (where they don't exist
  or are the wrong headers).

---

## Build script

`build-freebsd.sh` drives the full build. Run from `~/swift64-cross/`:

```sh
bash build-freebsd.sh build     # configure + compile
bash build-freebsd.sh package   # cmake --install + tar
bash build-freebsd.sh deploy    # scp + smoke test on board
bash build-freebsd.sh all       # all three steps
```

The key `build-script` flags and why they are needed:

| Flag | Reason |
|------|--------|
| `--cross-compile-hosts=freebsd-aarch64` | Enables the FreeBSD cmake sub-project |
| `--bootstrapping=hosttools` | Required since Swift 6.3+ uses macros in stdlib; uses the prebuilt 6.4 `swift-frontend` to compile stdlib Swift files |
| `--native-swift-tools-path=~/swift-host-tools` | Points to the 6.4-dev `swift-frontend` that compiles Swift sources |
| `--cross-compile-build-swift-tools false` | Sets `SWIFT_INCLUDE_TOOLS=FALSE`; prevents cmake from trying to cross-compile the Swift compiler itself for FreeBSD (which would fail because CLT swiftc 5.10 can't target FreeBSD) |
| `SWIFT_BUILD_DYNAMIC_SDK_OVERLAY=TRUE` | This flag defaults to FALSE on Darwin hosts (macOS gets overlays from its own SDK). Set TRUE to build `swiftGlibc` and the Platform overlays for FreeBSD. |
| `SWIFT_SDK_FREEBSD_ARCH_aarch64_PATH=$SYSROOT` | See toolchain file notes above. |
| `-DCMAKE_C_COMPILER=$XCTC61/usr/bin/clang` | Overrides build-script's `--host-cc=$(xcrun -f clang)` (CLT clang 15) for the FreeBSD cmake project. XCTC61 clang 21's `-print-resource-dir` returns headers that include `_Builtin_float`. |

The `--extra-cmake-options` flags are passed to cmake for ALL sub-projects (macOS LLVM
and FreeBSD Swift). The toolchain file's `CACHE ... FORCE` variables override them for
the FreeBSD project when they conflict.

---

## What happens during the build

`build-script` runs three cmake+ninja phases:

1. **earlyswiftdriver** — builds `swift-driver` as a macOS binary (needed for bootstrapping)
2. **macOS LLVM** — builds `clang`, `llvm-tblgen`, etc. as macOS arm64 binaries
3. **FreeBSD Swift** — configures and builds the stdlib as FreeBSD aarch64 ELF

The FreeBSD cmake project uses `BOOTSTRAPPING_MODE=HOSTTOOLS`: stdlib Swift sources are
compiled by `~/swift-host-tools/swift-frontend` (our 6.4-dev macOS binary) with
`-target aarch64-unknown-freebsd15 -sdk /opt/freebsd15-aarch64-sysroot`, and the
resulting `.o` files are linked by `ld.lld` from XCTC61 to produce FreeBSD ELF.

C/C++ runtime sources (core, runtime, SwiftRemoteMirror, etc.) are compiled by XCTC61
clang with `--target=aarch64-unknown-freebsd15 --sysroot=/opt/freebsd15-aarch64-sysroot`.

libdispatch is cross-compiled as an ExternalProject within the FreeBSD cmake project.

---

## Clang resource directory issue

**Problem:** Swift cmake's `symlink_clang_headers` custom command creates
`lib/swift/clang → <C compiler resource dir>`. When `CMAKE_C_COMPILER` is the CLT
clang 15, this symlinks to CLT's resource headers (`/Library/Developer/CommandLineTools/
usr/lib/clang/15.0.0/include/`) which lack `_Builtin_float` in `module.modulemap`.
When `swiftc -sdk $SYSROOT` compiles `stdlib/public/ClangOverlays/float.swift.gyb`
(which does `@_exported import _Builtin_float`), clang looks in `lib/swift/clang/include/`
and can't find the module → build failure.

**Why CLT clang gets picked:** build-script passes `--host-cc=$(xcrun -f clang)` which
sets `-DCMAKE_C_COMPILER:PATH=<CLT clang>`. Swift's CMakeLists.txt then sets
`SWIFT_PREBUILT_CLANG=TRUE` (because `SWIFT_NATIVE_CLANG_TOOLS_PATH` is non-empty), and
the `symlink_clang_headers` logic runs `${CMAKE_C_COMPILER} -print-resource-dir` → gets
the CLT path.

**Fix:** Pass `-DCMAKE_C_COMPILER=$XCTC61/usr/bin/clang` in `--extra-cmake-options`.
Since extra-cmake-options appear LAST on the cmake command line, this overrides the
earlier `-DCMAKE_C_COMPILER` set by build-script. Now `-print-resource-dir` returns
`$XCTC61/usr/lib/clang/21/` which has `_Builtin_float`. `build-freebsd.sh` also fixes
the symlink directly as a belt-and-suspenders measure after the build.

---

## Known issues and gotchas

### swiftrt.o order-dependency

cmake's generated `build.ninja` references `swiftrt.o` at the CLT's path:
```
/Library/Developer/CommandLineTools/usr/lib/swift/freebsd/aarch64/swiftrt.o
```
This path doesn't exist until the FreeBSD build produces it. When linking
`libswiftDemangle.so` (or similar), ninja reports the file missing. If this happens,
build `swiftrt.o` first and symlink it:

```sh
FBSD_BUILD=~/swift64-cross/build/Ninja-ReleaseAssert/swift-freebsd-aarch64
ninja -C "$FBSD_BUILD" lib/swift/freebsd/aarch64/swiftrt.o
sudo mkdir -p /Library/Developer/CommandLineTools/usr/lib/swift/freebsd/aarch64
sudo ln -sf "$FBSD_BUILD/lib/swift/freebsd/aarch64/swiftrt.o" \
    /Library/Developer/CommandLineTools/usr/lib/swift/freebsd/aarch64/swiftrt.o
```

If you clear the FreeBSD build directory, this symlink becomes dangling — recreate it.

### Spurious rebuilds of unittest .so files

`libswiftRuntimeUnittest.so`, `libswiftDifferentiationUnittest.so`, and similar
private test libraries rebuild on every ninja invocation due to custom command
mtime tracking. This is harmless; they are not part of the deployed stdlib.

### Proxy / network issues

The build downloads nothing, but if you have an HTTP proxy configured, it can
interfere with cmake's find_package calls. The build script clears
`HTTPS_PROXY`, `HTTP_PROXY`, and `ALL_PROXY` before invoking build-script.

### sysroot missing swift modules vs. sysroot having wrong swift modules

When rsyncing the board's filesystem, `/usr/lib/swift/freebsd/` contains the board's
prebuilt Swift 6.3.2 swiftmodules. When `swift-frontend` 6.4-dev uses
`-sdk /opt/freebsd15-aarch64-sysroot`, it finds these 6.3.2 modules and fails:
```
error: failed to build module '_Builtin_float'; this SDK is not supported by the
compiler (the SDK is built with 'Swift version 6.3.2', while this compiler is
'Swift version 6.4-dev ...')
```
The fix is to move `$SYSROOT/usr/lib/swift/freebsd/` to a backup (done in the
setup step above). The 6.4 stdlib build populates a separate output directory.

### -fuse-ld=lld vs. full path

Swift cmake sets `SWIFT_USE_LINKER=lld` for FreeBSD targets, adding `-fuse-ld=lld`
to all CXX link commands. On macOS, clang resolves `lld` by looking for `ld.lld` in
PATH. The toolchain file also adds `-fuse-ld=/full/path/ld.lld` via
`CMAKE_SHARED_LINKER_FLAGS`, but the short form appears AFTER it in the command and
wins. Fix: ensure `$XCTC61/usr/bin` is in PATH before running build-script so that
`ld.lld` is found by the short form.

---

## Output artifacts

After a successful build, `cmake --install` populates `~/swift64-cross/install-freebsd/`:

```
lib/swift/freebsd/
  aarch64/          ← per-arch libraries (linked into the parent dir)
  libswiftCore.so
  libswiftGlibc.so
  libswiftSynchronization.so
  libswift_Concurrency.so
  libdispatch.so
  libBlocksRuntime.so
  ... (22 .so files total)
  Swift.swiftmodule/aarch64-unknown-freebsd.{swiftmodule,swiftinterface,...}
  Glibc.swiftmodule/
  Synchronization.swiftmodule/
  _Builtin_float.swiftmodule/
  ... (21 .swiftmodule directories total)
```

Verify the ELF type before deploying:
```sh
file lib/swift/freebsd/libswiftCore.so
# ELF 64-bit LSB shared object, ARM aarch64, version 1 (FreeBSD), for FreeBSD 15.1
```

---

## Deploying to the board

```sh
# Build + install
bash ~/swift64-cross/build-freebsd.sh build
cmake --install ~/swift64-cross/build/Ninja-ReleaseAssert/swift-freebsd-aarch64 \
      --prefix ~/swift64-cross/install-freebsd

# Package
cd ~/swift64-cross
tar -czf swift-6.4-freebsd15-aarch64-stdlib.tar.gz -C install-freebsd .

# Copy to board (board reachable via Cloudflare Tunnel or jump host)
scp -J local@10.88.0.1 swift-6.4-freebsd15-aarch64-stdlib.tar.gz \
    swift@192.168.11.64:/home/swift/

# Install on board
ssh -J local@10.88.0.1 swift@192.168.11.64 << 'EOF'
  set -e
  sudo mkdir -p /usr/local/lib/swift/freebsd
  sudo tar -xzf ~/swift-6.4-freebsd15-aarch64-stdlib.tar.gz \
       -C /usr/local/lib/swift/freebsd \
       --strip-components=3 \
       lib/swift/freebsd
  # or overlay onto the existing 6.4 toolchain install dir:
  tar -xzf ~/swift-6.4-freebsd15-aarch64-stdlib.tar.gz \
       -C ~/swift64-install
EOF
```

---

## Rebuilding after source changes

The cmake configure only needs to run once. If you edit stdlib sources, rerun ninja:

```sh
XCTC61="$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain"
export PATH="$HOME/swift-build-venv/bin:$XCTC61/usr/bin:$PATH"
ninja -C ~/swift64-cross/build/Ninja-ReleaseAssert/swift-freebsd-aarch64 -j14 all
```

If you clear the FreeBSD build directory, rerun `bash build-freebsd.sh build` from
scratch. The macOS LLVM build (`llvm-macosx-arm64/`) is incremental and won't rebuild
unless LLVM sources changed.

---

## cmake variable reference

These are the variables that most often need adjustment when the build breaks. All are
set in `freebsd-aarch64-toolchain.cmake` or `build-freebsd.sh`'s `--extra-cmake-options`.

| Variable | Value | Why |
|----------|-------|-----|
| `SWIFT_SDK_FREEBSD_ARCH_aarch64_PATH` | `/opt/freebsd15-aarch64-sysroot` | Swift cmake defaults to `/`; with macOS root as SDK, `semaphore.h` and `float.h` are not found |
| `SWIFT_BUILD_DYNAMIC_SDK_OVERLAY` | `TRUE` | Darwin host default is FALSE; Platform/Glibc overlay never built otherwise |
| `SWIFT_INCLUDE_TOOLS` | `FALSE` (via `--cross-compile-build-swift-tools false`) | Prevents cmake from trying to build Swift compiler tools for FreeBSD target using CLT swiftc 5.10 |
| `CMAKE_C_COMPILER` | `$XCTC61/usr/bin/clang` | Overrides CLT clang 15 so `-print-resource-dir` returns clang 21 headers with `_Builtin_float` |
| `zstd_DIR` | `cmake-stubs/zstd` | LLVM imports `zstd::libzstd_shared`; FreeBSD names it `libprivatezstd`; stub provides the target |
| `zstd_LIBRARY` | `.so` (not `.a`) | `Findzstd.cmake` only creates `zstd::libzstd_shared` when the path doesn't end in `.a` |
| `CMAKE_SYSTEM_VERSION` | `"15"` | Without this, `SwiftConfigureSDK.cmake` REGEX on an empty string → configure error |
| `CMAKE_Swift_COMPILER_WORKS` | `TRUE` | CLT swiftc 5.10 self-test fails on macOS 14 ("unable to load stdlib"); skip the check |
| `CMAKE_FIND_ROOT_PATH_MODE_PACKAGE` | `BOTH` | Allow finding packages (zstd stub) on the macOS host, not only in the sysroot |

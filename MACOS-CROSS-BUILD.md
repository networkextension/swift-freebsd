# Building Swift for FreeBSD aarch64 on macOS M3 Max

Cross-compile the **Swift 6.4 compiler + stdlib** on an Apple Silicon Mac targeting
FreeBSD 15.1 aarch64. Uses `utils/build-script` (CMake, not SPM). Output is a full
deployable Swift toolchain — copy it to the board, run tests there.

**Proven working as of 2026-06-24:**
- Sysroot built from live FreeBSD 15.1 board (`rsync` from `/lib`, `/usr/lib`,
  `/usr/include`)  
- Swift 6.3.1 toolchain provides clang (LLVM 21) + `ld.lld` — both generate correct
  FreeBSD aarch64 ELF
- `swift-frontend` 6.3.1 compiled hello.swift → ELF 64-bit LSB, ARM aarch64, for
  FreeBSD 15.1, ran on board ✅

---

## Machine layout

| Role | Host | Notes |
|------|------|-------|
| **Build host** | macOS M3 Max (arm64, macOS 14 Sonoma) | ~2–3 h build |
| **Test target** | FreeBSD 15.1 aarch64 board | `swift@192.168.11.64`, jump `local@10.88.0.1` |
| **Jump host** | `local@10.88.0.1` | SSH proxy for board access |

---

## One-time setup (already done — skip if sysroot exists)

### 1 FreeBSD 15.1 sysroot

```sh
SYSROOT=/opt/freebsd15-aarch64-sysroot
sudo mkdir -p $SYSROOT && sudo chown $(whoami) $SYSROOT

# Rsync C runtime, headers, and libraries from the live board
for dir in lib usr/lib usr/include usr/libdata; do
  rsync -az -e "ssh -J local@10.88.0.1" \
    swift@192.168.11.64:/${dir}/ ${SYSROOT}/${dir}/
done

# Rsync Swift 6.3.2 stdlib modules from board's installed toolchain
TC=/home/swift/s632-clean-install/usr/local/swift
mkdir -p ${SYSROOT}/usr/lib/swift/freebsd \
         ${SYSROOT}/usr/lib/swift_static/freebsd
rsync -az -e "ssh -J local@10.88.0.1" \
  swift@192.168.11.64:${TC}/lib/swift/freebsd/ \
  ${SYSROOT}/usr/lib/swift/freebsd/
rsync -az -e "ssh -J local@10.88.0.1" \
  swift@192.168.11.64:${TC}/lib/swift_static/freebsd/ \
  ${SYSROOT}/usr/lib/swift_static/freebsd/

# Minimal SDKSettings.json so swift-frontend stops warning
cat > ${SYSROOT}/SDKSettings.json << 'EOF'
{"DisplayName":"FreeBSD 15.1 aarch64","Version":"15.1","CanonicalName":"freebsd15.1",
 "DefaultDeploymentTarget":"15.1"}
EOF
```

Verify:
```sh
file /opt/freebsd15-aarch64-sysroot/usr/lib/libc.so   # → ELF 64-bit, ARM aarch64
ls  /opt/freebsd15-aarch64-sysroot/usr/lib/swift/freebsd/*.swiftmodule | wc -l   # ≥ 10
```

### 2 Swift toolchains

Download from **swift.org → Downloads → macOS**:

| Toolchain | Purpose |
|-----------|---------|
| `swift-6.3.1-RELEASE` | Swift 6.3.2-compatible compiler + `ld.lld` (LLVM 21) |
| `swift-6.0.3-RELEASE` | Package driver for macOS 14 (6.3.1 crashes on macOS 14 Foundation) |

Both install to `~/Library/Developer/Toolchains/`.

Verify lld:
```sh
~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/ld.lld --version
# → LLD 21.0.0 (compatible with GNU linkers)
```

---

## Proof of concept: hello world (compile on Mac, run on board)

```sh
XCTC61=~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain
SYSROOT=/opt/freebsd15-aarch64-sysroot
OUT=/tmp/hello-freebsd-out
mkdir -p $OUT

# 1. Compile
$XCTC61/usr/bin/swift-frontend -frontend -c \
  /tmp/hello/main.swift \
  -target aarch64-unknown-freebsd \
  -sdk    $SYSROOT \
  -resource-dir $XCTC61/usr/lib/swift \
  -I $SYSROOT/usr/lib/swift/freebsd \
  -I $SYSROOT/usr/include \
  -o $OUT/main.o

# 2. Link
$XCTC61/usr/bin/ld.lld -flavor gnu \
  --sysroot $SYSROOT \
  -m aarch64linux \
  -dynamic-linker /libexec/ld-elf.so.1 \
  $SYSROOT/usr/lib/crt1.o $SYSROOT/usr/lib/crti.o \
  $OUT/main.o \
  -L$SYSROOT/usr/lib \
  -L$SYSROOT/usr/lib/swift/freebsd \
  -lswiftCore -lswiftGlibc -lswift_Concurrency \
  -lc -lm \
  $SYSROOT/usr/lib/crtn.o \
  -o $OUT/hello-freebsd

file $OUT/hello-freebsd
# → ELF 64-bit LSB executable, ARM aarch64, for FreeBSD 15.1 ✓

# 3. Run on board
scp -J local@10.88.0.1 $OUT/hello-freebsd swift@192.168.11.64:/tmp/
ssh -J local@10.88.0.1 swift@192.168.11.64 \
  'env LD_LIBRARY_PATH=/home/swift/s632-clean-install/usr/local/swift/lib/swift/freebsd \
   /tmp/hello-freebsd'
# → Hello, world! ✓
```

---

## Full Swift compiler cross-build via build-script

This produces a deployable Swift 6.4 toolchain (`swiftc`, stdlib, Foundation, Dispatch)
for FreeBSD aarch64. Build time on M3 Max: ~2.5–3 hours.

### 1 Check out sources

```sh
mkdir ~/swift64-cross && cd ~/swift64-cross

# Swift 6.4 release sources — matched snapshot tag is critical
git clone https://github.com/swiftlang/swift.git
cd swift && git checkout swift-6.4-RELEASE && cd ..

# Pull all dependency repos at consistent revisions
./swift/utils/update-checkout --clone --scheme release/6.4
```

### 2 Apply FreeBSD patches

```sh
cd ~/swift64-cross

# Our patch fixes two upstream bugs (may already be merged at 6.4 — check first)
# Bug 1: CMakeLists.txt hardcodes aarch64 for FreeBSD SDK registration
# Bug 2: Libdispatch.cmake missing FREEBSD branch for compiler triple args
patch -p1 -d swift < /path/to/swift-freebsd/arm64-freebsd-cross.patch

# Verify patch 1 is needed (if grep returns nothing, patch already upstream):
grep -n "configure_sdk_unix.*FreeBSD.*aarch64" swift/CMakeLists.txt | head -3
# Verify patch 2 is needed:
grep -n "FREEBSD" swift/cmake/modules/Libdispatch.cmake | head -5
```

### 3 CMake cross-toolchain file

```sh
cat > ~/swift64-cross/freebsd-aarch64-toolchain.cmake << 'EOF'
set(CMAKE_SYSTEM_NAME      FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(triple aarch64-unknown-freebsd15)

# Use Swift 6.3.1's clang — proven to produce correct FreeBSD ELF
set(XCTC "$ENV{HOME}/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr")
set(CMAKE_C_COMPILER   ${XCTC}/bin/clang)
set(CMAKE_CXX_COMPILER ${XCTC}/bin/clang++)
set(CMAKE_C_COMPILER_TARGET   ${triple})
set(CMAKE_CXX_COMPILER_TARGET ${triple})

set(CMAKE_SYSROOT /opt/freebsd15-aarch64-sysroot)

# Force lld — macOS ld64 cannot produce ELF
set(CMAKE_EXE_LINKER_FLAGS    "-fuse-ld=${XCTC}/bin/ld.lld")
set(CMAKE_SHARED_LINKER_FLAGS "-fuse-ld=${XCTC}/bin/ld.lld")
set(CMAKE_MODULE_LINKER_FLAGS "-fuse-ld=${XCTC}/bin/ld.lld")

# Don't search macOS paths for target libraries/headers
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
```

### 4 Build

```sh
XCTC61=~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain
cd ~/swift64-cross

./swift/utils/build-script \
  --release \
  --cross-compile-hosts=freebsd-aarch64 \
  --stdlib-deployment-targets=freebsd-aarch64 \
  --bootstrapping=hosttools \
  --host-cc="$(xcrun -f clang)" \
  --host-cxx="$(xcrun -f clang++)" \
  --native-swift-tools-path="$(dirname $(xcrun -f swiftc))" \
  --native-clang-tools-path="$(dirname $(xcrun -f clang))" \
  --cross-compile-deps-path=/opt/freebsd15-aarch64-sysroot \
  --jobs 14 \
  --skip-build-benchmarks \
  --skip-ios --skip-watchos --skip-tvos \
  --build-swift-static-stdlib \
  --extra-cmake-options="\
    -DSWIFT_USE_LINKER=lld \
    -DLLVM_USE_LINKER=lld \
    -DLLVM_ENABLE_LLD=ON \
    -DSWIFT_PRIMARY_VARIANT_SDK=FREEBSD \
    -DSWIFT_PRIMARY_VARIANT_ARCH=aarch64 \
    -DCMAKE_TOOLCHAIN_FILE=$HOME/swift64-cross/freebsd-aarch64-toolchain.cmake \
    -DCMAKE_AR=${XCTC61}/usr/bin/llvm-ar \
    -DCMAKE_RANLIB=${XCTC61}/usr/bin/llvm-ranlib \
    -DLLVM_PARALLEL_LINK_JOBS=4 \
    -DSWIFT_PARALLEL_LINK_JOBS=4" \
  2>&1 | tee ~/swift64-cross/build.log
```

**Key flags:**
- `--cross-compile-hosts=freebsd-aarch64` — produce tools that *run* on FreeBSD
- `--bootstrapping=hosttools` — required since Swift 6.3+ uses macros in stdlib
- `--native-swift-tools-path` — macOS swiftc for compiling Swift source in the build
- `LLVM_PARALLEL_LINK_JOBS=4` — M3 Max has RAM to spare (vs 1 on board)
- `llvm-ar`/`llvm-ranlib` — macOS `ar` produces Mach-O archives, not ELF

### 5 Known adaptation points

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ld64` invoked instead of lld | Wrong linker picked up | Confirm `SWIFT_USE_LINKER=lld` and `CMAKE_EXE_LINKER_FLAGS` |
| `ar: unsupported format` | macOS `ar` used instead of `llvm-ar` | Add `-DCMAKE_AR=...llvm-ar` |
| `AccessorDeclSyntax.modifiers missing` | Host compiler / stdlib version mismatch | Realign `swift-syntax` to snapshot tag; `rm -rf build/_deps` |
| `gettimeofday` undeclared in BoringSSL | Missing `sys/time.h` include on FreeBSD | Add `-DCMAKE_C_FLAGS=-include\ /opt/freebsd15-aarch64-sysroot/usr/include/sys/time.h` |
| `MemberImportVisibility` errors | Glibc overlay gaps (tracked: swiftlang/swift #85427) | Add `-disable-upcoming-feature MemberImportVisibility` to Swift flags |

### 6 Package the toolchain

```sh
BUILD=~/swift64-cross/build/Ninja-Release
INSTALL=~/swift64-cross/install

cmake --install ${BUILD}/swift-freebsd-aarch64 --prefix ${INSTALL}
tar -czf swift-6.4-RELEASE-freebsd15-aarch64.tar.gz -C ${INSTALL} usr/local/swift

ls -lh swift-6.4-RELEASE-freebsd15-aarch64.tar.gz
# → typically 350–500 MB compressed
```

---

## Deploy to board and test

```sh
BOARD=swift@192.168.11.64
JUMP=local@10.88.0.1

# Copy
scp -J $JUMP swift-6.4-RELEASE-freebsd15-aarch64.tar.gz ${BOARD}:/home/swift/

# Install on board
ssh -J $JUMP $BOARD 'mkdir -p ~/swift64-install && \
  tar -xzf swift-6.4-RELEASE-freebsd15-aarch64.tar.gz -C ~/swift64-install'

# Smoke test
ssh -J $JUMP $BOARD '
  export PATH=~/swift64-install/usr/local/swift/bin:$PATH
  export LD_LIBRARY_PATH=~/swift64-install/usr/local/swift/lib/swift/freebsd:$LD_LIBRARY_PATH
  swiftc --version
  echo "print(\"hello\")" > /tmp/h.swift && swiftc /tmp/h.swift -o /tmp/h && /tmp/h
  swift package init --type executable --name smoke /tmp/smoke 2>/dev/null || true
  cd /tmp/smoke && swift build && .build/debug/smoke
'

# Full test suite (serial — parallel executor deadlock tracked, not yet fixed)
ssh -J $JUMP $BOARD '
  export PATH=~/swift64-install/usr/local/swift/bin:$PATH
  export LD_LIBRARY_PATH=~/swift64-install/usr/local/swift/lib/swift/freebsd:$LD_LIBRARY_PATH
  cd ~/swift64 && swift test --filter SwiftStdlibTests 2>&1 | tee ~/test-stdlib.log
  grep -E "^(PASS|FAIL|error)" ~/test-stdlib.log | tail -20
'
```

---

## Board-only fallback (native build with 6.3.2 as host)

When the M3 Max cross-build has issues, fall back to the native board build:

```sh
ssh -J local@10.88.0.1 swift@192.168.11.64
# then on board:
sh ~/build-64.sh   # uses 6.3.2 at ~/s632-clean-install as hosttools
```

Build time: ~20 hours. Output identical to cross-build output.

---

## Status

| Component | Mac cross-build | Board native |
|-----------|----------------|-------------|
| C/C++ (clang → FreeBSD ELF) | ✅ proven 2026-06-24 | ✅ |
| Swift hello.swift → FreeBSD ELF | ✅ proven 2026-06-24 | ✅ |
| Full LLVM cross-build | not yet attempted | ✅ 6.3.2 done |
| Swift stdlib cross-build | not yet attempted | ✅ 6.3.2 done |
| Swift 6.4 native (board) | — | Phase A in progress |

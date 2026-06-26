#!/usr/bin/env bash
# Build Swift 6.4 for FreeBSD aarch64 on macOS M3 Max (macOS 14 Sonoma).
# Prerequisites: run update-checkout --scheme release/6.4.x first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
XCTC61="$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain"
SYSROOT="${SYSROOT:-/opt/freebsd15-aarch64-sysroot}"
JOBS="${JOBS:-14}"
LINK_JOBS="${LINK_JOBS:-4}"   # M3 Max has 128 GB — go parallel
CONFIG="${CONFIG:-Release}"

# cmake + ninja from venv; XCTC61/usr/bin so clang finds ld.lld when SWIFT_USE_LINKER=lld
export PATH="$HOME/swift-build-venv/bin:$XCTC61/usr/bin:$PATH"

die() { echo "error: $*" >&2; exit 1; }

check() {
    [ -x "$XCTC61/usr/bin/swift-frontend" ] || die "Swift 6.3.1 toolchain missing"
    [ -x "$XCTC61/usr/bin/ld.lld" ]         || die "ld.lld missing in Swift 6.3.1 toolchain"
    [ -d "$SYSROOT/usr/include" ]            || die "sysroot missing — rsync from board first"
    which cmake ninja >/dev/null 2>&1        || die "cmake/ninja missing — activate swift-build-venv"
    cmake --version | head -1
    ninja --version
    "$XCTC61/usr/bin/ld.lld" --version | head -1
}

apply_patches() {
    echo "==> Checking FreeBSD patches..."
    cd "$ROOT/swift"
    if git apply --check --reverse "$ROOT/../swift-freebsd/arm64-freebsd-cross.patch" 2>/dev/null; then
        echo "    Patch already applied — skipping"
    elif git apply --check "$ROOT/../swift-freebsd/arm64-freebsd-cross.patch" 2>/dev/null; then
        git apply "$ROOT/../swift-freebsd/arm64-freebsd-cross.patch"
        echo "    Applied arm64-freebsd-cross.patch"
    else
        echo "    WARNING: patch did not apply cleanly — manual inspection needed"
        git apply "$ROOT/../swift-freebsd/arm64-freebsd-cross.patch" 2>&1 || true
    fi
    cd "$ROOT"
}

run_build() {
    echo "==> Building Swift for FreeBSD aarch64..."
    # build-script uses env vars, not --source-root/--build-dir CLI flags
    # SKIP_XCODE_VERSION_CHECK: CLT-only install (no /Applications/Xcode.app)
    export SWIFT_SOURCE_ROOT="$ROOT"
    export SWIFT_BUILD_ROOT="$ROOT/build"
    export SKIP_XCODE_VERSION_CHECK=1
    # Toolchain file must NOT go in --extra-cmake-options (that applies to the
    # macOS host LLVM build too, and our ld.lld rejects macOS link flags).
    # Instead pass via FREEBSD_USE_TOOLCHAIN_FILE, handled in build-script-impl.
    export FREEBSD_USE_TOOLCHAIN_FILE="$ROOT/freebsd-aarch64-toolchain.cmake"
    HTTPS_PROXY="" HTTP_PROXY="" ALL_PROXY="" \
    "$ROOT/swift/utils/build-script" \
        --"$(echo $CONFIG | tr '[:upper:]' '[:lower:]')" \
        --cross-compile-hosts=freebsd-aarch64 \
        --bootstrapping=hosttools \
        --host-cc="$(xcrun -f clang)" \
        --host-cxx="$(xcrun -f clang++)" \
        --native-swift-tools-path="$HOME/swift-host-tools" \
        --native-clang-tools-path="$(dirname "$(xcrun -f clang)")" \
        --cross-compile-deps-path="$SYSROOT" \
        --jobs "$JOBS" \
        --skip-build-benchmarks \
        --skip-ios --skip-watchos --skip-tvos \
        --cross-compile-build-swift-tools false \
        --extra-cmake-options="\
-DLLVM_PARALLEL_LINK_JOBS=$LINK_JOBS \
-DSWIFT_PARALLEL_LINK_JOBS=$LINK_JOBS \
-DSWIFT_NATIVE_SWIFT_TOOLS_PATH=$HOME/swift-host-tools \
-DSWIFT_NATIVE_CLANG_TOOLS_PATH=$HOME/swift-host-tools \
-DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=TRUE \
-DSWIFT_SDK_FREEBSD_ARCH_aarch64_PATH=$SYSROOT \
-DCMAKE_C_COMPILER=$XCTC61/usr/bin/clang \
-DCMAKE_CXX_COMPILER=$XCTC61/usr/bin/clang++" \
        2>&1 | tee "$ROOT/build.log"

    # build-script passes --host-cc=$(xcrun -f clang) which sets CMAKE_C_COMPILER
    # to the CLT clang 15. Our extra-cmake-options above override it to XCTC61
    # clang 21, so cmake's SwiftShims symlink_clang_headers step uses clang 21's
    # resource directory (which has _Builtin_float in module.modulemap).
    # Belt-and-suspenders: also fix the symlink directly in case cmake re-runs.
    local fbsd_lib="$ROOT/build/Ninja-ReleaseAssert/swift-freebsd-aarch64/lib"
    local clang21="$ROOT/build/Ninja-ReleaseAssert/llvm-freebsd-aarch64/lib/clang/21"
    for d in "$fbsd_lib/swift/clang" "$fbsd_lib/swift_static/clang"; do
        if [ -L "$d" ] && [ "$(readlink "$d")" != "$clang21" ]; then
            echo "==> Fixing clang headers symlink: $d"
            ln -sf "$clang21" "$d"
        fi
    done
}

package() {
    local build_dir="$ROOT/build/Ninja-$CONFIG"
    local install_dir="$ROOT/install"
    echo "==> Packaging..."
    cmake --install "$build_dir/swift-freebsd-aarch64" --prefix "$install_dir"
    tar -czf "$ROOT/swift-6.4-freebsd15-aarch64.tar.gz" -C "$install_dir" usr/local/swift
    ls -lh "$ROOT/swift-6.4-freebsd15-aarch64.tar.gz"
    echo "==> Done. Deploy with:"
    echo "    scp -J local@10.88.0.1 $ROOT/swift-6.4-freebsd15-aarch64.tar.gz swift@192.168.11.64:/home/swift/"
}

deploy_and_test() {
    local tarball="$ROOT/swift-6.4-freebsd15-aarch64.tar.gz"
    [ -f "$tarball" ] || die "tarball not found — run: $0 package"
    echo "==> Deploying to board..."
    scp -J local@10.88.0.1 "$tarball" swift@192.168.11.64:/home/swift/
    ssh -J local@10.88.0.1 swift@192.168.11.64 '
        set -e
        mkdir -p ~/swift64-install
        tar -xzf ~/swift-6.4-freebsd15-aarch64.tar.gz -C ~/swift64-install
        export PATH=~/swift64-install/usr/local/swift/bin:$PATH
        export LD_LIBRARY_PATH=~/swift64-install/usr/local/swift/lib/swift/freebsd:$LD_LIBRARY_PATH
        swiftc --version
        echo "print(\"hello FreeBSD\")" > /tmp/h.swift
        swiftc /tmp/h.swift -o /tmp/h && /tmp/h
        echo "==> Smoke test PASSED"
    '
}

CMD="${1:-build}"
case "$CMD" in
    check)   check ;;
    patch)   check; apply_patches ;;
    build)   check; apply_patches; run_build ;;
    package) package ;;
    deploy)  deploy_and_test ;;
    all)     check; apply_patches; run_build; package; deploy_and_test ;;
    *)       echo "usage: $0 [check|patch|build|package|deploy|all]"; exit 1 ;;
esac

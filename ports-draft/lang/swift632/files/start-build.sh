# Driven by the port's do-build target.
#
# Swift 6.3 CANNOT self-bootstrap on FreeBSD (its stdlib uses macros => SWIFT_BUILD_SWIFT_SYNTAX
# => CMake forces --bootstrapping=hosttools; swift/CMakeLists.txt ~L1041). hosttools needs a
# prebuilt, VERSION-MATCHED (6.3.2) host Swift toolchain: in hosttools mode the host compiles
# the compiler's Swift sources AND the corelibs products, stamping their .swiftmodule with the
# host version. With a 6.3.2 host the whole tree is coherent in ONE build-script run; with a
# mismatched host the corelibs (Foundation/Dispatch/XCTest) get stamped wrong and the just-built
# 6.3.2 compiler rejects them. See ../../BUILD-NOTES-6.3.md and issue swiftlang/swift#89943.
#
# SWIFT_BOOTSTRAP_TOOLCHAIN must point at the extracted bootstrap toolchain's <prefix> (the dir
# holding bin/swiftc + lib/swift) — provided by BUILD_DEPENDS=lang/swift632-bootstrap (a stage0
# distfile, the v0.4.0-6.3.2 GitHub release), like lang/rust ships stage0.
#
# Args (from the Makefile do-build):
#   $1 swift_project_dir     (WRKSRC)
#   $2 swift_install_destdir (EarlyStageDir DESTDIR)
#   $3 swift_install_prefix  (${PREFIX}/swift632)
#   $4 clang_module_cache_path

set -e

swift_project_dir=$1
swift_install_destdir=$2
swift_install_prefix=$3
clang_module_cache_path=$4

: "${SWIFT_BOOTSTRAP_TOOLCHAIN:?set SWIFT_BOOTSTRAP_TOOLCHAIN to the 6.3.2 bootstrap toolchain prefix}"
: "${SWIFT_ARCH:=aarch64}"
TC="${SWIFT_BOOTSTRAP_TOOLCHAIN}"

# base-system ld/ar/ranlib first; then the bootstrap toolchain's swiftc on PATH.
export PATH="$TC/bin:/sbin:/bin:/usr/sbin:/usr/bin:${PATH}"
# the bootstrap swiftc is Swift-in-Swift; it needs its own runtime to run.
export LD_LIBRARY_PATH="$TC/lib/swift/freebsd/${SWIFT_ARCH}:$TC/lib/swift/host/compiler:$TC/lib/swift/host"
export SWIFTC="$TC/bin/swiftc"
export CLANG_MODULE_CACHE_PATH=${clang_module_cache_path}

if [ "${CCACHE_ENABLED}" = yes ] ; then
	ccache_fragment="--cmake-c-launcher ${CCACHE_BIN} --cmake-cxx-launcher ${CCACHE_BIN}"
else
	ccache_fragment=
fi

if [ -n "${MAKE_JOBS_NUMBER}" ] ; then
	jobs_fragment="--jobs ${MAKE_JOBS_NUMBER}"
else
	jobs_fragment=
fi

# llvm-targets: build the host arch only (X86 also pulled for amd64 cross bits).
case "${SWIFT_ARCH}" in
aarch64)	llvm_targets='AArch64;X86' ;;
x86_64)		llvm_targets='X86;AArch64' ;;
*)		llvm_targets='AArch64;X86' ;;
esac

cd "${swift_project_dir}/swift"
utils/build-script \
	--release \
	--assertions \
	--bootstrapping=hosttools \
	--host-cc /usr/bin/clang \
	--host-cxx /usr/bin/clang++ \
	${ccache_fragment} \
	${jobs_fragment} \
	--llvm-targets-to-build "${llvm_targets}" \
	--skip-early-swift-driver \
	--libdispatch true \
	--foundation true \
	--xctest true \
	--swiftpm true \
	--llbuild true \
	--swift-driver true \
	--swift-testing true \
	--swift-testing-macros true \
	--extra-cmake-options="-DSWIFT_USE_LINKER=lld" \
	--extra-cmake-options="-DLLVM_USE_LINKER=lld" \
	--extra-cmake-options="-DSWIFT_BUILD_SWIFT_SYNTAX=ON" \
	--extra-cmake-options="-DCMAKE_Swift_COMPILER=$TC/bin/swiftc" \
	`# Serialize links: a small-RAM/low-swap box wedges on parallel Swift/LLVM links.` \
	`# Harmless (slower) on big builders; drop on a well-resourced host if desired.` \
	--extra-cmake-options="-DLLVM_PARALLEL_LINK_JOBS=1" \
	--extra-cmake-options="-DSWIFT_PARALLEL_LINK_JOBS=1" \
	--llvm-max-parallel-lto-link-jobs 1 \
	--swift-tools-max-parallel-lto-link-jobs 1 \
	--install-destdir "${swift_install_destdir}" \
	--install-prefix "${swift_install_prefix}" \
	--install-all \
	--verbose-build true

# ----------------------------------------------------------------------------------------
# FreeBSD-specific gotchas observed while bringing this up (only bite with a NON-matched or
# already-complete host; a clean matched-6.3.2 single run above avoids them — kept for
# maintainers, see BUILD-NOTES-6.3.md for the full diagnoses):
#
#  * If corelibs .swiftmodule come out stamped with the wrong version: the host is not 6.3.2,
#    OR --native-swift-tools-path was passed pointing at the host (don't) — let the freshly
#    built compiler build the stdlib/corelibs.
#  * "redefinition of module 'Dispatch'" while building Foundation: only happens when the HOST
#    toolchain already ships the dispatch clang module AND the in-tree libdispatch -I is added
#    (i.e. when rebuilding products against a complete toolchain). A lean matched host avoids it.
#  * SwiftPM via build-script ok in one run; standalone it bootstraps with
#    swiftpm/Utilities/bootstrap and needs LLBuild_DIR at the bootstrap's own llbuild build dir.
#  * swift-testing's @Test/#expect macros require --swift-testing-macros true (separate flag),
#    else _InternalTestSupport fails: "plugin for module 'TestingMacros' not found".
# ----------------------------------------------------------------------------------------

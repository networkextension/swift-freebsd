# Driven by the port's do-build target.
#
# IMPORTANT (verified building 6.3.2 on FreeBSD aarch64, 2026-06): unlike swift510 (5.10),
# Swift 6.3 CANNOT self-bootstrap on FreeBSD. Its stdlib uses macros, which force
# SWIFT_BUILD_SWIFT_SYNTAX=ON, which CMake hard-restricts to --bootstrapping=hosttools on
# FreeBSD/Linux (swift/CMakeLists.txt ~L1041). hosttools needs a PREBUILT, VERSION-MATCHED
# host Swift toolchain (the host compiler builds the stdlib and stamps it with the host's
# version; a mismatched host => "module compiled with Swift 6.3 cannot be imported by the
# Swift 6.3.2 compiler"). So the port must provide a 6.3.x bootstrap toolchain.
# See ../../BUILD-NOTES-6.3.md.
#
# SWIFT_BOOTSTRAP_TOOLCHAIN must point at the extracted bootstrap toolchain's <prefix>/usr
# (the dir containing bin/swiftc + lib/swift). In a real port this comes from a
# BUILD_DEPENDS / distfile (like lang/rust's stage0), not from system clang.
#
# Args (passed by the Makefile do-build):
#   $1 swift_project_dir   (WRKSRC)
#   $2 swift_install_destdir (EarlyStageDir DESTDIR)
#   $3 swift_install_prefix  (${PREFIX}/swift)
#   $4 clang_module_cache_path

swift_project_dir=$1
swift_install_destdir=$2
swift_install_prefix=$3
clang_module_cache_path=$4

: "${SWIFT_BOOTSTRAP_TOOLCHAIN:?set SWIFT_BOOTSTRAP_TOOLCHAIN to the bootstrap toolchain's <prefix>/usr}"
TC="${SWIFT_BOOTSTRAP_TOOLCHAIN}"

# base-system ld/ar/ranlib first; then the bootstrap toolchain's swiftc on PATH
export PATH="$TC/bin:/sbin:/bin:/usr/sbin:/usr/bin:${PATH}"
# the bootstrap swiftc is Swift-in-Swift; it needs its own runtime to run
export LD_LIBRARY_PATH="$TC/lib/swift/freebsd/aarch64:$TC/lib/swift/host/compiler:$TC/lib/swift/host"
export SWIFTC="$TC/bin/swiftc"
export CLANG_MODULE_CACHE_PATH=${clang_module_cache_path}

if [ ${CCACHE_ENABLED} = yes ] ; then
	ccache_fragment="--cmake-c-launcher ${CCACHE_BIN} --cmake-cxx-launcher ${CCACHE_BIN}"
else
	ccache_fragment=
fi

if [ -n "${MAKE_JOBS_NUMBER}" ] ; then
	jobs_fragment="--jobs ${MAKE_JOBS_NUMBER}"
else
	jobs_fragment=
fi

cd ${swift_project_dir}/swift &&
utils/build-script \
--release \
--assertions \
--bootstrapping=hosttools \
--host-cc /usr/bin/clang \
--host-cxx /usr/bin/clang++ \
${ccache_fragment} \
${jobs_fragment} \
--llvm-targets-to-build 'AArch64;X86' \
--skip-early-swift-driver \
--libdispatch true \
--foundation true \
--xctest true \
--swiftpm true \
--llbuild true \
--swiftsyntax true \
--swift-driver true \
--swift-testing true \
--extra-cmake-options="-DSWIFT_USE_LINKER=lld" \
--extra-cmake-options="-DLLVM_USE_LINKER=lld" \
--extra-cmake-options="-DSWIFT_BUILD_SWIFT_SYNTAX=ON" \
--extra-cmake-options="-DCMAKE_Swift_COMPILER=$TC/bin/swiftc" \
`# serialize links: small-board RAM/swap wedges on parallel links (see BUILD-NOTES-6.3.md)` \
--extra-cmake-options="-DLLVM_PARALLEL_LINK_JOBS=1" \
--extra-cmake-options="-DSWIFT_PARALLEL_LINK_JOBS=1" \
--llvm-max-parallel-lto-link-jobs 1 \
--swift-tools-max-parallel-lto-link-jobs 1 \
--install-destdir ${swift_install_destdir} \
--install-prefix ${swift_install_prefix} \
--install-all true \
--verbose-build true

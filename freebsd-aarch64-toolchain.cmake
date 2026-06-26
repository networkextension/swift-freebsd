set(CMAKE_SYSTEM_NAME      FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(triple aarch64-unknown-freebsd15)

# Swift 6.3.1 toolchain: proven to emit correct FreeBSD ELF on macOS 14
set(XCTC "$ENV{HOME}/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr")

set(CMAKE_C_COMPILER          ${XCTC}/bin/clang)
set(CMAKE_CXX_COMPILER        ${XCTC}/bin/clang++)
set(CMAKE_C_COMPILER_TARGET   ${triple})
set(CMAKE_CXX_COMPILER_TARGET ${triple})
set(CMAKE_ASM_COMPILER        ${XCTC}/bin/clang)
set(CMAKE_ASM_COMPILER_TARGET ${triple})

set(CMAKE_AR     ${XCTC}/bin/llvm-ar)
set(CMAKE_RANLIB ${XCTC}/bin/llvm-ranlib)
set(CMAKE_NM     ${XCTC}/bin/llvm-nm)

set(CMAKE_SYSROOT /opt/freebsd15-aarch64-sysroot)

# Force lld — macOS ld64 cannot produce FreeBSD ELF
set(CMAKE_EXE_LINKER_FLAGS    "-fuse-ld=${XCTC}/bin/ld.lld" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "-fuse-ld=${XCTC}/bin/ld.lld" CACHE STRING "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "-fuse-ld=${XCTC}/bin/ld.lld" CACHE STRING "" FORCE)

# Don't let CMake pull macOS libraries/headers into the FreeBSD build
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# CLT swiftc 5.10 cannot self-test on macOS 14 ("unable to load stdlib").
# The FreeBSD build uses custom cmake commands (SwiftSource.cmake) for Swift
# compilation, not cmake-native Swift; skip the test.
set(CMAKE_Swift_COMPILER_WORKS TRUE CACHE INTERNAL "")

# ZLIB cross-compile: point cmake at the FreeBSD sysroot's zlib directly.
# FindZLIB fails with CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY because it
# cannot dlopen the FreeBSD ELF on macOS.  Pre-populate the cache vars.
set(ZLIB_LIBRARY /opt/freebsd15-aarch64-sysroot/usr/lib/libz.a CACHE FILEPATH "" FORCE)
set(ZLIB_INCLUDE_DIR /opt/freebsd15-aarch64-sysroot/usr/include CACHE PATH "" FORCE)

# FreeBSD system version — needed by SwiftConfigureSDK.cmake:436 REGEX REPLACE
# which fails with an empty CMAKE_SYSTEM_VERSION during cross-compile configure.
set(CMAKE_SYSTEM_VERSION "15" CACHE STRING "" FORCE)

# LibXml2 and LibEdit: LLVM_ENABLE_LIBXML2/LIBEDIT are ON in the FreeBSD LLVM
# config, but libxml2 is not in the FreeBSD sysroot (it's a port).  The swift
# tools are macOS-host binaries, so point cmake at the macOS SDK stubs.
set(LIBXML2_LIBRARY /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib/libxml2.tbd
    CACHE FILEPATH "" FORCE)
set(LIBXML2_INCLUDE_DIR /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/libxml2
    CACHE PATH "" FORCE)
set(LIBEDIT_LIBRARY /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib/libedit.tbd
    CACHE FILEPATH "" FORCE)
set(LIBEDIT_INCLUDE_DIR /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include
    CACHE PATH "" FORCE)
# Swift's FindLibEdit.cmake uses LibEdit_LIBRARIES / LibEdit_INCLUDE_DIRS.
# The FreeBSD sysroot has libedit; set the exact variable names FindLibEdit checks.
set(LibEdit_LIBRARIES /opt/freebsd15-aarch64-sysroot/usr/lib/libedit.a
    CACHE FILEPATH "" FORCE)
set(LibEdit_INCLUDE_DIRS /opt/freebsd15-aarch64-sysroot/usr/include
    CACHE PATH "" FORCE)

# UUID: on FreeBSD, uuid_*() functions are in libc — no separate libuuid package.
# Point cmake's FindUUID at libc.so (the linker stub) + the sysroot includes.
set(UUID_INCLUDE_DIR /opt/freebsd15-aarch64-sysroot/usr/include
    CACHE PATH "" FORCE)
set(UUID_LIBRARY /opt/freebsd15-aarch64-sysroot/usr/lib/libc.so
    CACHE FILEPATH "" FORCE)

# EXECINFO: FreeBSD has backtrace() in libexecinfo (unlike Linux where it's in libc).
# find_library() may not find it through the sysroot with ONLY mode; pre-populate.
set(EXECINFO_LIBRARY /opt/freebsd15-aarch64-sysroot/usr/lib/libexecinfo.a
    CACHE FILEPATH "" FORCE)

# ZSTD: the FreeBSD LLVM was built with macOS homebrew zstd.
# LLVMExports.cmake exports zstd::libzstd_shared as an INTERFACE dependency.
# Tell cmake where the zstd config package lives so the target is imported.
set(zstd_DIR /Users/local/swift64-cross/cmake-stubs/zstd
    CACHE PATH "" FORCE)

# Pre-populate zstd_LIBRARY so FindZstd.cmake short-circuits.
# Must use the .so (shared) so Findzstd.cmake creates zstd::libzstd_shared;
# if set to .a, the module treats it as static-only and skips that target.
# libzstd.so is a symlink → libprivatezstd.so.5 (identical ZSTD_* symbols).
set(zstd_LIBRARY /opt/freebsd15-aarch64-sysroot/usr/lib/libzstd.so
    CACHE FILEPATH "" FORCE)
set(zstd_STATIC_LIBRARY /opt/freebsd15-aarch64-sysroot/usr/lib/libzstd.a
    CACHE FILEPATH "" FORCE)
set(zstd_INCLUDE_DIR /opt/freebsd15-aarch64-sysroot/usr/include
    CACHE PATH "" FORCE)

# Tell Swift's cmake where the FreeBSD SDK lives so that stdlib compilations use
# -sdk /opt/... instead of -sdk /.  With -sdk /, swiftc looks for FreeBSD system
# headers (semaphore.h, float.h, etc.) in the macOS host filesystem where they
# either don't exist or are the wrong ones.
set(SWIFT_SDK_FREEBSD_ARCH_aarch64_PATH /opt/freebsd15-aarch64-sysroot
    CACHE STRING "" FORCE)

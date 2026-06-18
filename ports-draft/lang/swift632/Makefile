# Versioned port for Swift 6.3.2-RELEASE with aarch64 + amd64 support.
# Derived from lang/swift510 (jgopensource@proton.me). The 6.3.2 build was verified
# end-to-end on FreeBSD 15.1/aarch64; see ../../BUILD-NOTES-6.3.md and
# https://github.com/networkextension/swift-freebsd/releases/tag/v0.4.0-6.3.2
#
# Unlike lang/swift510 (5.10 self-bootstraps from system clang), Swift 6.3's stdlib uses
# macros => SWIFT_BUILD_SWIFT_SYNTAX=ON => CMake forces --bootstrapping=hosttools on
# FreeBSD/Linux. hosttools needs a prebuilt Swift host toolchain. Critically the host must be
# the SAME version (6.3.2): in hosttools mode the host compiler also builds the corelibs
# products (Foundation/Dispatch/XCTest) and stamps their .swiftmodule with the host's
# version, so a 6.3.2-matched host makes the whole tree coherent in a single build-script
# run (a mismatched host => "module compiled with Swift 6.3 cannot be imported by the
# Swift 6.3.2 compiler"). The v0.4.0-6.3.2 toolchain (this port's own prior build) is the seed.

PORTNAME=	swift
DISTVERSION=	6.3.2
PORTREVISION=	0
CATEGORIES=	lang
PKGNAMESUFFIX=	632
DIST_SUBDIR=	swift

MAINTAINER=	jgopensource@proton.me
COMMENT=	Swift programming language (6.3.2-RELEASE)
WWW=		https://www.swift.org/

LICENSE=	APACHE20
LICENSE_FILE=	${WRKSRC}/swift/LICENSE.txt

# aarch64 verified end-to-end on 15.1; amd64 carried from lang/swift510.
ONLY_FOR_ARCHS=	aarch64 amd64

value_for_aarch64=	aarch64
value_for_amd64=	x86_64
swift_arch=		${value_for_${ARCH}}

# A version-matched 6.3.2 host toolchain is required (see header). Like lang/rust's stage0,
# fetch a prebuilt 6.3.2 "stage0" toolchain as an extra distfile and use it from WRKDIR at
# build time (it is NOT installed). The seed is this port's own prior build (v0.4.0-6.3.2).
# NOTE: a prebuilt seed currently exists for aarch64 only; an amd64 seed must be produced
# (cross-built on x86, or once an amd64 6.3.2 is published) before BOOTSTRAP works there.
BOOTSTRAP_TAG=		v0.4.0-6.3.2
BOOTSTRAP_OSREL=	15	# the OS major the seed was built on; 14.x users: see compat note
BOOTSTRAP_FILE=		swift-6.3.2-RELEASE-freebsd${BOOTSTRAP_OSREL}-${swift_arch}.tar.zst
SWIFT_BOOTSTRAP_TOOLCHAIN=	${WRKDIR}/swift632-bootstrap/usr/local/swift

MASTER_SITES+=	https://github.com/networkextension/swift-freebsd/releases/download/${BOOTSTRAP_TAG}/:bootstrap
DISTFILES+=	${BOOTSTRAP_FILE}:bootstrap
EXTRACT_ONLY=	${DISTFILES:N*\:bootstrap:C/:.*//}

BUILD_DEPENDS=	bash:shells/bash \
		cmake-core>=3.19.6:devel/cmake-core \
		zstd:archivers/zstd
LIB_DEPENDS=	libcurl.so:ftp/curl \
		libicuuc.so:devel/icu \
		libuuid.so:misc/libuuid \
		libxml2.so:textproc/libxml2 \
		libzstd.so:archivers/zstd

USES=		libedit ninja:build perl5 pkgconfig python:3.9+ \
		shebangfix sqlite:3
USE_PERL5=	build
USE_GITHUB=	nodefault

SUB_FILES=	pkg-message

# Most swiftlang repos share this tag (verified present across swift, swift-build,
# swift-foundation, swift-foundation-icu, swift-testing, swift-corelibs-*, swift-syntax,
# swift-package-manager, ...). apple/* + swift-toolchain-sqlite use their own semver tags
# from swift-6.3.2's update_checkout/update-checkout-config.json (release/6.3 scheme).
tag=		swift-${DISTVERSION}-RELEASE

GH_TUPLE=\
	swiftlang:indexstore-db:${tag}:indexstore_db/indexstore-db \
	swiftlang:llvm-project:${tag}:llvm_project/llvm-project \
	swiftlang:sourcekit-lsp:${tag}:sourcekit_lsp/sourcekit-lsp \
	swiftlang:swift:${tag}:swift/swift \
	swiftlang:swift-cmark:${tag}:swift_cmark/cmark \
	swiftlang:swift-build:${tag}:swift_build/swift-build \
	swiftlang:swift-corelibs-foundation:${tag}:swift_corelibs_foundation/swift-corelibs-foundation \
	swiftlang:swift-corelibs-libdispatch:${tag}:swift_corelibs_libdispatch/swift-corelibs-libdispatch \
	swiftlang:swift-corelibs-xctest:${tag}:swift_corelibs_xctest/swift-corelibs-xctest \
	swiftlang:swift-docc:${tag}:swift_docc/swift-docc \
	swiftlang:swift-docc-symbolkit:${tag}:swift_docc_symbolkit/swift-docc-symbolkit \
	swiftlang:swift-driver:${tag}:swift_driver/swift-driver \
	swiftlang:swift-experimental-string-processing:${tag}:swift_experimental_string_processing/swift-experimental-string-processing \
	swiftlang:swift-foundation:${tag}:swift_foundation/swift-foundation \
	swiftlang:swift-foundation-icu:${tag}:swift_foundation_icu/swift-foundation-icu \
	swiftlang:swift-format:${tag}:swift_format/swift-format \
	swiftlang:swift-llbuild:${tag}:llbuild/llbuild \
	swiftlang:swift-markdown:${tag}:swift_markdown/swift-markdown \
	swiftlang:swift-package-manager:${tag}:swiftpm/swiftpm \
	swiftlang:swift-syntax:${tag}:swift_syntax/swift-syntax \
	swiftlang:swift-testing:${tag}:swift_testing/swift-testing \
	swiftlang:swift-tools-support-core:${tag}:swift_tools_support_core/swift-tools-support-core
GH_TUPLE+=\
	swiftlang:swift-toolchain-sqlite:1.0.7:swift_toolchain_sqlite/swift-toolchain-sqlite
GH_TUPLE+=\
	apple:swift-argument-parser:1.6.1:swift_argument_parser/swift-argument-parser \
	apple:swift-asn1:1.3.2:swift_asn1/swift-asn1 \
	apple:swift-certificates:1.10.1:swift_certificates/swift-certificates \
	apple:swift-collections:1.1.6:swift_collections/swift-collections \
	apple:swift-crypto:3.12.5:swift_crypto/swift-crypto \
	apple:swift-nio:2.65.0:swift_nio/swift-nio \
	apple:swift-system:1.5.0:swift_system/swift-system

SHEBANG_FILES=\
	swift/utils/api_checker/sdk-module-lists/infer-imports.py \
	swift/utils/api_checker/swift-api-checker.py \
	swift/utils/build-script \
	swift/utils/swift-api-dump.py \
	swift-driver/Utilities/build-script-helper.py \
	swiftpm/Utilities/bootstrap

# Distinct install prefix so this can coexist with other lang/swiftNNN versions; no
# system bin symlinks (users add ${swift_install_prefix}/bin to PATH).
swift_install_prefix=	${PREFIX}/swift632

early_stage_dir=	${WRKDIR}/EarlyStageDir
MANDIRS=		${swift_install_prefix}/share/man

WRKSRC=			${WRKDIR}/swift-project

PLIST_SUB=	SWIFT_ARCH=${swift_arch} \
		SWIFT_TARGET_TRIPLE=${swift_arch}-unknown-freebsd${OSREL}

# Unpack the prebuilt 6.3.2 stage0 seed (extracts usr/local/swift) for hosttools.
post-extract:
	@${MKDIR} ${WRKDIR}/swift632-bootstrap
	@${LOCALBASE}/bin/zstd -dc ${DISTDIR}/${DIST_SUBDIR}/${BOOTSTRAP_FILE} | \
		${TAR} -xf - -C ${WRKDIR}/swift632-bootstrap

pre-patch:
	@${MKDIR} ${WRKSRC}/llbuild/lib/LLBSQLite3

post-patch:
	@${SED} -E -e 's@^python3=python3$$@python3=${PYTHON_CMD}@' -i .bak \
		${WRKSRC}/swift/utils/build-script-impl

do-build:
	@${MKDIR} ${early_stage_dir}
	${SETENV} \
		CCACHE_ENABLED=${CCACHE_ENABLED} \
		CCACHE_BIN=${CCACHE_BIN} \
		CCACHE_DIR=${CCACHE_DIR} \
		MAKE_JOBS_NUMBER=${MAKE_JOBS_NUMBER} \
		SWIFT_BOOTSTRAP_TOOLCHAIN=${SWIFT_BOOTSTRAP_TOOLCHAIN} \
		SWIFT_ARCH=${swift_arch} \
		${SH} -x ${FILESDIR}/start-build.sh ${WRKSRC} ${early_stage_dir} \
			${swift_install_prefix} ${WRKDIR}/clang-module-cache

do-install:
	@${FIND} ${early_stage_dir}${swift_install_prefix}/bin -type f \
		-not -name '*.py' -not -name '*.sh' -not -name '*.txt' \
		-exec ${STRIP_CMD} '{}' ';' ; \
	${FIND} ${early_stage_dir}${swift_install_prefix} -type f -name '*.so*' \
		-exec ${STRIP_CMD} '{}' ';' ; \
	cd ${early_stage_dir} ; \
	${COPYTREE_BIN} .${swift_install_prefix}/bin ${STAGEDIR} ; \
	for subdir in include lib libexec local share; do \
		[ -d .${swift_install_prefix}/$${subdir} ] && \
		${COPYTREE_SHARE} .${swift_install_prefix}/$${subdir} ${STAGEDIR} ; \
	done

.include <bsd.port.mk>

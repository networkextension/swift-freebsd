# DRAFT FreeBSD port for Swift 6.x with aarch64 support.
# Derived from the existing lang/swift510 (Swift 5.10.1) port by jgopensource@proton.me.
# This is a starting point for discussion — not a finished port. See README in the
# repo root of networkextension/swift-freebsd for the design rationale.
#
# Key deltas from lang/swift510:
#   * DISTVERSION bumped to 6.x
#   * GH_TUPLE adds the components 6.x introduced: swift-build (SwiftBuild),
#     swift-testing, swift-foundation, swift-foundation-icu, swift-toolchain-sqlite
#   * aarch64 build verified end-to-end (see issue swiftlang/swift#89943, 84% test pass)
#   * a small set of aarch64-specific patches in files/ (most FreeBSD fixes already
#     live in lang/swift510 and carry forward)

PORTNAME=	swift
DISTVERSION=	6.3.2
PORTREVISION=	0
CATEGORIES=	lang
DIST_SUBDIR=	${PORTNAME}

MAINTAINER=	jgopensource@proton.me
COMMENT=	Swift programming language
WWW=		https://www.swift.org/

# aarch64 support added by this work; amd64 carried from lang/swift510.
ONLY_FOR_ARCHS=	aarch64 amd64

BUILD_DEPENDS=	bash:shells/bash \
		cmake-core>=3.19.6:devel/cmake-core
LIB_DEPENDS=	libcurl.so:ftp/curl \
		libicuuc.so:devel/icu \
		libuuid.so:misc/libuuid \
		libxml2.so:textproc/libxml2 \
		libzstd.so:archivers/zstd

USES=		libedit ninja:build perl5 pkgconfig python:3.9+ \
		shebangfix sqlite:3
USE_GITHUB=	nodefault
# The common tag which applies to most swiftlang repos. swift-6.3.2-RELEASE was confirmed
# to exist across swift, swift-build, swift-foundation, swift-foundation-icu, swift-testing,
# swift-corelibs-foundation, swift-syntax, swift-package-manager, etc. (The aarch64 work was
# first validated against swift-DEVELOPMENT-SNAPSHOT-2026-02-02-a / compiler 3f8c798cfe /
# LLVM 972b6285835; the port targets the coherent -RELEASE tag instead.)
tag=		swift-${DISTVERSION}-RELEASE

# Compiler + core. NOTE vs swift510: foundation split into swift-foundation +
# swift-corelibs-foundation; added swift-build, swift-testing, swift-foundation-icu,
# swift-toolchain-sqlite.
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
# swift-toolchain-sqlite uses its own semver tags (NOT swift-X.Y.Z-RELEASE). swift-6.3.2's
# utils/update_checkout/update-checkout-config.json (release/6.3 scheme) pins 1.0.7.
GH_TUPLE+=\
	swiftlang:swift-toolchain-sqlite:1.0.7:swift_toolchain_sqlite/swift-toolchain-sqlite
# apple/* pins from swift-6.3.2's update-checkout-config.json (release/6.3 scheme).
GH_TUPLE+=\
	apple:swift-argument-parser:1.6.1:swift_argument_parser/swift-argument-parser \
	apple:swift-asn1:1.3.2:swift_asn1/swift-asn1 \
	apple:swift-certificates:1.10.1:swift_certificates/swift-certificates \
	apple:swift-collections:1.1.6:swift_collections/swift-collections \
	apple:swift-crypto:3.12.5:swift_crypto/swift-crypto \
	apple:swift-nio:2.65.0:swift_nio/swift-nio \
	apple:swift-system:1.5.0:swift_system/swift-system
# NOTE: swift-6.3's update-checkout-config.json no longer lists Yams (swift-format dropped
# the dependency). Kept here pending verification against swift-format's 6.3.2 manifest;
# remove if the build does not fetch it.
GH_TUPLE+=jpsim:Yams:5.1.3:yams/yams
USE_PERL5=	build

SHEBANG_FILES=\
	swift/utils/api_checker/sdk-module-lists/infer-imports.py \
	swift/utils/api_checker/swift-api-checker.py \
	swift/utils/build-script \
	swift/utils/swift-api-dump.py \
	swift-driver/Utilities/build-script-helper.py \
	swiftpm/Utilities/bootstrap \

CONFLICTS=	libdispatch-[0-9]* swift510-[0-9]*

value_for_aarch64=	aarch64
value_for_amd64=	x86_64
swift_arch=		${value_for_${ARCH}}
early_stage_dir=	${WRKDIR}/EarlyStageDir
swift_install_prefix=	${PREFIX}/${PORTNAME}
MANDIRS=	${swift_install_prefix}/share/man

SUB_FILES=	pkg-message
SUB_LIST=	SWIFT_INSTALL_PREFIX=${swift_install_prefix}

WRKSRC=		${WRKDIR}/swift-project

PLIST_SUB=	SWIFT_ARCH=${swift_arch} \
		SWIFT_TARGET_TRIPLE=${swift_arch}-unknown-freebsd${OSREL}

pre-patch:
	@${MKDIR} ${WRKSRC}/llbuild/lib/LLBSQLite3

post-patch:
	@${SED} -E -e 's@^python3=python3$$@python3=${PYTHON_CMD}@' -i .bak ${WRKSRC}/swift/utils/build-script-impl

# The build is delegated to files/start-build.sh, which drives swift/utils/build-script.
#
# CORRECTION vs swift510: Swift 6.3 CANNOT self-bootstrap on FreeBSD (its stdlib uses macros,
# which force --bootstrapping=hosttools, which needs a prebuilt VERSION-MATCHED host Swift
# toolchain). See ../../BUILD-NOTES-6.3.md and the README. So the real port needs a bootstrap
# toolchain, e.g.:
#
#   BUILD_DEPENDS+= ${LOCALBASE}/swift-bootstrap/usr/bin/swiftc:lang/swift-bootstrap
#   SWIFT_BOOTSTRAP_TOOLCHAIN?= ${LOCALBASE}/swift-bootstrap/usr
#
# (a `swift-bootstrap` distfile of a matched 6.3.x toolchain, like lang/rust ships a stage0).
# For now SWIFT_BOOTSTRAP_TOOLCHAIN is left for the builder to point at a matched toolchain.
SWIFT_BOOTSTRAP_TOOLCHAIN?=	${LOCALBASE}/swift-bootstrap/usr

do-build:
	@${MKDIR} ${early_stage_dir}
	${SETENV} \
		CCACHE_ENABLED=${CCACHE_ENABLED} \
		CCACHE_BIN=${CCACHE_BIN} \
		CCACHE_DIR=${CCACHE_DIR} \
		MAKE_JOBS_NUMBER=${MAKE_JOBS_NUMBER} \
		SWIFT_BOOTSTRAP_TOOLCHAIN=${SWIFT_BOOTSTRAP_TOOLCHAIN} \
		${SH} -x ${FILESDIR}/start-build.sh ${WRKSRC} ${early_stage_dir} \
			${swift_install_prefix} ${WRKDIR}/clang-module-cache

do-install:
	@${FIND} ${early_stage_dir}${swift_install_prefix}/bin -type f -not -name '*.py' -not -name '*.sh' -not -name '*.txt' -exec ${STRIP_CMD} '{}' ';' ; \
	${FIND} ${early_stage_dir}${swift_install_prefix} -type f -name '*.so*' -exec ${STRIP_CMD} '{}' ';' ; \
	cd ${early_stage_dir} ; \
	${COPYTREE_BIN} .${swift_install_prefix}/bin ${STAGEDIR} ; \
	for subdir in include lib local share; do \
		${COPYTREE_SHARE} .${swift_install_prefix}/$${subdir} ${STAGEDIR} ; \
	done

.include <bsd.port.mk>

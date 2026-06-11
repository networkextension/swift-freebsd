#!/bin/sh
# Swift CI setup for FreeBSD 14.x amd64
# Goal: install Swift nightly (x86), then prepare arm64 cross-compilation SDK
# Run as root (or via doas/sudo)

set -e

SWIFT_AMD64_URL="https://download.swift.org/tmp-ci-nightly/development/freebsd-14_ci_latest.tar.gz"
SWIFT_INSTALL_DIR="/usr/local/swift"
SWIFT_USER="swift"

echo "==> [1/5] Bootstrap pkg"
env ASSUME_ALWAYS_YES=yes pkg bootstrap -f
pkg update -f

echo "==> [2/5] Install runtime dependencies"
pkg install -y \
  git curl ca_root_nss \
  libedit libuuid libxml2 icu sqlite3 \
  python311 zstd \
  bash

echo "==> [3/5] Download Swift nightly toolchain (x86_64, ~920MB)"
fetch -o /tmp/swift-amd64.tar.gz "${SWIFT_AMD64_URL}"

echo "==> [4/5] Extract Swift toolchain"
mkdir -p "${SWIFT_INSTALL_DIR}"
tar -xzf /tmp/swift-amd64.tar.gz -C "${SWIFT_INSTALL_DIR}" --strip-components=1
rm /tmp/swift-amd64.tar.gz

echo "==> [5/5] Configure PATH for user ${SWIFT_USER}"
PROFILE="/home/${SWIFT_USER}/.profile"
if ! grep -q "swift/bin" "${PROFILE}" 2>/dev/null; then
  printf '\nexport PATH="%s/bin:$PATH"\n' "${SWIFT_INSTALL_DIR}" >> "${PROFILE}"
fi

# Also add to root profile for CI scripts running as root
if ! grep -q "swift/bin" /root/.profile 2>/dev/null; then
  printf '\nexport PATH="%s/bin:$PATH"\n' "${SWIFT_INSTALL_DIR}" >> /root/.profile
fi

export PATH="${SWIFT_INSTALL_DIR}/bin:$PATH"

echo ""
echo "==> Swift version installed:"
swift --version

echo ""
echo "==> Swift installed at: ${SWIFT_INSTALL_DIR}/bin/swift"
echo "==> Next step: run setup_arm64_sdk.sh to prepare FreeBSD arm64 cross-compilation SDK"

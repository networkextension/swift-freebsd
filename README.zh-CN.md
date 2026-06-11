# Swift on FreeBSD arm64 — 交叉编译工具链

在 **x86 FreeBSD 14.x** 主机上交叉编译 Swift 程序到 **FreeBSD arm64 (aarch64)**,并在真实 arm64 硬件上验证通过。

> swift.org 没有任何 FreeBSD aarch64 的 Swift 发行版,FreeBSD ports 里只有 Swift 5.10.1(x86)。
> 本项目自行交叉编译了 aarch64 的 Swift runtime + stdlib,补齐了这块空白。

## 验证结果(2026-06-11)

真机 NXP DPAA2 板,FreeBSD 14.4-RELEASE arm64:

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

stdlib、async/await、TaskGroup 并发全部正常。

## 架构

```
x86 FreeBSD 14.4 (build host)
├── /usr/local/swift              Swift 6.3-dev x86 nightly 工具链 (swiftc 本身就是交叉编译器)
├── /opt/freebsd-arm64-sysroot    FreeBSD 14.3 arm64 base 的头文件+库 (从官方 base.txz 解出)
├── /opt/swift-aarch64-resources  自编的 aarch64 Swift runtime/stdlib 资源目录
└── /usr/local/bin/swiftc-arm64   一键交叉编译包装脚本
```

```sh
# 用法:一条命令出 arm64 二进制
swiftc-arm64 hello.swift -o hello
file hello   # → ELF 64-bit LSB executable, ARM aarch64, FreeBSD 14.3
```

## 搭建步骤

### 1. 安装 x86 宿主工具链

swift.org 的 CI nightly(唯一可用的 FreeBSD Swift 6.x 二进制):

```sh
fetch https://download.swift.org/tmp-ci-nightly/development/freebsd-14_ci_latest.tar.gz
mkdir -p /usr/local/swift
tar -xzf freebsd-14_ci_latest.tar.gz -C /usr/local/swift --strip-components=1
pkg install -y cmake ninja python311 bash git rsync libuuid icu libedit libxml2 sqlite3
ln -sf /usr/local/bin/python3.11 /usr/local/bin/python3
```

### 2. 准备 arm64 sysroot

```sh
fetch https://download.freebsd.org/releases/arm64/aarch64/14.3-RELEASE/base.txz
mkdir -p /opt/freebsd-arm64-sysroot
tar -xf base.txz -C /opt/freebsd-arm64-sysroot ./lib ./usr/lib ./usr/include ./usr/libdata
```

### 3. 检出 Swift 源码(必须与工具链同 commit!)

```sh
mkdir /build/swift-project && cd /build/swift-project
git clone --depth 1 https://github.com/swiftlang/swift.git swift
# 关键:源码必须固定到工具链的 commit (swift --version 里的 hash),否则 frontend flag 不兼容
cd swift && git fetch --depth 1 origin <toolchain-commit-full-sha> && git checkout FETCH_HEAD && cd ..
./swift/utils/update-checkout --clone --skip-history --scheme main
```

### 4. 打补丁

应用本仓库的 [`arm64-freebsd-cross.patch`](arm64-freebsd-cross.patch)(2 个上游 bug,见下文):

```sh
cd /build/swift-project/swift && git apply /path/to/arm64-freebsd-cross.patch
```

### 5. 交叉编译 stdlib

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

⚠️ 如果 CMakeCache 已存在,`EXECINFO_LIBRARY` 的 `-D` 不会覆盖缓存,需手改 CMakeCache.txt 指向 sysroot 里的 aarch64 版本。

### 6. 安装产物

```sh
BUILD=/build/swift-project/build/Ninja-ReleaseAssert/swift-freebsd-x86_64
# 资源目录 (tar -h 解引用符号链接)
mkdir -p /opt/swift-aarch64-resources
tar -C $BUILD/lib/swift -chf - . | tar -C /opt/swift-aarch64-resources -xf -
# swiftrt.o 等运行时镜像进 sysroot (链接器经 -sdk 查找)
mkdir -p /opt/freebsd-arm64-sysroot/usr/lib/swift/freebsd
cp -R /opt/swift-aarch64-resources/freebsd/aarch64 /opt/freebsd-arm64-sysroot/usr/lib/swift/freebsd/
```

⚠️ **千万不要**把 build 产物 rsync 进 `/usr/local/swift/lib/swift/freebsd/` 顶层 —— 会把宿主 x86 库覆盖成 aarch64,swift-driver(本身是 Swift 写的)直接报废。

### 7. 包装脚本

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

## 发现的上游 Bug(见 patch)

1. **`CMakeLists.txt`** — FreeBSD 的 SDK 配置硬编码 `configure_sdk_unix("FreeBSD" "${SWIFT_HOST_VARIANT_ARCH}")`,只注册宿主架构。下游 `SwiftConfigureSDK.cmake` 明明白名单里有 `aarch64|x86_64`,入口却传不进去。
   注:同时配置 `"x86_64;aarch64"` 双架构会在归档合并步骤挂掉(非 Darwin 没有 lipo,`cmake -E copy 多源 → 单文件` 报错),所以只配 aarch64。

2. **`cmake/modules/Libdispatch.cmake`** — libdispatch ExternalProject 的交叉编译参数(`CMAKE_C_COMPILER_TARGET`)**只有 Windows 分支**。FreeBSD 交叉编译时 libdispatch 静默编成宿主 x86 架构,链接 `_Concurrency` 时才暴雷。补丁添加了 FREEBSD 分支传 target triple + sysroot + `CMAKE_SYSTEM_NAME`。

## 踩坑记录

| 问题 | 现象 | 解法 |
|---|---|---|
| 源码与工具链版本错位 | `unknown argument: '-solver-enable-crash-on-valid-salvage'` | swift 仓库 checkout 到工具链 commit |
| 双架构 lipo 合并 | `Target (for copy command) ... is not a directory` | 只配 aarch64 单架构 |
| find_library 抓宿主库 | `libexecinfo.so is incompatible with crti.o` | `EXECINFO_LIBRARY` 指向 sysroot(注意 CMakeCache 缓存) |
| libdispatch 编成 x86 | `libdispatch.so is incompatible with crti.o` | Libdispatch.cmake 补丁 + 清掉旧 prefix 目录重配 |
| swiftrt.o 找不到 | `no such file: .../sysroot/usr/lib/swift/freebsd/aarch64/swiftrt.o` | aarch64 运行时镜像进 sysroot |
| 链接到宿主 x86 stdlib | `libswiftCore.so is incompatible with crt1.o` | 独立 `-resource-dir` 指向 aarch64 资源目录 |

## 已编译 / 未编译

✅ **已有(23 库)**:Core、_Concurrency、Glibc、dispatch(C)、Synchronization、Distributed、Observation、RegexBuilder、_StringProcessing、_RegexParser、_Differentiation、SwiftOnoneSupport 等

❌ **待补**(按建议顺序):libswiftDispatch(Swift overlay)→ XCTest → FoundationEssentials → _FoundationICU/Internationalization → Foundation → FoundationXML/Networking(需要先从 `pkg.freebsd.org/FreeBSD:14:aarch64` 抽 libxml2/curl 进 sysroot)→ swift-testing

## Release 资产

- `swift-freebsd-arm64-cross-env.tar.gz` — 完整交叉编译环境(sysroot + aarch64 资源 + 包装脚本),解压即用(还需自装 x86 nightly 工具链,见步骤 1)
- `swift-arm64-test.tar.gz` — 真机测试包(2 个测试二进制 + 11 个运行时库 + 一键脚本)

## 环境

- 构建机:FreeBSD 14.4-RELEASE amd64,8 核 / 32GB
- 工具链:Swift 6.3-dev nightly(commit `3f8c798cfe`,2026-02-03)
- 目标:`aarch64-unknown-freebsd14.3`
- 验证硬件:NXP DPAA2 arm64,FreeBSD 14.4-RELEASE

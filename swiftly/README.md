# swiftly on FreeBSD

[swiftly](https://github.com/swiftlang/swiftly) (the Swift toolchain installer/manager)
**builds and runs natively on FreeBSD 15.1 / aarch64**, using the native
`swift-6.3.2-RELEASE` toolchain from this repo
([v0.4.1](https://github.com/networkextension/swift-freebsd/releases/tag/v0.4.1)).

```
$ swift build            # Build complete! (126s), 0 errors
$ .build/aarch64-unknown-freebsd/debug/swiftly --help     # full usage
$ .build/.../swiftly --version
  Could not load swiftly's configuration file ... run 'swiftly init'.   # works (no crash)
```

This is the second leg alongside the toolchain port (`../ports-draft/lang/swift632`):
the toolchain lets you *build* Swift on FreeBSD; swiftly lets you *manage* Swift toolchains
on FreeBSD.

## Approach: a dedicated `FreeBSDPlatform` target

swiftly selects a platform implementation at compile time (`LinuxPlatform` / `MacOSPlatform`).
FreeBSD gets its **own** `FreeBSDPlatform` target (`struct FreeBSD: Platform`) rather than
reusing `LinuxPlatform` — this is the clean, upstreamable shape (and what a ports submission
needs). It was derived from `LinuxPlatform` (whose POSIX/Foundation/Subprocess logic compiles
on FreeBSD essentially unchanged) and is wired in as an **unconditional** package dependency
that self-guards with `#if os(FreeBSD)`, because Swift's `PackageDescription` currently has
**no `.freebsd` platform** (`Platform.freebsd` is `'freebsd' is unavailable`), so
`.when(platforms: [.freebsd])` cannot be used.

- `patches/FreeBSDPlatform/{FreeBSD,Extract}.swift` — the new target's source.
- `patches/swiftly.diff` — `Package.swift` (target + deps), `Swiftly.swift` /
  `TestSwiftly.swift` (`#elseif os(FreeBSD) → FreeBSD.currentPlatform`),
  `SwiftlyCore/{ProcessInfo,Platform,Platform+Process,Terminal}.swift` (FreeBSD on the POSIX
  `os(macOS) || os(Linux)` guards), and `Tools/build-swiftly-release` (FreeBSD branch — the
  release pipeline is musl-SDK-specific, so it throws for now).

## Dependency patches (`patches/deps/`)

Building swiftly pulls a large graph (SwiftNIO, AsyncHTTPClient, swift-nio-ssl/BoringSSL,
swift-crypto, swift-certificates, swift-openapi-*, swift-log, …). The patches fall into three
classes:

**1. Real FreeBSD portability fixes (upstream-worthy):**
- `swift-nio.diff` (the big one) — SwiftNIO has no FreeBSD platform layer. Enables the
  `CNIOOpenBSD` C shim on FreeBSD, the kqueue `Selector` (drops `EVFILT_EXCEPT`, absent on
  FreeBSD), socket constants (`UIO_MAXIOV`, `SHUT_*`, `IPTOS_ECN_*`, `IP_PKTINFO`,
  BSD-signature `sendfile`), `_NIOFileSystem` syscalls (FTS, xattr stubs, `renameat`,
  `O_TMPFILE`/`AT_EMPTY_PATH`/`RENAME_*`), and `inet_ntop`/`mmsghdr`/`in_pktinfo` shims.
  *(For an upstream PR this should become a dedicated `CNIOFreeBSD` shim rather than riding
  `CNIOOpenBSD`.)*
- `swift-nio-ssl.diff` — BoringSSL `gettimeofday`/`getentropy` visibility (`__STRICT_ANSI__` /
  `_POSIX_C_SOURCE` undef), and a `CNIOBoringSSLShims_inet_ntop` wrapper.
- `swift-log`, `swift-distributed-tracing`, `swift-http-types`, `swift-subprocess`,
  `async-http-client` — the `pthread_*`-is-`OpaquePointer` pattern (optional typealias +
  `pthread_mutexattr_t(bitPattern: 0)`), mirroring each project's existing OpenBSD branch;
  plus `<xlocale.h>` for `strptime_l` in async-http-client. See upstream
  [swiftlang/swift#81407](https://github.com/swiftlang/swift/issues/81407).

**2. A temporary workaround (NOT for upstream):** the 1-file diffs for `swift-asn1`,
`swift-certificates`, `swift-crypto`, `swift-http-structured-headers`, `swift-nio-extras`,
`swift-nio-http2`, `swift-nio-transport-services`, `swift-openapi-*` just comment out
`enableUpcomingFeature("MemberImportVisibility")` in their `Package.swift`. This sidesteps a
toolchain gap — FreeBSD's SwiftGlibc overlay doesn't expose some `<arpa/inet.h>` / `<sys/uio.h>`
symbols, so a C shim re-declaring `<netinet/in.h>` becomes the "defining module" for `sockaddr`
members. The real fix is the overlay, tracked at
[swiftlang/swift#85427](https://github.com/swiftlang/swift/issues/85427); once that lands these
disables can all be dropped.

## Build recipe

With the native `swift-6.3.2-RELEASE` toolchain installed (e.g. under
`/usr/local/swift`), apply the patches to a swiftly checkout + its resolved
`.build/checkouts/*`, then `swift build`. Notes:
- `pkg install compat14x-aarch64` is **not** needed — the v0.4.1 toolchain is native 15.1.
- The toolchain must carry the `NSLock` `Process.once` fix
  ([swiftlang/swift#90057](https://github.com/swiftlang/swift/issues/90057)); v0.4.1 has it.
  Without it, `Foundation.Process` self-deadlocks and SwiftPM build-tool plugins hang.

## Upstreaming status

Tracked on the official **[Swift on FreeBSD](https://github.com/orgs/swiftlang/projects/16)**
board. Our data is posted on #85427 (Glibc overlay) and #81407 (pthread API notes); the
SwiftNIO/pthread portability work and a `FreeBSDPlatform` for swiftly are the next PRs.

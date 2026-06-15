# Building the `lang/swift` 6.3.2 port with poudriere (FreeBSD aarch64)

Notes for building this draft port on an **Ampere ARM64** server (the target host once one
is available — the board used for the initial bring-up is CPU-limited). poudriere gives a
clean jail, so the build is reproducible and independent of the host's installed packages.

## Why aarch64 native (not cross)

The original toolchain was *cross-compiled* x86→aarch64 (see [BOOTSTRAP.md](../BOOTSTRAP.md)).
A port does a **native** multi-stage build on the aarch64 host, so the cross-only fixes
(`build-script-impl` host allowlist, `Libdispatch.cmake` cross args, the `CMakeLists.txt`
arch hardcode) are *not* applied here — only the two native-relevant patches in `files/`.

## Resource expectations

Swift is a heavy build (LLVM + the compiler twice via bootstrapping + stdlib + Foundation +
SwiftPM/llbuild + tests). Budget accordingly:

- **RAM:** ~2 GB per link job at peak. `start-build.sh` already pins LTO link jobs to 1
  (`--llvm-max-parallel-lto-link-jobs 1`, `--swift-tools-max-parallel-lto-link-jobs 1`).
  On a many-core Ampere, cap parallelism if the jail OOMs (see `MAKE_JOBS_NUMBER` below).
- **Disk:** tens of GB in `WRKDIR` (the `EarlyStageDir` DESTDIR plus build trees).
- **Time:** hours even on a fast Ampere; the multi-stage bootstrap builds the compiler twice.

## Setup

```sh
pkg install poudriere-devel ports-mgmt/portlint
# A jail matching the host release/arch (aarch64):
poudriere jail -c -j 143arm64 -v 14.3-RELEASE -a arm64.aarch64

# Ports tree containing this lang/swift draft. Easiest: point poudriere at a tree where
# ports-draft/lang/swift has been copied to lang/swift, with distinfo regenerated.
poudriere ports -c -p swiftdev -m null -M /path/to/ports-with-lang-swift
```

`make -C lang/swift makesum` must be run once (with network access) to generate `distinfo`
for all the `GH_TUPLE` distfiles before poudriere's offline build.

## Tuning knobs (poudriere `make.conf` for the set)

```make
# Throttle if the jail runs out of RAM during the C++/LTO link phases.
MAKE_JOBS_NUMBER?=	8
# ccache dramatically speeds re-builds across patch iterations.
WITH_CCACHE_BUILD=	yes
CCACHE_DIR=		/var/cache/ccache
```

The port reads `CCACHE_ENABLED`/`CCACHE_BIN`/`CCACHE_DIR`/`MAKE_JOBS_NUMBER` from the
environment and forwards them to `build-script` (see `files/start-build.sh`).

## Build

```sh
poudriere testport -j 143arm64 -p swiftdev -o lang/swift
# or, for a plain build into a local repo:
poudriere bulk     -j 143arm64 -p swiftdev lang/swift
```

`testport` runs the full `stage`/`check-plist`/`pkg` flow — that is what catches missing or
stale `pkg-plist` entries, which is the main thing to iterate on after the build itself
succeeds. `PLIST_SUB` already substitutes `SWIFT_ARCH=aarch64` and
`SWIFT_TARGET_TRIPLE=aarch64-unknown-freebsd${OSREL}`.

## Expected iteration points

1. **`pkg-plist`** — Swift installs a large, version-dependent file set; regenerate from a
   successful `make stage` (`make -C lang/swift makeplist > pkg-plist`) and trim generated
   junk.
2. **New 6.x patches** — rebase the swift510 patch set; some hunks will have moved. The two
   patches already in `files/` (DebugDescriptionMacro, AddSwift.cmake) are the aarch64/6.x
   additions on top of that set.
3. **Yams** — confirm whether the 6.3.2 build actually fetches it; drop from `GH_TUPLE` if not.

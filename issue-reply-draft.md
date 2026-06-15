Thanks @finagolfin! I don't have OpenBSD numbers to compare against — this was FreeBSD-only — but happy to defer to @3405691582 on how the two ports line up.

@etcwilde — an official FreeBSD AArch64 toolchain would be great, and I'm glad to help make it happen. Everything I used is written up here, including the exact matched component revisions and a build-1→36 troubleshooting log:
https://github.com/networkextension/swift-freebsd/blob/main/BOOTSTRAP.md

The build needed a handful of FreeBSD-cross fixes ([patch](https://github.com/networkextension/swift-freebsd/blob/main/arm64-freebsd-cross.patch)). Three look upstream-ready and I can send them as separate PRs:

- `utils/build-script-impl` — add `freebsd-*` to the `--cross-compile-hosts` allowlist (line 2933 already lists it; line ~1108 doesn't).
- `cmake/modules/Libdispatch.cmake` — pass cross args (`CMAKE_C_COMPILER_TARGET` / `CMAKE_SYSROOT` / `CMAKE_SYSTEM_NAME`) for FreeBSD; currently Windows-only, so libdispatch silently builds for the host arch.
- `cmake/modules/AddSwift.cmake` — in the host-tools branch, order the arch-specific lib dir before the generic one so `-lswiftCore` resolves the target arch.

Two more are workarounds I'd rather discuss than PR as-is: the `CMakeLists.txt` `configure_sdk_unix("FreeBSD" ...)` arch handling (I hardcoded `aarch64`), and a `DebugDescriptionMacro.swift` change to avoid `String.replacing` under `-disable-implicit-string-processing-module-import` — the real fix there is probably elsewhere.

This was a 2nd-stage native build: seed compiler cross-built on x86 FreeBSD, then the full compiler + stdlib + Foundation/Dispatch/XCTest/swift-testing rebuilt natively on the device. Glad to open the PRs, share more logs, or re-run anything that would help.

# Building Swift 6.3.2 on FreeBSD aarch64 — hard-won notes

Notes from actually building `swift-6.3.2-RELEASE` natively on a FreeBSD 14.4 aarch64 board
(NXP DPAA2 / LX2160, 16× Cortex-A72, 63 GB RAM). These are the non-obvious things that cost
real time; they inform the `lang/swift` 6.3 port design.

## 1. Coherent source checkout (`swift-6.3.2-RELEASE`)

Do **not** mix `main`-by-date checkouts — SPI/API drift between repos causes failures like
`SWBBuildServer does not conform to QueueBasedMessageHandler` (swift-build vs
swift-tools-protocols version skew). Use one coherent set:

```sh
mkdir s632 && cd s632
git clone https://github.com/swiftlang/swift.git
( cd swift && git checkout swift-6.3.2-RELEASE )
./swift/utils/update-checkout --clone --tag swift-6.3.2-RELEASE   # then re-run WITHOUT --clone (see below)
```

- `update-checkout --clone --tag ...` can die with a `TimeoutError` in the parallel clone
  runner while waiting on the huge `llvm-project` clone. The clones still complete; **re-run
  `./swift/utils/update-checkout --tag swift-6.3.2-RELEASE` (no `--clone`)** to do the fast
  checkout phase. Result: swiftlang core repos land on `swift-6.3.2-RELEASE`; `apple/*` +
  `Yams` + `swift-toolchain-sqlite` land on their version tags (1.6.1, 2.65.0, 1.0.7, …) via
  the `release/6.3` scheme — exactly the GH_TUPLE pins in the port Makefile.

## 2. You need a version-matched host toolchain (the big one)

See [README.md](README.md#the-bootstrap-chicken-and-egg--63-requires-a-prebuilt-host-toolchain).
TL;DR: 6.3's stdlib uses macros → `SWIFT_BUILD_SWIFT_SYNTAX=ON` → CMake forces
`--bootstrapping=hosttools` on FreeBSD/Linux → the **host** compiler builds the stdlib → the
stdlib is stamped with the **host's** version. A 6.3-dev host yields a 6.3.2 compiler that
rejects its own 6.3-stamped stdlib. **The host must be the same version you're building.**

### The regen-from-`.swiftinterface` trick (bootstrap a matched host)

If all you have is a *near*-version host (e.g. 6.3-dev) and you host-build 6.3.2, the
binary `.swiftmodule`s are version-locked to the host, but **resilient modules also ship a
textual `.swiftinterface`** which any compatible compiler can recompile. Re-stamp them with
the freshly-built 6.3.2 compiler:

```sh
# FRESH = .../build/Ninja-ReleaseAssert/swift-freebsd-aarch64   (has bin/swift-frontend = 6.3.2)
export LD_LIBRARY_PATH="$FRESH/lib/swift/freebsd/aarch64:$FRESH/lib/swift/host/compiler"  # FRESH's OWN runtime!
for iface in $(find "$RD" -name 'aarch64-unknown-freebsd.swiftinterface'); do
  out="$(dirname "$iface")/aarch64-unknown-freebsd.swiftmodule"
  flags=$(sed -n 's#^// swift-module-flags: ##p' "$iface" | head -1)   # MUST pass these (incl -module-name)
  "$FRESH/bin/swift-frontend" -compile-module-from-interface "$iface" -o "$out" -resource-dir "$RD" $flags
done
```

- **Must** pass the interface's embedded `// swift-module-flags:` (it carries `-module-name`,
  `-target`, experimental features). Without `-module-name` it errors
  `module name "aarch64-unknown-freebsd" is not a valid identifier`.
- **Must** run the fresh compiler with its **own** runtime. Pointing `LD_LIBRARY_PATH` at a
  different toolchain's `host/compiler` `.so` (6.3) **segfaults** the 6.3.2 frontend.
- After regenerating the stdlib modules, `hello.swift` compiles and runs as 6.3.2. ✓
- **Caveats:** non-resilient overlays have **no** `.swiftinterface` (e.g. `Dispatch`) → can't
  be regen'd, must be rebuilt by the 6.3.2 compiler. `CxxStdlib` needs C++-interop flags.
- **Proper finish:** regen *everything incl. the host `swift-syntax`/`SwiftCompilerSources`
  modules* to assemble a fully-consistent 6.3.2 host, then re-run `build-script` once with it
  as the hosttools seed → all of stdlib/Dispatch/Foundation/SwiftPM build natively as 6.3.2.
  That consistent toolchain *is* the bootstrap distfile the port should ship.

## 3. build-script recipe that got furthest (hosttools)

```sh
TC=<version-matched host toolchain>/usr        # e.g. the bootstrap distfile
export PATH="$TC/bin:$PATH"
export LD_LIBRARY_PATH="$TC/lib/swift/freebsd/aarch64:$TC/lib/swift/host/compiler:$TC/lib/swift/host"
export SWIFTC="$TC/bin/swiftc"
utils/build-script --release --assertions --bootstrapping=hosttools \
  --host-cc /usr/bin/clang --host-cxx /usr/bin/clang++ --jobs 8 \
  --llvm-targets-to-build 'AArch64;X86' --skip-early-swift-driver \
  --libdispatch true --foundation true --xctest true --swiftpm true --llbuild true \
  --swift-driver true --swift-testing true \
  --extra-cmake-options="-DSWIFT_USE_LINKER=lld" \
  --extra-cmake-options="-DLLVM_USE_LINKER=lld" \
  --extra-cmake-options="-DLLVM_PARALLEL_LINK_JOBS=1" \
  --extra-cmake-options="-DSWIFT_PARALLEL_LINK_JOBS=1" \
  --extra-cmake-options="-DSWIFT_BUILD_SWIFT_SYNTAX=ON" \
  --extra-cmake-options="-DCMAKE_Swift_COMPILER=$TC/bin/swiftc" \
  --install-destdir <destdir> --install-prefix /usr/local/swift --install-all
```

- LLVM builds+installs on FreeBSD aarch64 with **no patches** (~2.5 h at `-j8`).
- Do **not** pass `--native-swift-tools-path`/`--native-clang-tools-path` — they don't change
  which compiler builds the stdlib (it's always the host in hosttools) and only confuse things.
- `swift-testing` and `SwiftPM`'s TSCBasic fail with `cannot load underlying module for
  'Dispatch'` if the host toolchain's resource dir lacks the **Dispatch clang module**
  (`lib/swift/{dispatch,os,Block}`). A `--install-all` toolchain has it; a hand-assembled
  host may not. Do **not** inject it into the host resource dir during the main build — it
  collides with the `-I` the in-tree build already adds (`redefinition of module 'CDispatch'`).
  Fix belongs in the bootstrap distfile's resource dir.

## 4. Memory & thermal limits on a small board

- **63 GB RAM but only 2 GB swap** → parallel **links** (not compiles) spike memory and a
  swap-starved box hard-wedges (network + serial dead, needs power-cycle). Serialize links:
  `-DLLVM_PARALLEL_LINK_JOBS=1 -DSWIFT_PARALLEL_LINK_JOBS=1`. Then `-j8`…`-j14` is rock stable
  (57–59 GB free, 0 swap). **Do not** add swap-on-ZFS — it deadlocks under memory pressure.
- **Sustained all-core compile overheats** a passively/poorly-cooled board → ACPI thermal
  shutdown at ~95 °C. With an added fan + a thermal governor that `SIGSTOP`s
  `ninja/clang/swift-frontend` above ~86 °C and `SIGCONT`s below ~76 °C (watch the max of all
  `hw.acpi.thermal.tzN.temperature`), `-j14` holds at ~70 °C. → use poudriere on a
  well-cooled, well-swapped host (the Ampere target) instead.
- ninja's incremental cache survives reboots/power-cycles — just relaunch `build-script`.

## 5. Status

Reached a **consistent 6.3.2 compiler + stdlib** on FreeBSD aarch64 (`hello.swift` compiles &
runs) via the regen trick. LLVM/cmark/swift/libdispatch/Foundation all build. Remaining for a
*complete* clean toolchain: the §2 "proper finish" two-pass (assemble a fully-consistent 6.3.2
host, re-run build-script) — which simultaneously produces the bootstrap distfile the port
needs. Best run on the Ampere host under poudriere.

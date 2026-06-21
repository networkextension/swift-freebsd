# lang/swift632 — status

Versioned FreeBSD port for **Swift 6.3.2-RELEASE** (compiler + stdlib + Foundation +
Dispatch + XCTest + swift-testing + SwiftPM). Derived from lang/swift510.

## Design
- **hosttools bootstrap.** 6.3 cannot self-bootstrap on FreeBSD (macro stdlib forces
  `--bootstrapping=hosttools`). The host must be **version-matched 6.3.2** so the corelibs
  products it builds are stamped 6.3.2 and the whole tree is coherent in one build-script run.
- **stage0 seed via distfile** (lang/rust style): the `BOOTSTRAP_FILE` is fetched from the
  v0.4.0-6.3.2 GitHub release and extracted into `${WRKDIR}/swift632-bootstrap` at build time;
  it is not installed. Seed currently exists for **aarch64** only.
- Installs under `${PREFIX}/swift632` (coexists with other lang/swiftNNN).

## Files
- `Makefile` — GH_TUPLE pins (release/6.3 scheme), hosttools build via `files/start-build.sh`.
- `files/start-build.sh` — single `--install-all` build-script run (+ `--swift-testing-macros`,
  serialized links); documents the FreeBSD gotchas (corelibs stamping, dispatch module
  collision, SwiftPM `LLBuild_DIR`, TestingMacros) for maintainers.
- `files/patch-swift_cmake_modules_AddSwift.cmake`, `files/patch-swift_lib_Macros_..._DebugDescriptionMacro.swift`.
- `files/patch-swift-testing_Sources_Testing_Support_Locked.swift` — **routes swift-testing's
  `Locked<T>` to `pthread_mutex` on FreeBSD** (adds `os(FreeBSD)` to the existing Linux/Android
  `!SWT_FIXED_85448` branch). Without it the bundled `Synchronization.Mutex` deadlocks under
  contention on FreeBSD/aarch64, so *any* parallel `swift test` (swift-testing) run on the
  resulting toolchain hangs. Verified: rebuilt `libTesting.so` with this change turned a
  reliably-hanging 200-test package into 3/3 passes, and let swiftly's own suite run. Mirrors
  swift-testing's upstream issue 85448 workaround; should become an upstream swift-testing PR.
- `pkg-descr`, `files/pkg-message`.

## Remaining before submission (need an aarch64 poudriere jail)
1. `make makesum` — generates `distinfo` for all GH_TUPLE sources + the bootstrap seed.
   Known bootstrap checksum:
   `SHA256 (swift/swift-6.3.2-RELEASE-freebsd15-aarch64.tar.zst) = 7f8ce99a9923333cd4f44e3238f17ddd01f5ee89bd47b3903ec0033114632a9e`
   `SIZE = 821055218`
2. `make makeplist` (after a successful build) — generates `pkg-plist`.
3. Rebase lang/swift510's FreeBSD patches onto 6.3.2; confirm which still apply (the 6.3.2
   native build needed only AddSwift.cmake + DebugDescriptionMacro from the draft set).
4. `poudriere testport` on aarch64 (15.x) and amd64.
5. Produce an **amd64** stage0 seed (cross-built on x86 FreeBSD, or once amd64 6.3.2 is
   published) so BOOTSTRAP works on amd64; until then the port is aarch64-only in practice.
6. Decide naming/prefix vs the existing lang/swift510 convention with the maintainer
   (jgopensource@proton.me) / sponsoring committer (Xin LI).
7. **Verify the GH_TUPLE extraction layout vs WRKSRC.** build-script needs all repos as
   siblings in one workspace; `WRKSRC=${WRKDIR}/swift-project` and start-build.sh does
   `cd ${WRKSRC}/swift`. Confirm the GH_TUPLE subdir fields place every repo under
   `swift-project/` to match (inherited from the swift510-derived draft — compare with the
   actual lang/swift510). If repos extract directly under ${WRKDIR}, either prefix each
   GH_TUPLE subdir with `swift-project/` or set WRKSRC=${WRKDIR}.

## Provenance
Build verified end-to-end on FreeBSD 15.1/aarch64; see ../../BUILD-NOTES-6.3.md,
the GitHub release, and swiftlang/swift#89943.

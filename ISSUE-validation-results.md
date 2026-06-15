# Compiler validation test suite results on FreeBSD AArch64 (native build)

Following up on @finagolfin's suggestion — here are the results of running the compiler
validation test suite (`build-script -T`) on **FreeBSD 14.4 / AArch64**, built and tested
natively on the device.

## Environment

| | |
|---|---|
| OS | FreeBSD 14.4-RELEASE, `aarch64` |
| Host | 16 cores, 64 GB RAM |
| Target triple | `aarch64-unknown-freebsd14.4` |
| swift | `3f8c798cfe25bbb04f2bae2ec81a46259f5f637b` |
| llvm-project | `972b62858355d0714921cbf489de6598376e914a` |
| swift-syntax | `swift-DEVELOPMENT-SNAPSHOT-2026-02-02-a` (`edbbad24`) |
| Build type | `--release`, `--bootstrapping=hosttools` |

This is a 2nd-stage native build: a seed compiler was first cross-compiled on x86 FreeBSD,
then used to natively build the full compiler + stdlib + Foundation/Dispatch/XCTest/
swift-testing from source on the AArch64 device. Details and the FreeBSD AArch64 build
patches: https://github.com/networkextension/swift-freebsd

## Results

```
Testing Time: 8106.19s
Total Discovered Tests: 21177
  Unsupported        :  3283 (15.50%)
  Passed             : 17813 (84.11%)
  Expectedly Failed  :    53 (0.25%)
  Failed             :    26 (0.12%)
  Unexpectedly Passed :    1 (0.00%)
```

84% pass / 26 failures (0.12%) — FreeBSD AArch64 is in good shape.

## Failures (26), grouped

**Reflection / typeref (6)** — likely the largest cluster:
- `Reflection/conformance_descriptors.swift`
- `Reflection/typeref_decoding.swift`, `typeref_decoding_asan.swift`, `typeref_decoding_packs.swift`
- `Reflection/typeref_lowering.swift`, `typeref_lowering_packs.swift`

**C++ interop stdlib (4)**:
- `Interop/Cxx/function/default-arguments-multifile.swift`
- `Interop/Cxx/stdlib/foundation-and-std-module.swift`
- `Interop/Cxx/stdlib/import-cxx-math-ambiguities.swift`
- `Interop/Cxx/stdlib/use-std-optional-lib.swift`

**TSan (3)**:
- `Sanitizers/tsan/libdispatch.swift`
- `Sanitizers/tsan/norace-block-release.swift`
- `Sanitizers/tsan/norace-deinit-run-time.swift`

**Runtime unit tests (3)**: `SwiftRuntimeTests` shards 10, 11, 12 / 16

**Macros (2)**:
- `Macros/expand_on_imported.swift`
- `Macros/print_clang_expand_on_imported.swift`

**Concurrency / Synchronization (2)** — possibly a real atomics/concurrency issue worth a look:
- `Concurrency/Runtime/cancellation_handler_only_once.swift`
- `stdlib/Synchronization/Mutex/LockSingleConsumerStack.swift` (its unit counterpart
  `["concurrentPushes", "concurrentPushesAndPops"]` also fails; these tended to *hang*
  rather than fail fast)

**Misc (6)**:
- `IRGen/pic.swift`
- `Interpreter/generic_casts.swift`
- `Runtime/subclass_instance_start_adjustment.swift`
- `SILGen/coroutine_accessors_back_deployment_abi.swift`
- `Swift-validation :: Evolution/test_coroutine_accessors.swift`
- `Swift-validation :: Sema/type_checker_perf/fast/swift_docc.swift` (perf threshold)

1 test `Unexpectedly Passed` (an `XFAIL` that passes on FreeBSD AArch64).

## Note on hangs / `--lit-args`

A few tests (the TSan ones and the `Synchronization` Mutex/lock-free-stack stress tests)
**hang** rather than fail. `build-script -T --lit-args="--timeout=300"` did not appear to
propagate the per-test timeout to the validation `lit` invocation, so the run stalled on
them; I worked around it with an external watchdog that killed test processes exceeding a
CPU-time budget. If there's a supported way to pass a per-test timeout to the validation
suite via `build-script`, a pointer would be appreciated (and the propagation may be worth
fixing).

Happy to dig into any specific failure, post full logs, or re-run with extra flags. Thanks
@finagolfin for the nudge.

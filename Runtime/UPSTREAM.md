# QuickJS adapter provenance and boundaries

The C sources in `CQuickJS/vendor` are copied without modification from the official
QuickJS **2026-06-04** release:

- Archive: https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz
- SHA-256: `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`
- License: MIT; the complete upstream notice is retained in `LICENSE.QuickJS` and the sources.
- Included: `quickjs.c`, `dtoa.c`, `libregexp.c`, `libunicode.c`, `cutils.c` and their headers.
- Excluded: the command-line tools, compiler, OS/shell module (`quickjs-libc`), examples,
  generated binaries, upstream build products and test suite.

`LegadoQuickJS.c` and `LegadoRuntime/QuickJSRuntime.swift` are this project's adapter.
The separate SwiftPM product has no dependency from `LegadoCore` or `LegadoApp` yet.
It is the first v0.3.1 implementation step, not a replacement of the released app engine.
The existing Xcode app target is unchanged; full app integration and bridge migration remain.

The adapter owns one serialized runtime/context, installs a monotonic deadline and atomic
cancellation signal for evaluation and JSON serialization, and bounds heap, stack, source
and JSON result sizes. Every returned C result and runtime/context is explicitly released.
Blocking `Atomics.wait` is disabled so a script cannot enter that native wait indefinitely.
The evaluation timeout starts after acquiring the runtime lock; it is not a queue deadline.
Cancellation can interrupt a running evaluation through VM polling, but not cancel a caller
waiting for that lock. A token is one-shot and must remain alive for the evaluation.

Only synchronous global evaluation is exposed. Results cross the boundary as JSON text;
undefined and non-JSON results return nil. There are no Legado Java/source/book bindings,
network/filesystem host calls, module loader or Promise job pump. No source runs on the new
adapter through the app yet. Native regex / large-number work and OS scheduling may delay
interrupt polling; this is not a strict wall-clock guarantee for every engine operation.

Regression tests exercise JSON/context isolation, 50 timeout/recovery cycles, cancellation,
recursion and allocation failures, serialization/error-conversion interruption, input/output
limits, syntax errors and 50 ownership/release cycles. Weak-reference checks are not a
substitute for a leak detector. Cross-compilation proves iOS compiler compatibility, not
iOS runtime acceptance or parity with JavaScriptCore.

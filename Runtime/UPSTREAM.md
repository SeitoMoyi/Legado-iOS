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
The SwiftPM Core target now depends on the product; the Xcode app compiles the same C and
Swift sources through its explicit source registration and native module map. JSEngine uses
this adapter for the app's source, login, formatting and replacement script calls.

The adapter owns one serialized runtime/context, installs a monotonic deadline and atomic
cancellation signal for evaluation and JSON serialization, and bounds heap, stack, source
and JSON result sizes. Every returned C result and runtime/context is explicitly released.
Blocking `Atomics.wait` is disabled so a script cannot enter that native wait indefinitely.
The evaluation timeout starts after acquiring the runtime lock; it is not a queue deadline.
Cancellation can interrupt a running evaluation through VM polling, but not cancel a caller
waiting for that lock. A token is one-shot and must remain alive for the evaluation.

The adapter exposes synchronous global evaluation and a JSON host callback. JSEngine installs
the existing Java/source/book bindings, including bounded HTTP operations. Nested evaluations
share deadlines and restore the outer interrupt handler; nesting is capped at 16. Global
bindings are defined directly so an untrusted setter cannot execute outside a budget. No
module loader, OS/shell module, filesystem host access or Promise job pump is installed.

Results cross the boundary as JSON text; undefined and non-JSON results return nil. Native
regex backtracking, recursion, memory failures, serialization/error conversion and cancellation
have regression coverage. This is not a strict wall-clock guarantee for every native engine
operation or queue wait and is not process isolation.

Tests include 50 timeout/recovery cycles and 50 ownership/release cycles; weak references are
not a leak detector. The integrated C probe also executed successfully in an isolated iOS
17.2 simulator (50 nested-host timeout/recovery cycles and cross-thread cancellation). The
Xcode app build passed; complete interactive-device and bridge parity remain distinct checks.

# Source runtime: v0.3.1

v0.3.0 introduced source libraries and pre-update hooks. v0.3.1 routes the app's existing
script entry points through the pinned QuickJS adapter in `Runtime/`; both SwiftPM Core
and the Xcode application compile it. JavaScriptCore and its private timeout API are not
used by the script engine. This is a compatibility subset of Android's Rhino/Java surface.

## Source libraries and hooks

`BookSource.jsLib` is modeled, editable and retained by import/export/backup. Inline code
runs before source rules and headers in each engine's context. A flat JSON name-to-HTTP(S)
URL map loads in declaration order. Only text is cached; globals and live contexts are
never shared between engines. Non-URL map values are ignored, following SharedJsScope.

Downloads send no source/login headers or automatic cookies. Successful, nonempty responses
have a post-download 1 MiB cap; declarations have at most 16 entries. The text cache is
memory-only and bounded by NSCache; changed content at an unchanged URL is not revalidated.
Library download waits observe cancellation and a shared 30-second request budget. These
are not streaming response-size limits. Engine source, result, heap and stack limits are
separate and documented in the adapter provenance notes.

`preUpdateJs` runs before explicit refreshes from the reader, shelf and detail page. Initial
combined detail/TOC loading keeps the opt-out default. `java.refreshTocUrl()` refreshes normal
details and updates the book visible to subsequent statements. `java.reGetBook()` searches
one page of the current source for an exact trimmed name/author match before requesting the
new details/directory. Both helpers reject calls outside the hook. Hook book variables
reach subsequent TOC parsing, and identity relocation preserves current shelf progress,
group and order; deleted records are not resurrected and destination conflicts are rejected.

This does not implement Android's entire precise-search/variable-merge behavior, every
book/chapter property, arbitrary nested hook templates, or RSS source authentication.

## Evaluation and host calls

`JSEngine` exposes the existing Java/source/book methods with JSON host calls. HTTP response
objects retain `body()`, `statusCode()`, `url()` and `text`. Variable maps, captured login
headers, hashing/base64/time helpers, header evaluation and directory formatting retain
regression coverage. HTML nodes enter scripts as HTML strings, rather than native DOM
objects. Remaining Android methods are tracked in Plan.md; unsupported APIs are not emulated
with site-specific URLs or metadata guesses.

The VM has public interrupt, heap and stack controls. Evaluations use a monotonic deadline;
source engines default to 15 seconds, pre-update hooks to 30 seconds, and replacement rules
use their configured remaining budget (maximum 60 seconds). Nested host evaluations share
the outer deadline and restore its interrupt handler. Native evaluation nesting is capped
at 16. Heap defaults for app engines are 64 MiB, source code 2 MiB and JSON bindings/results
8 MiB. The standalone adapter has smaller defaults. Blocking Atomics.wait is disabled.

Cancellation is checked during VM interrupt polling and native HTTP waits. Replacement
loops stop instead of leaving an abandoned JavaScriptCore worker. Cancelled hook workers
accept later work. Formatting timeout aborts that formatting task rather than repeating a
runaway script across every chapter. Library initialization and JSON serialization/error
conversion also run through bounded or cancellable paths. Category parsing has an async
entry so source scripts and HTTP waits do not execute on the UI actor.

The adapter is serialized within a runtime. Its execution budget starts after acquiring the
lock; it does not promise cancellable queue waits. Host bridges execute on the evaluating
thread and must bound their own native work. Regex backtracking is tested with the pinned
engine's public interrupt path; arbitrary expensive native operations, allocation/GC and OS
scheduling are not a strict wall-clock guarantee. There is no process isolation, module
loader, Promise job pump or complete Android Java object model.

## Validation

The offline suite reports 377 tests, three external-sample skips, zero failures. It includes
source library order/cache/credential exclusion, hooks/relocation, existing header/login/rule
fixtures, 50 loop recovery cycles, native regex interruption, nested host deadlines, native
setter protection, cancellation, recursion/allocation failures, serialization/error conversion,
ownership checks, UI-actor category cancellation and cancelled hook worker-pool recovery.

The integrated C adapter probe ran on an isolated iOS 17.2 simulator: 50 nested-host timeout/
recovery cycles, cross-thread cancellation and explicit context/runtime destruction passed.
The app simulator build also passed. This is not a leak-detector or full interactive-device
result. A live detail/TOC/chapter smoke test was attempted but skipped because book.xkvi.top
failed TLS connection; it is not recorded as parser acceptance.

See [upstream provenance and licensing](../Runtime/UPSTREAM.md), the [implementation sequence](ImplementationRoadmap.md),
and `RuntimeIntegrationTests` / `QuickJSRuntimeTests` for the verification surface.

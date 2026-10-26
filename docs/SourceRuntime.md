# v0.3.0 source runtime — implementation notes

Release scope: `v0.3.0` includes this source-runtime foundation and the interruption investigation. The adapter implementation is scheduled for `v0.3.1`; the broader v0.3.x roadmap is separate.

## Implemented foundation

`BookSource.jsLib` is now a modeled field, editable in the source editor and preserved by import, export and backup. `JSEngine` loads the library before source rules or header evaluation:

- Inline JavaScript executes in each engine's own context.
- A flat JSON map of library names to absolute HTTP(S) URLs is downloaded and evaluated in declaration order, following Android `SharedJsScope`'s map shape. Non-URL values are ignored, as on Android.
- Only script text is cached. No live JS contexts or mutable globals are shared between books or sources. This intentionally differs from Android's sealed shared scope.
- Downloads send neither source/login headers nor automatic session cookies. Responses must be successful and nonempty; a post-download 1 MiB size check and a 16-library declaration limit apply. These checks are not streaming download or VM memory limits.
- Syntax and dependency failures are surfaced before search, detail, explore-list and uncached chapter requests. The legacy nonthrowing category API returns an empty category list for library initialization failure.
- The cache is memory-only, bounded by `NSCache`, and cleared by `SourceLibraryStore.shared.clearCache()` or process restart. A changed remote script at the same URL is not automatically revalidated. Different library declarations create fresh contexts.

`preUpdateJs` runs before a refresh directory request, with three entry points wired: reader refresh, shelf refresh, and explicit detail-page refresh. An initial combined details/directory fetch keeps Android's opt-out default; core callers can pass `runPreUpdateJs: true` explicitly.

- `java.refreshTocUrl()` runs the normal details-only service and exposes the updated book to the next statement in the hook.
- `java.reGetBook()` searches the same source's first page for an exact trimmed name + author match, refreshes the selected book's details, and uses its new directory URL. It does not request the expired URL first.
- Hook calls to `java.get` / `java.put` use the book's variable map, so values reach subsequent directory parsing. Existing `book.getVariable` / `putVariable` also work.
- The two refresh helpers are rejected outside the hook. Script errors propagate instead of yielding a successful partial directory.
- Relocation replaces the original shelf slot and preserves current progress, group and order. It does not resurrect a removed book or overwrite an existing destination entry. Conflicting identities are left unresolved. Reader memory caches are rebuilt when book identity changes.
- Native async network services run on a separate task while the hook worker waits. Hook workers never block the UI executor. The native helper calls share a 30-second wait budget and cancel their network task on cancellation / timeout. At most two hook workers execute concurrently.

These are compatibility subsets. The hook's book object and Java bridge do not expose every Android property/method. Search only considers one page and exact name/author matching; it does not reproduce Android's complete precise-search or search-result variable merge behavior. Hook execution does not expand arbitrary nested template expressions. RSS source libraries and RSS login contexts remain separate work.

## Interruption decision

The installed public JavaScriptCore SDK headers expose no execution time-limit setter. WebKit declares `JSContextGroupSetExecutionTimeLimit` in its [private header](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextRefPrivate.h); the app does not link it or look it up dynamically.

A returned timeout or cancellation does **not** terminate JavaScriptCore execution. A started pure JavaScript loop can still occupy a worker and continue script side effects. Cancelling queued work avoids starting it, and native refresh helper waits are cancellable, but an already-running script has no hard interrupt. The two-worker cap does not guarantee recovery: two runaway hooks can prevent later hooks from starting, and cancelled queued operations still need the workers to drain. Library initialization and other existing JS entry points retain the same underlying limitation. This feature branch is not ready to be described as an isolated or fully bounded script runtime.

QuickJS documents public [interrupt, heap and stack controls](https://bellard.org/quickjs/quickjs.html#Execution-timeout-and-interrupts). The [standalone probe](../tools/runtime_probe/README.md) interrupted 50 loop evaluations, recovered each context, and freed each runtime on macOS. Its core also cross-compiled for iOS arm64. QuickJS has **not** been integrated into the app.

The v0.3.1 milestone is a native runtime adapter with the existing bindings, cancellation and deadline signals, bounded host calls, iOS loop / recursion / allocation tests, and resource cleanup checks. Native operations such as expensive regular expressions and large-number work need separate verification; the loop probe does not prove every operation respects a wall-clock deadline.

## Validation

Regression tests cover library order and cache isolation, credentials/cookie exclusion, failed dependencies, field round trips, both refresh helpers, direct hook mutations, cross-stage variables, cancellation before dispatch and during a native request, shelf relocation and identity conflicts. The existing suite also covers the v0.2.8.2 theme, introduction and title regressions.

See `SourceRuntimeTests`, the application `BookStoreTests`, and `Plan.md` for the current test/build results. No live-source or device acceptance of library-dependent or hook-dependent sources is implied by deterministic mocked-network tests.

## v0.3.1 adapter progress

The first implementation step is now an independent `LegadoRuntime` SwiftPM product with a
small C adapter and pinned, unmodified QuickJS sources. It is not linked into the Xcode app
target or used by `JSEngine`. See [provenance, API boundaries and limitations](../Runtime/UPSTREAM.md).
Seven new regression methods pass on macOS; the six C files and Swift adapter also compile
for iOS arm64 device and simulator. The full offline suite reports 370 tests, three skipped,
zero failures. iOS execution, host bridge migration and application integration remain.

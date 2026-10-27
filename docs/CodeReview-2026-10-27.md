# Follow-up code audit — 2026-10-27

Scope: the v0.4.0 source/session/browser integration and its uncommitted live-source follow-up.
This is a focused review, not a claim that the entire Android migration has no defects.

## Fixed findings

1. Login recovery used a full response URL as baseUrl. Android AnalyzeUrl normalizes the
   requested URL to scheme/host/port before its response check. The corrected hook now
   handles search and chapter requests, including a different host/port and redirects;
   rule parsing still receives the full final response URL.
2. Self-invoking loginUrl scripts could submit login twice. The fallback login() call now
   runs only when evaluating loginUrl has not already emitted a new login header.
   Function-only scripts and explicit button actions remain supported.
3. Cancelled/failed/deleted browser downloads left unused per-download directories.
   One cleanup helper now removes the file and its empty immediate download folder.
   Stopping clears the loading indicator; late destination callbacks for untracked
   downloads are rejected, and completion always refreshes the active count.
4. Live tests duplicated header-script evaluation and printed partial credentials.
   They now use the production header resolver and do not print cookies or tokens.
   A duplicate reachability request was removed.

## Hardcoded values and unused code

No production branch for this particular source, account, novel or chapter was added.
Site URLs, selected chapter positions and deliberately invalid tokens in live tests are
explicit fixtures, not application behavior. Existing page/deadline/size limits are
intentional bounded-work policies and were retained. Required UIKit coder initializers
were not treated as dead code merely because normal app flow uses programmatic views.
No credentials or live session tokens were found in changed repository files.

## Verification

- Offline suite: 446 tests, 3 external-file skips, 0 failures.
- iOS Simulator Debug production build passed; source registration and diff checks passed.
- Dedicated iPhone 11 / iOS 15.5 probe: 21/21 production-helper checks passed, including
  download completion/import/deletion, empty incomplete-folder cleanup and stop state.
  Probe fingerprint: `def1f56888184e7da4c678b737572429c3277ac0c3bf57e8ebea3c166bfeede2`.
- Expanded real-source flow passed: 1 integration test, 0 skips, 0 failures (21.78 seconds).
  The real-source flow is recorded in [the live report](LiveSourceVerification-2026-10-27.md).
  Some chapters are public, so the chapter recovery check supplies the source's expiry
  response to the hook, then performs real login and chapter HTTP requests; search
  recovery is triggered by an actual deliberately invalid Authorization header.

These fixes are included in v0.4.1; the original v0.4.0 IPA predates them.

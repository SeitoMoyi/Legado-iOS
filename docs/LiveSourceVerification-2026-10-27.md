# Real-source verification — 2026-10-27

Source: https://list.xkvi.top/legado/booksource.json (机翻机器人).
The user's updated proxy made authenticated API requests work. A root-page HTTP 502 is
not a reliable source-health check; its authenticated APIs returned usable results.
Credentials were supplied only to the test process environment, not checked into the
repository or recorded in this report. Tests use the isolated test home, not app data.

## Scope and results

The expanded `LiveSourceTests.testXkviJifanLoginFlow` passed with no skips:

- Real rule-link download and source preview decoding.
- Real rule-subscription download and matching source identity.
- Production form-login service, authenticated search and distinct second-page results.
- Exact live title/author lookup through book-list import.
- Book detail introduction contains parsed text, not the previously reported JS fragment.
- Chapter list has contiguous indices; first and later chapters contain readable text.
- Forced chapter fetch followed by identical cached content.
- Explicit source refresh preserves book identity and returns chapters.
- Prefetch starts with five uncached chapters; cancellation returns within three seconds
  and stops before the entire queue is cached. A subsequent chapter request succeeds.
- Authenticated discovery categories include reading history; the All category returns books.
- Deliberately invalid account session is refreshed by the actual loginCheckJs hook;
  the refreshed header is stored and reused by a new engine with no embedded loginHeader.

One source-dependent bug was reproduced and fixed for v0.4.1:
`JSEngine.checkedResponse` changed `baseUrl` to the full search URL before loginCheckJs.
This source builds its login address from `baseUrl`, so recovery posted to the wrong URL.
Android's AnalyzeUrl normalizes the requested URL to its scheme/host/port before
running that hook. The fix uses that origin for the hook, then the full final response
URL for parsing. This covers search and chapter requests, including a different request
host/port and redirects. A focused
regression verifies both contexts; the real expired-session flow passed after the fix.

Final focused run: 2 XCTest methods (the expanded live integration and the new response
context regression), 0 skips, 0 failures. The existing source-flow suite also passed
alongside an earlier successful expanded live run (11 methods total).

## Limits

The subsequent code audit adds checks for chapter-specific expired-login recovery and
prevents duplicate submission when loginUrl already calls login(). See
[the audit record](CodeReview-2026-10-27.md).

This run exercises actual production services and scripts on macOS with QuickJS, not
simulator navigation or a visual reading-layout check. It does not establish title line
counts, theme contrast, WebKit login UI, or bookshelf-exit UI behavior. The cancellation
check covers the production prefetch service used by the reader. This source is a book
source, not an RSS source; RSS rendering and unrelated offline-only features were not
part of this real-source run. No claim is made about all books, sources or Android parity.

The response-context fix and expanded tests are included in v0.4.1; the v0.4.0 IPA
predates this follow-up fix.

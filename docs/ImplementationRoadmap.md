# Android parity: implementation sequence through v0.4.0

The reference is the Android snapshot in `../app` and `../modules`, not an assumed upstream
release. Code and data fixtures take precedence over old completion claims. Patch releases
carry independently verified steps; v0.4.0 is the consolidated ecosystem/data milestone,
not a claim that every Android format and platform integration is implemented.

| Release | Concrete scope | Acceptance / reference |
|---|---|---|
| v0.3.0 | Source library and pre-update foundation; reported reader regressions | Published `dd070f2`; 363 offline tests, unsigned archive and GitHub release passed. |
| v0.3.1 | Interruptible app script engine, current Java/source/book bridges, bounded host waits, cancellation recovery | Existing source/rule/login tests plus native loop/regex, nested bridge, cancellation and iOS runtime probe; Xcode compile and archive. No private JavaScriptCore API. |
| v0.3.2 | Android group bitmasks and migration of existing iOS IDs; group management; modeled backup members for groups, dictionaries and HttpTTS | `BookGroup.kt`, `BookDao` group queries, `Backup.kt`/`Restore.kt`; imported Android-shaped fixtures must behave in the shelf and survive export. |
| v0.3.3 | Preserve unmodeled backup members, all reader styles/current selection and iOS preferences; read-config behavior and rule subscriptions | Preserve raw members without pretending they execute; subscription models/update rules follow Android `RuleSub` and use explicit merge behavior. Deterministic ZIP and HTTP fixtures. |
| v0.3.4 | Browser/login and RSS source context/category/rendering gaps; rule-link import | `BaseSource`, login RowUi/check hooks, Android RSS rule evaluation; shared authenticated context and bounded verification retries. Browser UI and downloads use platform APIs. |
| v0.3.5 | Shelf import/logging and reader behavior gaps required by these flows; integration regressions | Source/backup/subscription flows must work together; invalidate obsolete requests and preserve user edits and progress. |
| v0.4.0 | Consolidation, code/doc audit, migration checks and release | Run the complete offline suite, platform builds/archive, simulator probes and available live-source smoke tests; record actual skips and device-only gaps. |

## Release discipline

- A plan row does not count as implemented because JSON keys can be imported or edited.
- Unknown backup members can be preserved without claiming their Android behavior exists.
- Tests use isolated stores and temporary simulators. The user's simulator and account
  credentials are not reset; no user acceptance step blocks automatable implementation.
- Network downtime is distinct from a parser failure; skipped live checks remain visible.
- Source-specific URL guesses and metadata fallbacks are not substitutes for source rules.
- Before pushing a release: update VERSION and Xcode metadata, check source registration,
  run appropriate regressions/builds, and publish notes reflecting the actual final scope.
- Formats (MOBI/AZW3/UMD/PDF), named themes/backgrounds, dedicated comic UI and platform
  extensions remain later v0.4.x/1.0 work, separately scoped and never marked complete by
  reaching the v0.4.0 version number.

The matrix in `Plan.md` continues to record remaining Android differences. This sequence
replaces the old undifferentiated v0.3.x bucket; discoveries may refine a row, with the
reason and verification recorded before its release.

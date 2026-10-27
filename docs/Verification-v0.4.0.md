# v0.4.0 verification — 2026-10-27

Reference: the local Android snapshot, not assumed upstream parity. Version 0.4.0, build 9.

- Offline XCTest: **443 tests, 3 skipped, 0 failures** using an isolated home. The skipped tests need external EPUB / Android ZIP fixtures. There are 450 declared test methods including 7 live-source tests.
- Native integration: **18/18 passed on each of iPhone 11 / iOS 15.5 and iPhone 13 / iOS 17.2** in dedicated disposable simulators. No user simulator was reset or modified.
- Release: unsigned arm64 device archive; version/build and bundled QuickJS license checked. GitHub independently runs offline tests and archives the IPA.
- Live xkvi source: explicitly skipped after book.xkvi.top TLS connection failure; no claim of current end-to-end compatibility. No physical-device interaction acceptance.

Native source fingerprint (both reports): `606d7c8f632767a4d8fbe568ac3d08778683aa910df33a801e47115a5474b71b`.
The harness hashes the production Swift files it compiles, plus its own Swift entry point; see [reproduction instructions](../tools/native_probe/README.md).

## Native checks

- native response replacement and synchronous host HTTP
- native QuickJS deadline
- native QuickJS recovery
- native RSS library, identity, headers and JSON rules
- native rule-link download preview
- native backup styles and selection
- native opaque backup bytes
- native image EPUB export and reimport
- production RSS WebKit custom CSS
- production RSS content JavaScript disabled
- production RSS document base URL
- production WebKit cookie bridge and relative image loading
- production RSS reused view enables JavaScript and reloads
- production RSS reused view updates CSS
- production RSS base URL opt-out
- production WebKit download completion
- production browser downloaded TXT imports with original filename
- production WebKit logout clears scoped cookies

These use fake loopback HTTP fixtures and isolated stores. The harness compiles the actual production renderer, browser, cookie helper, core services and script adapter; it is not a UI tour of the full app. Local screenshots verified the RSS document rendering. No private source credentials are stored in these fixtures.

## Remaining scope

Full Java/crypto bridge, full JSONPath/XPath, webJs/sourceRegex network execution, behavior for seven raw-only backup configurations, MOBI/AZW3/UMD/PDF, background images/comic interface, platform extensions, per-group sorting and smooth automatic scrolling remain later work. See [Plan.md](../Plan.md) and [roadmap](ImplementationRoadmap.md).

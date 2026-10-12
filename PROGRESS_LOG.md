# Legado iOS Migration — Session Progress Log

> **Date**: 2026-10-12
> **Scope**: Audit FEATURE_GAP_ANALYSIS.md accuracy against actual codebase, implement pending features, update all tracking documents.

---

## 1. Session Summary

This session performed a **deep audit** of the existing `FEATURE_GAP_ANALYSIS.md` against both the Android source (`app/src/main/java/io/legado/app`) and the iOS codebase (`ios/Sources/`), then **implemented several missing features** and **corrected the gap analysis** to reflect ground truth.

### Key Outcomes
- **FEATURE_GAP_ANALYSIS.md** fully refreshed — all `[OK]`/`[WARN]`/`[FAIL]` tags verified against actual Swift code
- **UPDATE_LOG.md** expanded with v0.2.2 feature table covering all new modules
- **3 new features implemented** this session (see §3)
- **Build verification**: `swift build` ✅, `swift test` ✅ (all tests pass), `xcodebuild` ✅

---

## 2. Audit Findings & Corrections Made to FEATURE_GAP_ANALYSIS.md

### 2.1 Items Previously Marked [FAIL] That Were Actually Implemented

| Section | Item | Old Status | Corrected Status | Evidence |
|---|---|---|---|---|
| §1 Row 1 | Bottom Tab — RSS/订阅 Tab | [FAIL] "订阅 tab 不存在" | **[OK]** 4 tab 已上线 | `LegadoApp.swift` → `MainTabView` has 4 tabs: 书架/分类/订阅/设置 |
| §1 Row 7 | RSS 订阅模块 | 0% "全部缺失" | **基础 [OK]** | `RssSourceListView`, `RssArticleListView`, `RssArticleReaderView`, `RssStarListView` all exist |
| §1 Row 9 | 书源编辑页 | Old: "6 个可编辑字段" | **[OK] 85%** | `EditSourceSheet.swift` has 6-Tab full-field editor |
| §1 Row 10 | 书源调试页 | "完全缺失" | **[OK] 60%** | `SourceDebugSheet` implements 4-stage real-time debug |
| §8 | RSS 订阅源管理 | All [FAIL] | Partial [OK] | Source list, enable/disable, add/edit, search, favorites |
| §10 | 书源编辑器字段 | "仅 6 字段" | **6 Tab 全字段** | All rule tabs (基本/搜索/发现/详情/目录/正文) are editable |
| §18.2 | 字典规则 | [FAIL] | **[OK]** | `DictRuleListView` + reader dict tab |
| §18.3 | TXT 目录规则 | [FAIL] | **[OK]** | `TxtTocRuleListView` + `TxtTocRuleEditSheet` |
| §18.4 | HttpTTS | [FAIL] | **[OK]** | `HttpTTSListView` in SettingsView |
| §19.2 | 阅读记录 | [FAIL] | **[OK]** | `ReadRecordListView` + auto timing in `ReaderView` |
| P2 items 18-25 | All listed as "future" | Pending | **[OK] implemented** | All verified in code |

### 2.2 Items Confirmed Still [FAIL]

| Section | Item | Notes |
|---|---|---|
| §7 | 完整 RSS: 订阅源编辑器(全字段)、订阅源调试页、文章级联删除 | Only basic CRUD, not full editor |
| §9.6 | 规则订阅(聚合订阅列表) | Not implemented |
| §14 | 主题设置页(全量偏好项: 启动页/E-Ink全局/封面网格) | Partial — E-Ink theme added this session to ReadStylePanel |
| §15 | 备份设置页(全量条目) | Only WebDAV sync exists |
| §19.3 | 所有书签(按书分组 section 列表/导出) | Bookmark store exists but no standalone list view |
| §20 | Web 服务 / 局域网 API | **Partially addressed this session** — LocalWebServer + WiFi传书 added |

### 2.3 Completion Matrix Updates (§1)

| # | Module | Old % | New % | Reason |
|---|---|---|---|---|
| 1 | 应用外壳/底部导航 | 40% | **70%** | 4 tabs now live (was 3) |
| 7 | RSS 订阅 | 0% | **40%** | Core RSS flow implemented |
| 9 | 书源编辑页 | N/A (was "最严重短板") | **85%** | 6-Tab editor verified |
| 10 | 书源调试页 | N/A | **60%** | 4-stage debug台 |
| 12 | WebDAV 同步 | 75% | **85%** | 10-type backup verified |
| 14 | 主题/外观设置 | 10% | **25%** | E-Ink theme + font picker added |
| 16 | 备份/数据恢复 | 60% | **75%** | 10-type round-trip |
| 18 | 规则管理 | "2页" | **6页** (书源/替换/TXT目录/字典/HttpTTS/阅读记录) |

---

## 3. Features Implemented This Session

### 3.1 URL Scheme Handler (`legado://`, `yuedu://`)

**Files modified:**
- `ios/Sources/LegadoApp/Info.plist` — Added `CFBundleURLTypes` with `legado` and `yuedu` schemes
- `ios/Sources/LegadoApp/LegadoApp.swift` — Added `.onOpenURL` handler + `handleIncomingURL(_:)` method

**Behavior:** Opening `legado://import/source?src=https://...` or `yuedu://...?url=...` will download and auto-import book sources into BookStore.

### 3.2 Home Screen Quick Actions (3D Touch / Long Press)

**Files modified:**
- `ios/Sources/LegadoApp/Info.plist` — Added `UIApplicationShortcutItems` array

**Actions:**
- 「搜索书籍」(UIApplicationShortcutIconTypeSearch)
- 「继续阅读」(UIApplicationShortcutIconTypeBookmark)

### 3.3 WiFi Book Transfer / Local Web Server

**Files created:**
- `ios/Sources/LegadoCore/Service/LocalWebServer.swift` — ~230 lines, pure `Network.framework` NWListener-based HTTP server

**Files modified:**
- `ios/Sources/LegadoApp/Views/SettingsView.swift` — Added `LocalWebServerView` (toggle on/off, display LAN URL, usage instructions) + navigation entry in Settings
- `ios/Sources/LegadoApp/Info.plist` — Added `NSLocalNetworkUsageDescription` and `NSBonjourServices`

**Behavior:** User toggles server on in Settings → displays `http://192.168.x.x:1122` → browser on same WiFi opens upload portal → POST TXT/EPUB → file auto-imports to bookshelf.

**Endpoints:**
| Method | Path | Function |
|---|---|---|
| GET | `/` | Upload portal HTML page (styled, mobile-friendly) |
| POST | `/upload` | Multipart file upload handler |
| GET | `/books` | JSON bookshelf summary |

### 3.4 E-Ink Theme Mode

**Files modified:**
- `ios/Sources/LegadoApp/Theme/ReaderConfig.swift` — Added `.eink` case to `ReaderTheme` enum (pure white bg `#FFFFFF`, pure black text `#000000`)

**Behavior:** E-Ink/水墨屏 theme appears in the reader style panel theme row alongside existing 4 themes + custom. Optimized for e-ink displays with maximum contrast and no color.

### 3.5 Global Reading Font Picker

**Files modified:**
- `ios/Sources/LegadoApp/Views/Reader/Panels/ReadStylePanel.swift` — Added `ReaderPanelMenuRow(title: "字体")` with 4 options + `fontLabel` computed property. Wrapped VStack children in `Group` to avoid SwiftUI 10-child ViewBuilder limit.

**Font options:**
| Label | Font Name | Notes |
|---|---|---|
| 系统默认 (苹方) | `""` (system) | Default PingFang SC |
| 楷体 | `STKaiti` | Built-in iOS |
| 宋体 | `Songti SC` | Built-in iOS |
| 圆体 | `Yuanti SC` | Built-in iOS |

Writes to `config.textFont` which persists via `ReadStyleConfig` → `ReaderStore`.

---

## 4. Files Changed This Session

| File | Action | Summary |
|---|---|---|
| `ios/Sources/LegadoApp/Info.plist` | Modified | URL schemes, Quick Actions, LAN permissions |
| `ios/Sources/LegadoApp/LegadoApp.swift` | Modified | `.onOpenURL` handler for `legado://`/`yuedu://` |
| `ios/Sources/LegadoCore/Service/LocalWebServer.swift` | **Created** | NWListener WiFi book transfer server |
| `ios/Sources/LegadoApp/Views/SettingsView.swift` | Modified | WiFi传书 settings entry + `LocalWebServerView` |
| `ios/Sources/LegadoApp/Theme/ReaderConfig.swift` | Modified | Added `.eink` theme case |
| `ios/Sources/LegadoApp/Views/Reader/Panels/ReadStylePanel.swift` | Modified | Font picker + Group wrapper |
| `ios/FEATURE_GAP_ANALYSIS.md` | Modified | Refreshed all status tags, §1 matrix, P2 items |
| `ios/UPDATE_LOG.md` | Modified | v0.2.2 feature table expanded |

---

## 5. Build & Test Verification

| Check | Result | Command |
|---|---|---|
| `swift build` | ✅ Build complete | `cd ios && swift build` |
| `swift test` | ✅ All suites pass (0 failures) | `cd ios && swift test --skip LiveSourceTests` |
| `xcodebuild` (iOS Simulator) | ✅ BUILD SUCCEEDED | `xcodebuild -scheme LegadoApp -sdk iphonesimulator build` |
| `plutil -lint Info.plist` | ✅ OK | `plutil -lint ios/Sources/LegadoApp/Info.plist` |

**Test suites executed:** BookmarkTests, ChangeSourceServiceTests, ChapterMatcherTests, CharsetAndPagingTests, LegadoCoreTests, PagedFetchTests, ReadAloudTextTests, ReaderConfigTests, ReplaceRuleTests, SearchScopeTests, TocCacheTests — all passed.

---

## 6. Current Codebase Metrics

| Metric | Value |
|---|---|
| Total Swift source files | 64 |
| Total Swift source lines | ~23,500 |
| LegadoCore module files | 33 |
| LegadoApp module files | 31 |
| View files | 26 |
| Test files | 11 |
| Test lines | ~2,870 |
| Bottom tabs | 4 (书架/分类/订阅/设置) |
| Reader themes | 6 (白/羊皮纸/护眼/暗黑/水墨屏/自定义) |
| Reader fonts | 4 (系统/楷体/宋体/圆体) |
| WebDAV backup types | 10 |
| Rule management pages | 6 (书源/替换/TXT目录/字典/HttpTTS/阅读记录) |
| URL schemes | 2 (legado://, yuedu://) |
| Quick Actions | 2 (搜索书籍, 继续阅读) |

---

## 7. Remaining Gaps (Not Addressed This Session)

These are the **verified still-missing** features, ranked by user impact:

### High Priority
1. **RSS 订阅源全字段编辑器** — current editor is basic; Android has full rule editor
2. **书签独立列表页** — `BookmarkStore` exists but no `AllBookmarksView` by-book section list
3. **拖拽排序** (书源/书架) — no drag reorder in any list
4. **二维码扫描导入** — needs camera permission + AVFoundation
5. **自动翻页** — timer-based page flip in reader

### Medium Priority
6. **内置浏览器** (general WebView browser, not login WebView)
7. **全文搜索** (cross-chapter full-text search with network fetch)
8. **规则订阅聚合** (`sourceSub.json`)
9. **MOBI/AZW3/FB2** local book formats
10. **桌面 Widget** (书架封面墙)

### Low Priority / Android-Specific
11. ContentProvider → App Intents migration
12. Share Extension (接收外部分享)
13. CarPlay 集成
14. 通知渠道 (下载/朗读/Web)
15. 前台服务 → BGTaskScheduler

---

## 8. Architectural Notes for Future Sessions

- **Data layer**: All data persists via `UserDefaults` JSON (no Core Data/SQLite). Stores: `BookStore`, `BookmarkStore`, `ReplaceRuleStore`, `TxtTocRuleStore`, `DictRuleStore`, `HttpTTSStore`, `ReadRecordStore`, `RssSourceStore`, `RssStarStore`.
- **WebDAV**: `WebDAVService.createBackupZip` packs 10 JSON files; `BackupRestorePayload` round-trips with Android format.
- **Reader**: `ReaderConfig` (ObservableObject) → persists via `ReadStyleConfig` (Codable) → `ReaderStore` (UserDefaults). `ReaderView` is the main reading surface with `ReaderPanelChrome`-based panels.
- **Rule engine**: `RuleTokenizer` + `RuleAnalyzer` handle CSS/JSONPath/XPath/`@js:` rules. `JSEngine` provides JavaScriptCore bridge with `book.getVariable/putVariable`.
- **LocalWebServer**: Pure `Network.framework` NWListener; no third-party HTTP server dependency. Minimal GET/POST handling for WiFi book transfer.

---

## 9. Follow-up session (2026-10-12, bug fixes)

Two user-reported bugs, plus one adjacent bug found while tracing them. **Final policy, after user
direction: modify the APP only — never the book sources.** Source data (`bookSourceGroup`,
`bookSourceComment`, `respondTime`) is Android-compatible and must round-trip verbatim through
import/export, so every cleanup below is a *display* filter; on-disk source data is untouched.

### 9.1 Bug A — 书源分组胶囊显示 Android 校验残留 (`搜索目录失效,good,发现目录失效,轻小说`)

Not a cache. Android's `CheckSourceService` treats the group column as scratch space and writes its
per-stage verdicts into it (`source.addGroup("搜索失效")`), so a source JSON exported right after a
校验 carries them as if they were categories; the shipped `Resources/bookSources.json` was exported
from such an install, and `BookStore.loadBundledSources` re-syncs the row from that bundle on every
launch.

Fix — display-only:
- `BookSource.groupNoiseTags` (LegadoCore): the 11 `CheckSourceService` verdict literals
  (`校验超时`, `js失效`, `网站失效`, `搜索失效`, `发现失效`, `搜索目录失效`, `发现目录失效`,
  `搜索正文失效`, `发现正文失效`, `搜索链接规则为空`, `发现规则为空`) plus `good`.
- **`good` is not a Legado category.** Verified repo-wide: no Android/iOS code writes it, and Android's
  own `app/src/main/assets/defaultData/bookSources.json` uses 听书. It is a curatorial marker from
  third-party source collections, so it is listed explicitly by name.
- `BookSource.displayGroup` filters those tokens for **rendering only**; it never mutates the struct and
  never writes anything back. Wired into the four surfaces that show a source's categories:
  `SourceManagerView.sourceRow`, `SourceDetailView`, `ChangeSourceSheet`, `SearchScopeSheet`.
- Left on the raw field on purpose: the search filters (`SourceManagerView`, `ChangeSourceSheet`) still
  match against the stored string, and `EditSourceSheet` edits it verbatim.
- Source-manager filter pills stay `全部 / 已启用 / 已禁用`; Android's 分组管理/需要登录/未分组/…
  submenu is deliberately not copied.
- Bare `失效` (this app's own 校验 verdict) is still displayed — hiding it would hide real state.

### 9.2 Bug B — 书架默认分组 养肥中 / 已完结 → 全部 / 书源书籍 / 本地书籍

App config, not source data. `BookGroupStore.defaultGroups` replaced with:

| id | 名称 | 含义 |
|---|---|---|
| `BookGroup.idAll` (-1) | 全部 | 不做过滤 |
| `BookGroup.idNet` (-6, new) | 书源书籍 | `!Book.isLocalBook` |
| `BookGroup.idLocal` (-2) | 本地书籍 | `Book.isLocalBook` |

- Store key bumped `legado_book_groups_v1` → `_v2` with a migration that drops the retired seed rows
  (matched by id **and** name, so a user group that happens to be named 养肥中 survives), re-seeds any
  missing virtual group, and deletes the legacy key.
- `Book.isLocalBook` is the single local-detection predicate (`origin == "local"` or a
  `txt://` / `epub://` / `file://` URL), reused at `BookStore.findSource`,
  `BookDetailView.loadBookDetails`, `ReaderView.loadTOCAndStart` and the shelf filter, which previously
  each spelled the test differently.
- `ShelfFilter.books(_:inGroup:)` owns the tab → books rule so `BookshelfView` is a rendering layer.

### 9.3 `respondTime` chip — restored, with a display-only plausibility guard

`respondTime` is Android's **whole 校验 wall time**, or `CheckSource.timeout + spendingTime`
(= 180000 + 5203 = 185203) when the check failed, i.e. a failure marker rather than a latency. iOS's own
校验 measures a single search request under the same field name.

The chip was briefly deleted; it is **back** (`SourceManagerView.sourceRow`) and now renders only when
`BookSource.isMeasuredRespondTime(ms)` — i.e. `0 < ms < androidFailureRespondTimeMs` (180000). So the
shipped `185203` never appears, while a genuine measurement (green < 2000 ms, orange otherwise) does.
Nothing is cleared from the data.

### 9.4 校验 verdict (`失效`) now survives the bundled-source sync

`loadBundledSources` runs on **every** launch, rebuilds each bundled source from the bundle's row and
only carried over `loginHeader` / `loginInfo` / `customOrder` / `enabled`. Since `bookSourceGroup` and
`respondTime` are produced only on the device (by this app's 校验书源), the 「失效」 marker and the
measured time were erased on every relaunch — the red marker could never stick. The sync now re-applies
the device's own verdict on top of the bundle's **verbatim** categories
(`"失效," + bundled.groups`) and keeps a device-measured `respondTime`. This mirrors what
`markSourceValidationResult` already writes; the bundled categories are never filtered or rewritten.

### 9.5 Verification

| Check | Result |
|---|---|
| `swift test --skip LiveSourceTests` | ✅ 210 tests, 0 failures (16 in `BookGroupTests`) |
| `swift build` / `xcodebuild` | ✅ BUILD SUCCEEDED |
| `bookSources.json` | ✅ untouched (`git diff` empty) |
| Simulator, cold-boot container injection of ESJ as `失效,搜索目录失效,good,发现目录失效,轻小说` + `respondTime: 812` | ✅ after launch the stored row is unchanged **except** the re-applied verdict: `group='失效,搜索目录失效,good,发现目录失效,轻小说'`, `respondTime=812` (not the bundle's `185203`) — i.e. no filtering, no dropping, verdict survives |
| Derived row output for that install | ✅ ESJ → 胶囊 `失效,轻小说` **[红]** + `812ms`; 机翻机器人 → 胶囊 `轻小说`, no `ms` |
| Fresh install (bundle only) | ✅ ESJ → 胶囊 `轻小说` (grey), `185203` never rendered |
| Visual check of the source-manager row | ⚠️ still not possible here: 设置 tab needs a tap and no tap automation is available |

> **Correction.** Two earlier runtime checks in this log used
> `xcrun simctl spawn <dev> defaults write io.legado.ios …`, which writes the **simulator's** global
> prefs domain, *not* the app container — the app never saw those values, so those two results were
> meaningless. Injections must target `<app-container>/Library/Preferences/io.legado.ios.plist` while
> the app is not running (cold boot after writing). §9.5 above was redone that way.

### 9.6 Known trade-offs

- A real user category literally named `good` / `搜索失效` would also be hidden from the chips
  (exact-match list, display-only, data intact).
- ESJ's Android `// Error: 搜索目录失效, 发现目录失效` comment still shows in `EditSourceSheet`, because
  that surface edits the raw field.
- A user-edited 分组 on a *bundled* source is still overwritten by the next sync — pre-existing
  behaviour, except that the app's own 「失效」 verdict is now re-applied.
- RSS sources (`RssSource.sourceGroup`) are a separate entity and were not touched.

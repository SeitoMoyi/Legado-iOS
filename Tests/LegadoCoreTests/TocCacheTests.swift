import XCTest
@testable import LegadoCore

/// The cache-first TOC path (plan.md 批次 P0.5 B) hinges on two pure decisions: whether a cached
/// list is old enough to re-crawl, and whether a freshly crawled list is different enough to be
/// worth swapping in. Wrong answers mean either hammering the source on every open or yanking the
/// chapter list out from under a reader who is mid-page.
final class TocCacheTests: XCTestCase {

    private func chapter(_ title: String, _ url: String, index: Int = 0) -> BookChapter {
        BookChapter(bookUrl: "https://book.test", url: url, title: title, index: index)
    }

    func testMissingTimestampIsStale() {
        XCTAssertTrue(TocCache.isStale(fetchedAt: nil))
    }

    func testFreshTimestampIsNotStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fetched = now.addingTimeInterval(-60)
        XCTAssertFalse(TocCache.isStale(fetchedAt: fetched, now: now))
    }

    func testTenMinuteBoundaryMatchesAndroidUpToc() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(TocCache.isStale(fetchedAt: now.addingTimeInterval(-599), now: now))
        XCTAssertTrue(TocCache.isStale(fetchedAt: now.addingTimeInterval(-600), now: now))
        XCTAssertEqual(TocCache.refreshInterval, 600)
    }

    /// A clock that jumped backwards must not lock us into a stale list forever.
    func testFutureTimestampIsTreatedAsStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(TocCache.isStale(fetchedAt: now.addingTimeInterval(3600), now: now))
    }

    func testKeyIsStableAndBookSpecific() {
        XCTAssertEqual(TocCache.defaultsKey(bookUrl: "https://a/1"),
                       TocCache.defaultsKey(bookUrl: "https://a/1"))
        XCTAssertNotEqual(TocCache.defaultsKey(bookUrl: "https://a/1"),
                          TocCache.defaultsKey(bookUrl: "https://a/2"))
        XCTAssertTrue(TocCache.defaultsKey(bookUrl: "https://a/1").hasPrefix("legado_toc_time_"))
    }

    func testSameListIgnoresIndexRewrites() {
        let before = [chapter("第一章", "https://a/1", index: 0), chapter("第二章", "https://a/2", index: 1)]
        let after = [chapter("第一章", "https://a/1", index: 0), chapter("第二章", "https://a/2", index: 1)]
        XCTAssertTrue(TocCache.isSameList(before, after))
    }

    func testDifferentCountIsDifferentList() {
        let before = [chapter("第一章", "https://a/1")]
        let after = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2")]
        XCTAssertFalse(TocCache.isSameList(before, after))
    }

    /// A same-size update (one chapter renamed, or a new chapter replacing a placeholder at the
    /// tail) still has to be noticed, otherwise 追更 silently does nothing.
    func testTailTitleChangeIsDifferentList() {
        let before = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2")]
        let after = [chapter("第一章", "https://a/1"), chapter("第二章 修订", "https://a/3")]
        XCTAssertFalse(TocCache.isSameList(before, after))
    }

    func testHeadTitleChangeIsDifferentList() {
        let before = [chapter("序章", "https://a/0"), chapter("第一章", "https://a/1")]
        let after = [chapter("楔子", "https://a/9"), chapter("第一章", "https://a/1")]
        XCTAssertFalse(TocCache.isSameList(before, after))
    }

    func testEmptyListsCompareWithoutCrashing() {
        XCTAssertTrue(TocCache.isSameList([], []))
        XCTAssertFalse(TocCache.isSameList([], [chapter("第一章", "https://a/1")]))
    }

    func testTimestampRoundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: TocCacheTests.classNameForSuite())!
        defaults.removeObject(forKey: TocCache.defaultsKey(bookUrl: "https://book.test/x"))
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(stamp.timeIntervalSince1970, forKey: TocCache.defaultsKey(bookUrl: "https://book.test/x"))
        let restored = defaults.double(forKey: TocCache.defaultsKey(bookUrl: "https://book.test/x"))
        XCTAssertEqual(Date(timeIntervalSince1970: restored).timeIntervalSince1970,
                       stamp.timeIntervalSince1970, accuracy: 0.001)
        defaults.removePersistentDomain(forName: TocCacheTests.classNameForSuite())
    }

    private static func classNameForSuite() -> String { "LegadoTocCacheTests" }

    // MARK: - isAppendOnly (decides whether the index-keyed content cache survives)

    func testAppendingChaptersKeepsIndicesValid() {
        let before = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2")]
        let after = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2"),
                     chapter("第三章", "https://a/3")]
        XCTAssertTrue(TocCache.isAppendOnly(before, after))
    }

    func testIdenticalListsAreAppendOnly() {
        let list = [chapter("第一章", "https://a/1")]
        XCTAssertTrue(TocCache.isAppendOnly(list, list))
    }

    /// A chapter inserted near the front shifts every later index, so the cached bodies would
    /// be served to the wrong chapters.
    func testInsertionInMiddleIsNotAppendOnly() {
        let before = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2")]
        let after = [chapter("第一章", "https://a/1"), chapter("加更", "https://a/9"),
                     chapter("第二章", "https://a/2")]
        XCTAssertFalse(TocCache.isAppendOnly(before, after))
    }

    func testRenamedChapterBreaksAppendOnly() {
        let before = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2")]
        let after = [chapter("第一章 修订", "https://a/1"), chapter("第二章", "https://a/2")]
        XCTAssertFalse(TocCache.isAppendOnly(before, after))
    }

    /// Same title, different url means the source moved the chapter: the cached body is stale
    /// even though the index still lines up by title.
    func testUrlChangeBreaksAppendOnly() {
        let before = [chapter("第一章", "https://a/1")]
        let after = [chapter("第一章", "https://b/1")]
        XCTAssertFalse(TocCache.isAppendOnly(before, after))
    }

    func testShrinkingListIsNotAppendOnly() {
        let before = [chapter("第一章", "https://a/1"), chapter("第二章", "https://a/2")]
        let after = [chapter("第一章", "https://a/1")]
        XCTAssertFalse(TocCache.isAppendOnly(before, after))
    }

    func testAppendOnlyOnEmptyPreviousIsTrue() {
        XCTAssertTrue(TocCache.isAppendOnly([], [chapter("第一章", "https://a/1")]))
    }
}

extension TocCacheTests {
    func testMetadataOnlyChangesRefreshReaderWithoutDroppingContent() {
        let original = BookChapter(bookUrl: "b", url: "u", title: "章", index: 0)
        let fields: [WritableKeyPath<BookChapter, Bool?>] = [\.isVolume, \.isVip, \.isPay]
        for field in fields {
            var updated = original
            updated[keyPath: field] = true
            XCTAssertFalse(TocCache.isSameList([original], [updated]))
            XCTAssertTrue(TocCache.isAppendOnly([original], [updated]))
        }
        var updated = original
        updated.tag = "更新时间"
        XCTAssertFalse(TocCache.isSameList([original], [updated]))
        XCTAssertTrue(TocCache.isAppendOnly([original], [updated]))
    }

    func testLegacyMissingFlagsMatchFalseAndIgnoreIndexChanges() {
        let original = BookChapter(bookUrl: "b", url: "u", title: "章", index: 0)
        var legacy = original
        legacy.isVolume = nil
        legacy.isVip = nil
        legacy.isPay = nil
        legacy.index = 7
        legacy.tag = ""
        XCTAssertTrue(TocCache.isSameList([original], [legacy]))
    }

    func testMiddleChapterChangesAreNotHiddenByMatchingEndpoints() {
        let original = (0..<3).map { BookChapter(bookUrl: "b", url: "\($0)", title: "章\($0)", index: $0) }
        var updated = original
        updated[1].url = "new-url"
        XCTAssertFalse(TocCache.isSameList(original, updated))
    }
}

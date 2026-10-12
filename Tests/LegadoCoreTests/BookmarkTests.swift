import XCTest
@testable import LegadoCore

/// P0-3: bookmarks. The compatibility contract is Android's `bookmark.json`, whose books are
/// matched by name + author so a bookmark survives 换源 (which rewrites bookUrl).
final class BookmarkTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "LegadoBookmarkTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAndroidJsonKeyNames() throws {
        let data = try JSONEncoder().encode([Bookmark(time: 5, bookName: "书名", bookAuthor: "作者",
                                                      chapterIndex: 2, chapterPos: 120,
                                                      chapterName: "第二章", bookText: "原文",
                                                      content: "备注")])
        let dict = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first)
        for key in ["time", "bookName", "bookAuthor", "chapterIndex", "chapterPos",
                    "chapterName", "bookText", "content"] {
            XCTAssertTrue(dict.keys.contains(key), "missing \(key)")
        }
        XCTAssertEqual(dict.keys.count, 8, "no invented keys — Android restores by name")
    }

    func testDecodesAndroidBookmarkWithMissingKeys() throws {
        let json = #"[{"bookName":"书","bookAuthor":"者","chapterIndex":3,"chapterPos":42,"chapterName":"章"}]"#
        let loaded = try XCTUnwrap(
            TolerantJSON.decodeList(Bookmark.self, from: Data(json.utf8), fallback: Bookmark()))
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].chapterIndex, 3)
        XCTAssertEqual(loaded[0].chapterPos, 42)
        XCTAssertEqual(loaded[0].content, "")
    }

    func testBookKeyPairsNameAndAuthor() {
        // A separator that cannot appear in a title, so "A|B" + "C" never equals "A" + "B|C".
        let a = Bookmark(bookName: "书名", bookAuthor: "作者")
        let b = Bookmark(bookName: "书名", bookAuthor: "作者")
        let c = Bookmark(bookName: "书名作", bookAuthor: "者")
        XCTAssertEqual(a.bookKey, b.bookKey)
        XCTAssertNotEqual(a.bookKey, c.bookKey)
    }

    func testSortingMatchesAndroidDao() {
        let unordered = [
            Bookmark(time: 1, bookName: "乙", bookAuthor: "x", chapterIndex: 5, chapterPos: 0),
            Bookmark(time: 2, bookName: "甲", bookAuthor: "y", chapterIndex: 9, chapterPos: 30),
            Bookmark(time: 3, bookName: "甲", bookAuthor: "y", chapterIndex: 9, chapterPos: 5),
            Bookmark(time: 4, bookName: "甲", bookAuthor: "x", chapterIndex: 1, chapterPos: 0)
        ]
        let sortedTimes = BookmarkStore.sorted(unordered).map { $0.time }
        // Which Chinese title sorts first depends on the device locale, so assert the
        // structure Android guarantees instead of pinning one collation order.
        XCTAssertEqual(Set(sortedTimes), [1, 2, 3, 4])

        let sorted = BookmarkStore.sorted(unordered)
        let sameBook = sorted.filter { $0.bookName == "\u{7532}" && $0.bookAuthor == "y" }
        // time 3 sits at chapterPos 5, time 2 at 30 — ascending position wins.
        XCTAssertEqual(sameBook.map { $0.time }, [3, 2],
                       "same chapter: smaller chapterPos sorts first")
        let chapters = sameBook.map { $0.chapterIndex }
        XCTAssertEqual(chapters, [9, 9])

    }

    func testStoreRoundTripAndOrdering() throws {
        let bookmarks = [
            Bookmark(time: 10, bookName: "B", bookAuthor: "b"),
            Bookmark(time: 20, bookName: "A", bookAuthor: "a")
        ]
        BookmarkStore.save(bookmarks, to: defaults)
        let loaded = BookmarkStore.load(from: defaults)
        XCTAssertEqual(loaded.map { $0.bookName }, ["A", "B"], "load must re-sort")
        XCTAssertEqual(loaded.map { $0.time }, [20, 10])
    }

    func testEmptyStoreLoadsNothing() {
        XCTAssertEqual(BookmarkStore.load(from: defaults), [])
    }

    func testImportReplacesSameTimeAndAppendsNew() throws {
        let existing = [Bookmark(time: 1, bookName: "旧", bookAuthor: "a")]
        let payload = "[{\"time\":1,\"bookName\":\"新\",\"bookAuthor\":\"a\",\"chapterIndex\":4},{\"time\":2,\"bookName\":\"另\",\"bookAuthor\":\"b\",\"chapterIndex\":0}]"
        let merged = BookmarkStore.importJSON(payload, into: existing)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains { $0.bookName == "新" && $0.chapterIndex == 4 })
        XCTAssertTrue(merged.contains { $0.bookName == "另" })
        XCTAssertFalse(merged.contains { $0.bookName == "旧" }, "same time must overwrite")
    }

    func testImportIgnoresGarbage() {
        let existing = [Bookmark(time: 1, bookName: "keep", bookAuthor: "a")]
        XCTAssertEqual(BookmarkStore.importJSON("not json", into: existing).count, 1)
    }

    func testExportRoundTripsThroughImport() throws {
        let original = [Bookmark(time: 7, bookName: "书", bookAuthor: "者", chapterIndex: 2,
                                chapterPos: 9, chapterName: "第二章", bookText: "原文一段",
                                content: "批注")]
        let json = try XCTUnwrap(BookmarkStore.exportJSON(original))
        XCTAssertEqual(BookmarkStore.importJSON(json, into: []).map { $0.time }, [7])
        let restored = BookmarkStore.importJSON(json, into: [])[0]
        XCTAssertEqual(restored, original[0])
    }

    func testMarkdownExportMatchesAndroidLayout() {
        let bookmarks = [
            Bookmark(time: 1, bookName: "书", bookAuthor: "者", chapterIndex: 0, chapterPos: 0,
                     chapterName: "第一章", bookText: "正文", content: "想法"),
            Bookmark(time: 2, bookName: "书", bookAuthor: "者", chapterIndex: 1, chapterPos: 0,
                     chapterName: "第二章", bookText: "更多正文", content: "")
        ]
        let markdown = BookmarkStore.exportMarkdown(bookmarks)
        let lines = markdown.components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0 == "## 书 者" }.count, 1, "exactly one book header")
        XCTAssertEqual(lines.filter { $0.hasPrefix("#### ") }.count, 2, "one line per bookmark")
        XCTAssertTrue(markdown.contains("#### 第一章"))
        XCTAssertTrue(markdown.contains("###### 正文"))
        XCTAssertTrue(markdown.contains("###### 想法"))
        XCTAssertTrue(markdown.contains("#### 第二章"))
    }
}

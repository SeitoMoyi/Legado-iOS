import XCTest
import Foundation
@testable import LegadoCore

/// Home-screen quick actions: `Info.plist` declares the shortcut types and `LegadoAppDelegate`
/// forwards them, but the mapping and the 「继续阅读」 resolution live in `LaunchIntent` and are
/// testable without a UIKit host.
final class LaunchIntentTests: XCTestCase {

    private func book(url: String, durChapterTime: Int64, lastCheckTime: Int64 = 0) -> Book {
        var b = Book(bookUrl: url, name: "书\(url)", author: "作者", origin: "https://src.test")
        b.durChapterTime = durChapterTime
        b.lastCheckTime = lastCheckTime
        return b
    }

    // MARK: - Shortcut type mapping

    /// The literals must match `Sources/LegadoApp/Info.plist` verbatim, otherwise the declared
    /// shortcuts silently do nothing.
    func testShortcutTypesMatchInfoPlistLiterals() {
        XCTAssertEqual(LaunchIntent.searchShortcutType, "io.legado.action.search")
        XCTAssertEqual(LaunchIntent.lastReadShortcutType, "io.legado.action.lastRead")
    }

    func testSearchShortcutMapsToSearchIntent() {
        XCTAssertEqual(LaunchIntent.fromShortcutType("io.legado.action.search"), .search)
    }

    func testLastReadShortcutMapsToContinueReadingIntent() {
        XCTAssertEqual(LaunchIntent.fromShortcutType("io.legado.action.lastRead"), .continueReading)
    }

    func testUnknownShortcutTypeIsIgnored() {
        XCTAssertNil(LaunchIntent.fromShortcutType("io.legado.action.doesNotExist"))
        XCTAssertNil(LaunchIntent.fromShortcutType(""))
        XCTAssertNil(LaunchIntent.fromShortcutType(nil))
    }

    // MARK: - 「继续阅读」 target selection

    func testLastReadBookPicksNewestDurChapterTime() {
        let books = [
            book(url: "a", durChapterTime: 1_000),
            book(url: "c", durChapterTime: 3_000),
            book(url: "b", durChapterTime: 2_000)
        ]
        XCTAssertEqual(LaunchIntent.lastReadBook(in: books)?.bookUrl, "c")
    }

    /// `lastCheckTime` is bumped by TOC refreshes and by pinning, so a book that was never opened
    /// must not win on it — otherwise 「继续阅读」 would open an unread book.
    func testNeverOpenedBookDoesNotWinViaLastCheckTime() {
        let books = [
            book(url: "neverOpened", durChapterTime: 0, lastCheckTime: 9_999),
            book(url: "read", durChapterTime: 1_000, lastCheckTime: 1_000)
        ]
        XCTAssertEqual(LaunchIntent.lastReadBook(in: books)?.bookUrl, "read")
    }

    func testShelfWithNoReadBooksHasNoContinueTarget() {
        let books = [
            book(url: "a", durChapterTime: 0, lastCheckTime: 5_000),
            book(url: "b", durChapterTime: 0)
        ]
        XCTAssertNil(LaunchIntent.lastReadBook(in: books))
    }

    func testEmptyShelfHasNoContinueTarget() {
        XCTAssertNil(LaunchIntent.lastReadBook(in: []))
    }

    /// Ties keep the caller's shelf order, so the shortcut is deterministic rather than
    /// dependent on sort instability.
    func testTieKeepsFirstBookInShelfOrder() {
        let books = [
            book(url: "first", durChapterTime: 4_000),
            book(url: "second", durChapterTime: 4_000)
        ]
        XCTAssertEqual(LaunchIntent.lastReadBook(in: books)?.bookUrl, "first")
    }
}

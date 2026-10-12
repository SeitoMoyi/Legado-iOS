import XCTest
import Foundation
@testable import LegadoCore

/// Group vocabulary on both sides of the app:
/// - the bookshelf tabs (`BookGroupStore`) — 全部 / 书源书籍 / 本地书籍, and the v1 → v2 migration
///   that retires 养肥中 / 已完结;
/// - `Book.isLocalBook`, the single predicate splitting 书源书籍 from 本地书籍;
/// - `BookSource.stripAndroidValidatorGroupTags`, which keeps Android's 校验书源 verdicts
///   (`搜索目录失效`, `good`, …) from being displayed as if they were user groups.
final class BookGroupTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "LegadoBookGroupTests"

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

    // MARK: - Shelf tabs

    func testFreshStoreSeedsThreeShelfGroups() {
        let names = BookGroupStore.load(from: defaults).map(\.groupName)
        XCTAssertEqual(names, ["全部", "书源书籍", "本地书籍"])
        XCTAssertFalse(names.contains("养肥中"))
        XCTAssertFalse(names.contains("已完结"))
    }

    func testRetiredDefaultsAreMigratedOutOfStoredGroups() {
        let legacy = [
            BookGroup(groupId: BookGroup.idAll, groupName: "全部", order: 0),
            BookGroup(groupId: 1, groupName: "养肥中", order: 1),
            BookGroup(groupId: 2, groupName: "已完结", order: 2),
            BookGroup(groupId: BookGroup.idLocal, groupName: "本地书籍", order: 3)
        ]
        defaults.set(try? JSONEncoder().encode(legacy), forKey: "legado_book_groups_v1")

        let names = BookGroupStore.load(from: defaults).map(\.groupName)
        XCTAssertEqual(names, ["全部", "书源书籍", "本地书籍"])
        XCTAssertNil(defaults.data(forKey: "legado_book_groups_v1"), "migrated row should be dropped")
        XCTAssertNotNil(defaults.data(forKey: BookGroupStore.key), "migration should persist")
    }

    func testUserCreatedGroupsSurviveMigration() {
        let legacy = [
            BookGroup(groupId: BookGroup.idAll, groupName: "全部", order: 0),
            BookGroup(groupId: 1, groupName: "养肥中", order: 1),
            BookGroup(groupId: 7, groupName: "我的收藏", order: 2),
            // Retired *name*, user-owned id: must not be treated as a seed row.
            BookGroup(groupId: 9, groupName: "已完结", order: 3)
        ]
        defaults.set(try? JSONEncoder().encode(legacy), forKey: "legado_book_groups_v1")

        let ids = BookGroupStore.load(from: defaults).map(\.groupId)
        XCTAssertTrue(ids.contains(7), "custom group dropped")
        XCTAssertTrue(ids.contains(9), "custom group that merely reuses a retired name was dropped")
        XCTAssertFalse(ids.contains(1), "retired seed row survived")
        XCTAssertEqual(ids.first, BookGroup.idAll, "全部 should stay first")
        XCTAssertEqual(ids.dropFirst().first, BookGroup.idNet, "书源书籍 should sit next to 全部")
    }

    func testStoredGroupListMissingVirtualGroupsIsRepaired() {
        let partial = [BookGroup(groupId: BookGroup.idAll, groupName: "全部", order: 0)]
        defaults.set(try? JSONEncoder().encode(partial), forKey: BookGroupStore.key)

        let loaded = BookGroupStore.load(from: defaults)
        XCTAssertEqual(loaded.map(\.groupName), ["全部", "书源书籍", "本地书籍"])
    }

    func testNetAndLocalGroupsAreDistinctVirtualIds() {
        XCTAssertNotEqual(BookGroup.idNet, BookGroup.idAll)
        XCTAssertNotEqual(BookGroup.idNet, BookGroup.idLocal)
    }

    // MARK: - 书源书籍 / 本地书籍 split

    func testLocalBooksAreClassifiedByOriginOrUrlScheme() {
        XCTAssertTrue(Book(bookUrl: "txt://file/abc", name: "本地", author: "作者").isLocalBook)
        XCTAssertTrue(Book(bookUrl: "epub://file/abc", name: "本地", author: "作者").isLocalBook)
        XCTAssertTrue(Book(bookUrl: "file:///tmp/a.txt", name: "本地", author: "作者").isLocalBook)
        XCTAssertTrue(Book(bookUrl: "https://x.test/book/1", name: "本地", author: "作者",
                           origin: "local", originName: "本地导入").isLocalBook)
    }

    func testNetworkBooksAreNotLocal() {
        let book = Book(bookUrl: "https://www.esjzone.one/detail/1.html", name: "网络书",
                        author: "作者", origin: "https://www.esjzone.one",
                        originName: "ESJ")
        XCTAssertFalse(book.isLocalBook)
    }

    // MARK: - Shelf tab filtering

    func testNetTabShowsOnlyNetworkBooksAndLocalTabOnlyImports() {
        let network = Book(bookUrl: "https://www.esjzone.one/detail/1.html", name: "网络书",
                           author: "作者", origin: "https://www.esjzone.one", originName: "ESJ")
        let local = Book(bookUrl: "txt://file/local1", name: "本地书", author: "作者",
                         origin: "local", originName: "本地导入")
        let shelf = [network, local]

        XCTAssertEqual(ShelfFilter.books(shelf, inGroup: BookGroup.idAll).count, 2)
        XCTAssertEqual(ShelfFilter.books(shelf, inGroup: BookGroup.idNet).map(\.name), ["网络书"])
        XCTAssertEqual(ShelfFilter.books(shelf, inGroup: BookGroup.idLocal).map(\.name), ["本地书"])
    }

    func testUserGroupTabMatchesStoredGroupId() {
        let pinned = Book(bookUrl: "https://x.test/1", name: "收藏", author: "作者",
                          origin: "https://x.test", group: 7)
        let loose = Book(bookUrl: "https://x.test/2", name: "未分组", author: "作者",
                         origin: "https://x.test", group: 0)

        XCTAssertEqual(ShelfFilter.books([pinned, loose], inGroup: 7).map(\.name), ["收藏"])
        XCTAssertTrue(ShelfFilter.books([pinned, loose], inGroup: 99).isEmpty)
    }

    // MARK: - Source group display filtering (display-only, never rewrites the source)

    func testVerdictTagsAndCuratorialMarkerAreHiddenFromDisplayedGroup() {
        let source = BookSource(bookSourceUrl: "https://www.esjzone.one/", bookSourceName: "ESJ",
                                bookSourceGroup: "搜索目录失效,good,发现目录失效,轻小说")
        XCTAssertEqual(source.displayGroup, "轻小说", "only the individual category should be shown")
    }

    func testDisplayFilteringLeavesTheStoredGroupUntouched() {
        let source = BookSource(bookSourceUrl: "https://www.esjzone.one/", bookSourceName: "ESJ",
                                bookSourceGroup: "搜索目录失效,good,发现目录失效,轻小说")
        _ = source.displayGroup
        XCTAssertEqual(source.bookSourceGroup, "搜索目录失效,good,发现目录失效,轻小说",
                       "Android-compatible data must round-trip verbatim — the app filters at render time")
    }

    func testUnknownRealCategoryIsPassedThroughUntouched() {
        let source = BookSource(bookSourceUrl: "https://x.test/", bookSourceName: "X",
                                bookSourceGroup: "轻小说,听书,某个我不知道的分组")
        XCTAssertEqual(source.displayGroup, "轻小说,听书,某个我不知道的分组")
    }

    func testOwnFailureTagIsStillDisplayed() {
        let source = BookSource(bookSourceUrl: "https://x.test/", bookSourceName: "X",
                                bookSourceGroup: "失效,轻小说")
        XCTAssertEqual(source.displayGroup, "失效,轻小说",
                       "「失效」 is what this app's 校验 writes; hiding it would hide real state")
    }

    func testDisplayGroupIsNilWhenOnlyNoiseRemains() {
        let source = BookSource(bookSourceUrl: "https://x.test/", bookSourceName: "X",
                                bookSourceGroup: "搜索失效,发现规则为空,good,校验超时")
        XCTAssertNil(source.displayGroup)
    }

    func testMeasuredRespondTimeIsShownButAndroidFailureMarkerIsNot() {
        XCTAssertTrue(BookSource.isMeasuredRespondTime(812), "a real measurement")
        XCTAssertFalse(BookSource.isMeasuredRespondTime(185_203), "180000 + spendingTime means 校验失败")
        XCTAssertFalse(BookSource.isMeasuredRespondTime(BookSource.androidFailureRespondTimeMs),
                       "exactly at the timeout floor is still the failure marker")
        XCTAssertFalse(BookSource.isMeasuredRespondTime(0), "no measurement")
    }

    func testSourceWithoutAnyGroupHasNoDisplayedGroup() {
        let source = BookSource(bookSourceUrl: "https://x.test/", bookSourceName: "X")
        XCTAssertNil(source.displayGroup)
    }
}

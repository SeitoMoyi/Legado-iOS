import XCTest
import LegadoCore
@testable import LegadoApp

final class BookStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: BookStore!

    override func setUp() {
        super.setUp()
        suite = "Legado.BookStoreTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        store = BookStore(defaults: defaults)
    }

    override func tearDown() {
        store = nil
        defaults.removePersistentDomain(forName: suite)
        ContentProcessor.shared.rules = nil
        ContentProcessor.shared.onRuleAutoDisabled = nil
        super.tearDown()
    }

    func testSingleSourceImportKeepsExtrasAndDoesNotOverwriteAnotherUrlWithSameName() throws {
        let first = #"{"bookSourceUrl":"https://one.test","bookSourceName":"同名","jsLib":"library"}"#
        let second = #"{"bookSourceUrl":"https://two.test","bookSourceName":"同名"}"#
        XCTAssertEqual(try store.importSources(json: first), 1)
        XCTAssertEqual(try store.importSources(json: second), 1)
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(store.sources[0].jsLib, "library")
        XCTAssertThrowsError(try store.importSources(json: #"{"bookSourceName":"无地址"}"#))
    }

    func testReloadingPersistedEmptyListsClearsExistingState() throws {
        store.sources = [BookSource(bookSourceUrl: "https://one.test", bookSourceName: "一")]
        store.bookshelf = [Book(bookUrl: "one", name: "书", author: "作者")]
        defaults.set(Data("[]".utf8), forKey: "legado_sources_v1")
        defaults.set(Data("[]".utf8), forKey: "legado_bookshelf_v1")
        store.loadData()
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(store.bookshelf.isEmpty)
    }

    func testSourceReorderWorksWithMissingOrTiedImportedPositions() {
        let first = BookSource(bookSourceUrl: "one", bookSourceName: "一", customOrder: nil)
        let hidden = BookSource(bookSourceUrl: "hidden", bookSourceName: "隐藏", customOrder: 0)
        let last = BookSource(bookSourceUrl: "last", bookSourceName: "末", customOrder: 0)
        store.sources = [first, hidden, last]
        store.applySourceOrder([last, first])
        XCTAssertEqual(store.sources.map(\.bookSourceUrl), ["last", "hidden", "one"])
        XCTAssertEqual(store.sources.map(\.customOrder), [0, 1, 2])
    }

    func testShelfReorderWorksWithTiedPositionsAndLeavesHiddenSlot() {
        let first = Book(bookUrl: "one", name: "一", author: "作者")
        let hidden = Book(bookUrl: "hidden", name: "隐藏", author: "作者")
        let last = Book(bookUrl: "last", name: "末", author: "作者")
        store.bookshelf = [first, hidden, last]
        store.applyManualOrder([last, first])
        XCTAssertEqual(store.bookshelf.sorted { $0.order < $1.order }.map(\.bookUrl), ["last", "hidden", "one"])
    }

    func testRestoringBookmarksToleratesDuplicateExistingIds() {
        store.bookmarks = [Bookmark(time: 1, bookName: "旧"), Bookmark(time: 1, bookName: "重复")]
        _ = store.restoreBackupPayload(.init(bookmarks: [Bookmark(time: 1, bookName: "更新")]))
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.bookName, "更新")
    }

    func testRestoringReadRecordsKeepsDevicesSeparate() {
        ReadRecordStore.save([ReadRecord(deviceId: "A", bookName: "书", readTime: 100)], to: defaults)
        _ = store.restoreBackupPayload(.init(readRecords: [ReadRecord(deviceId: "B", bookName: "书", readTime: 200)]))
        let records = ReadRecordStore.load(from: defaults)
        XCTAssertEqual(Set(records.map(\.deviceId)), Set(["A", "B"]))
        XCTAssertEqual(records.map(\.readTime).sorted(), [100, 200])
    }

    func testLoginUnwrapsJsAndRequiresNewCredentials() async throws {
        var source = BookSource(bookSourceUrl: "https://login.test", bookSourceName: "登录")
        source.loginUrl = "@js:source.putLoginHeader(JSON.stringify({'Cookie':'token=new'}))"
        store.sources = [source]
        let header = try await store.performLogin(source: source, credentials: [:])
        XCTAssertTrue(header.contains("token=new"))
        XCTAssertEqual(store.sources.first?.loginHeader, header)

        source.loginHeader = "old credentials"
        source.loginUrl = "<js>1 + 1</js>"
        do {
            _ = try await store.performLogin(source: source, credentials: [:])
            XCTFail("an old saved header must not make a login that returned no credentials succeed")
        } catch { }
    }
}

extension BookStoreTests {
    func testRestorePreservesNewerLocalProgressWhenMetadataChanges() {
        store.bookshelf = [Book(bookUrl: "same", name: "现名", author: "现作者", durChapterIndex: 2, durChapterPos: 20, durChapterTime: 200)]
        _ = store.restoreBackupPayload(.init(books: [Book(bookUrl: "same", name: "旧名", author: "旧作者", durChapterIndex: 1, durChapterTime: 100)]))
        XCTAssertEqual(store.bookshelf.first?.name, "旧名")
        XCTAssertEqual(store.bookshelf.first?.durChapterIndex, 2)
        XCTAssertEqual(store.bookshelf.first?.durChapterTime, 200)
    }
}

extension BookStoreTests {
    func testRelocatedBookReplacesShelfEntryAndKeepsNewerReadingProgress() throws {
        var original = Book(bookUrl: "old", name: "书", author: "作者")
        original.durChapterIndex = 4
        original.durChapterPos = 90
        original.durChapterTime = 200
        original.group = 8
        original.order = 7
        store.bookshelf = [original]
        var fetched = original
        fetched.bookUrl = "new"
        fetched.tocUrl = "new-toc"
        fetched.durChapterIndex = 1
        fetched.durChapterPos = 0
        fetched.durChapterTime = 100
        let updated = try XCTUnwrap(try store.applyRefreshedBook(fetched, replacing: "old"))
        XCTAssertEqual(store.bookshelf.count, 1)
        XCTAssertEqual(updated.bookUrl, "new")
        XCTAssertEqual(updated.durChapterIndex, 4)
        XCTAssertEqual(updated.durChapterPos, 90)
        XCTAssertEqual(updated.durChapterTime, 200)
        XCTAssertEqual(updated.group, 8)
        XCTAssertEqual(updated.order, 7)
    }

    func testRelocatedRefreshDoesNotResurrectDeletedBookOrOverwriteAnotherEntry() throws {
        let updated = Book(bookUrl: "new", name: "书", author: "作者")
        XCTAssertNil(try store.applyRefreshedBook(updated, replacing: "deleted"))
        store.bookshelf = [Book(bookUrl: "old", name: "旧", author: "作者"), updated]
        XCTAssertThrowsError(try store.applyRefreshedBook(updated, replacing: "old"))
        XCTAssertEqual(store.bookshelf.map(\.bookUrl), ["old", "new"])
    }
}

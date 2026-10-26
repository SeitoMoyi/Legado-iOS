import XCTest
import LegadoCore
@testable import LegadoApp

final class BookStoreTests: XCTestCase {
    func testLegacyGroupMigrationIsPersistedOnceAndKeepsCombinedMembershipOnReload() throws {
        let legacyID: Int64 = 1_700_000_001
        BookGroupStore.save([BookGroup(groupId: legacyID, groupName: "Legacy"), BookGroup(groupId: 4, groupName: "Native")], to: defaults)
        store.bookshelf = [Book(bookUrl: "one", name: "Book", author: "Author", durChapterIndex: 3, durChapterPos: 20, group: legacyID)]
        store.saveBookshelf()
        defaults.removeObject(forKey: BookGroupStore.bitmaskVersionKey)
        store = BookStore(defaults: defaults)
        let group = try XCTUnwrap(BookGroupStore.load(from: defaults).first { $0.groupName == "Legacy" })
        XCTAssertTrue(BookGroupCompatibility.isSingleBit(group.groupId))
        XCTAssertEqual(store.bookshelf.first?.group, group.groupId)
        XCTAssertEqual(store.bookshelf.first?.durChapterIndex, 3)
        XCTAssertTrue(store.usesGroupBitmasks)
        XCTAssertNil(defaults.data(forKey: BookGroupStore.migrationKey))
        store.moveBooks(bookUrls: ["one"], toGroupId: group.groupId | 4)
        store = BookStore(defaults: defaults)
        XCTAssertEqual(store.bookshelf.first?.group, group.groupId | 4)
    }

    func testInterruptedMigrationRestoresCompleteSnapshot() throws {
        let original = Book(bookUrl: "one", name: "Book", author: "Author", durChapterPos: 25, group: 1001)
        let migration = try BookGroupCompatibility.migrateLegacy(groups: [BookGroup(groupId: 1001, groupName: "Legacy")], books: [original])
        defaults.set(try JSONEncoder().encode(migration), forKey: BookGroupStore.migrationKey)
        defaults.set(try JSONEncoder().encode([original]), forKey: "legado_bookshelf_v1")
        BookGroupStore.save(migration.groups, to: defaults)
        defaults.removeObject(forKey: BookGroupStore.bitmaskVersionKey)
        store = BookStore(defaults: defaults)
        XCTAssertEqual(store.bookshelf.first?.group, migration.books.first?.group)
        XCTAssertEqual(store.bookshelf.first?.durChapterPos, 25)
        XCTAssertTrue(store.usesGroupBitmasks)
        XCTAssertNil(defaults.data(forKey: BookGroupStore.migrationKey))
    }

    func testExcessLegacyGroupsRemainReadableUntilCapacityIsResolved() throws {
        let groups = BookGroupStore.defaultGroups + (1000..<1064).map { BookGroup(groupId: Int64($0), groupName: "G\($0)") }
        BookGroupStore.save(groups, to: defaults)
        let original = Book(bookUrl: "one", name: "Book", author: "Author", group: 1000)
        defaults.set(try JSONEncoder().encode([original]), forKey: "legado_bookshelf_v1")
        defaults.removeObject(forKey: BookGroupStore.bitmaskVersionKey)
        store = BookStore(defaults: defaults)
        XCTAssertFalse(store.usesGroupBitmasks)
        XCTAssertNotNil(store.groupMigrationIssue)
        XCTAssertEqual(store.bookshelf.first?.group, 1000)
        XCTAssertEqual(ShelfFilter.books(store.bookshelf, inGroup: 1000, groups: groups, legacyAssignments: true).count, 1)
        store.deleteBookGroups([1001])
        XCTAssertTrue(store.usesGroupBitmasks)
        XCTAssertNil(store.groupMigrationIssue)
        XCTAssertTrue(BookGroupCompatibility.isSingleBit(store.bookshelf.first!.group))
    }

    func testBackupGroupConflictPreservesExistingBooksAndNativeSeedNames() throws {
        BookGroupStore.save(BookGroupStore.defaultGroups + [BookGroup(groupId: 1, groupName: "Local")], to: defaults)
        store.bookshelf = [Book(bookUrl: "local", name: "Local book", author: "Author", group: 1)]
        let incoming = Book(bookUrl: "remote", name: "Remote book", author: "Author", group: 1)
        _ = try store.restoreBackupPayload(.init(books: [incoming], bookGroups: [BookGroup(groupId: 1, groupName: "养肥中", order: 100)]))
        let groups = BookGroupStore.load(from: defaults)
        XCTAssertEqual(groups.first { $0.groupId == 1 }?.groupName, "Local")
        let imported = try XCTUnwrap(groups.first { $0.groupName == "养肥中" })
        XCTAssertNotEqual(imported.groupId, 1)
        XCTAssertEqual(store.bookshelf.first { $0.bookUrl == "local" }?.group, 1)
        XCTAssertEqual(store.bookshelf.first { $0.bookUrl == "remote" }?.group, imported.groupId)
        XCTAssertGreaterThan(try store.addBookGroup(name: "After import").order, imported.order)
    }

    func testInvalidBackupGroupsDoNotPartiallyImportBooksOrSources() throws {
        let original = Book(bookUrl: "local", name: "Local", author: "Author")
        store.bookshelf = [original]
        let groups = BookGroupStore.load(from: defaults)
        XCTAssertThrowsError(try store.restoreBackupPayload(.init(
            books: [Book(bookUrl: "remote", name: "Remote", author: "Author")],
            sources: [BookSource(bookSourceUrl: "https://source.test", bookSourceName: "Source")],
            bookGroups: [BookGroup(groupId: 3, groupName: "Invalid")]
        )))
        XCTAssertEqual(store.bookshelf, [original])
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertEqual(BookGroupStore.load(from: defaults), groups)
    }

    func testDeletedLegacyGroupDoesNotReattachOldBackupToReusedBit() throws {
        let legacyID: Int64 = 1_700_000_001
        BookGroupStore.save([BookGroup(groupId: legacyID, groupName: "Legacy")], to: defaults)
        defaults.set(try JSONEncoder().encode([Book(bookUrl: "one", name: "One", author: "A", group: legacyID)]), forKey: "legado_bookshelf_v1")
        defaults.removeObject(forKey: BookGroupStore.bitmaskVersionKey)
        store = BookStore(defaults: defaults)
        let bit = try XCTUnwrap(store.bookshelf.first?.group)
        store.deleteBookGroups([bit])
        let replacement = try store.addBookGroup(name: "New")
        XCTAssertEqual(replacement.groupId, bit)
        _ = try store.restoreBackupPayload(.init(books: [Book(bookUrl: "old-backup", name: "Old", author: "A", group: legacyID)]))
        XCTAssertEqual(store.bookshelf.first { $0.bookUrl == "old-backup" }?.group, 0)
        XCTAssertEqual(store.bookshelf.first { $0.bookUrl == "one" }?.group, 0)
    }

    func testGroupRenameDeleteAndSupplementalRulesArePersistent() throws {
        let first = try store.addBookGroup(name: "First")
        let second = try store.addBookGroup(name: "Second")
        store.bookshelf = [Book(bookUrl: "one", name: "One", author: "A", group: first.groupId | second.groupId)]
        store.renameBookGroup(id: first.groupId, name: "Renamed", enableRefresh: false)
        XCTAssertEqual(BookGroupStore.load(from: defaults).first { $0.groupId == first.groupId }?.groupName, "Renamed")
        XCTAssertEqual(BookGroupStore.load(from: defaults).first { $0.groupId == first.groupId }?.enableRefresh, false)
        store.deleteBookGroups([first.groupId])
        XCTAssertEqual(store.bookshelf.first?.group, second.groupId)
        var engine = HttpTTS(id: 1, name: "Voice", url: "https://tts.test")
        engine.extra["jsLib"] = .string("library")
        _ = try store.restoreBackupPayload(.init(dictRules: [DictRule(name: "D", urlRule: "https://dict.test")], httpTTS: [engine]))
        XCTAssertEqual(DictRuleStore.load(from: defaults).first { $0.name == "D" }?.urlRule, "https://dict.test")
        let engines = HttpTTSStore.load(from: defaults)
        XCTAssertEqual(Set(engines.map(\.id)).count, engines.count)
        XCTAssertEqual(engines.first { $0.id == 1 }?.extra["jsLib"], .string("library"))
        store = BookStore(defaults: defaults)
        XCTAssertEqual(store.bookshelf.first?.group, second.groupId)
    }

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

    func testRestoringBookmarksToleratesDuplicateExistingIds() throws {
        store.bookmarks = [Bookmark(time: 1, bookName: "旧"), Bookmark(time: 1, bookName: "重复")]
        _ = try store.restoreBackupPayload(.init(bookmarks: [Bookmark(time: 1, bookName: "更新")]))
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.bookName, "更新")
    }

    func testRestoringReadRecordsKeepsDevicesSeparate() throws {
        ReadRecordStore.save([ReadRecord(deviceId: "A", bookName: "书", readTime: 100)], to: defaults)
        _ = try store.restoreBackupPayload(.init(readRecords: [ReadRecord(deviceId: "B", bookName: "书", readTime: 200)]))
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
    func testRestorePreservesNewerLocalProgressWhenMetadataChanges() throws {
        store.bookshelf = [Book(bookUrl: "same", name: "现名", author: "现作者", durChapterIndex: 2, durChapterPos: 20, durChapterTime: 200)]
        _ = try store.restoreBackupPayload(.init(books: [Book(bookUrl: "same", name: "旧名", author: "旧作者", durChapterIndex: 1, durChapterTime: 100)]))
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

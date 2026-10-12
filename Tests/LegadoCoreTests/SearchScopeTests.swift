import XCTest
@testable import LegadoCore

private func makeSource(_ name: String, _ url: String, group: String? = nil, enabled: Bool? = true) -> BookSource {
    BookSource(bookSourceUrl: url, bookSourceName: name, bookSourceGroup: group,
               enabled: enabled, searchUrl: "/search?kw={{key}}")
}

final class SearchScopeTests: XCTestCase {

    // MARK: Android string format

    func testEmptyRawMeansAllSources() {
        let scope = SearchScope(raw: "")
        XCTAssertTrue(scope.isAll)
        XCTAssertFalse(scope.isSource)
        XCTAssertEqual(scope.groups, [])
        XCTAssertNil(scope.sourceUrl)
    }

    func testGroupListRoundTripsThroughRaw() {
        let scope = SearchScope(raw: "默认,故事汇")
        XCTAssertFalse(scope.isAll)
        XCTAssertFalse(scope.isSource)
        XCTAssertEqual(scope.groups, ["默认", "故事汇"])
        XCTAssertNil(scope.sourceUrl)
    }

    func testSourceScopeUsesAndroidNameDoubleColonUrlEncoding() {
        let scope = SearchScope(raw: "追书小说::https://book.example.com")
        XCTAssertTrue(scope.isSource)
        XCTAssertEqual(scope.sourceUrl, "https://book.example.com")
        XCTAssertEqual(scope.groups, [])
    }

    /// A url containing "::" must still resolve, so the split takes the tail.
    func testSourceScopeKeepsUrlWithColonSegments() {
        let scope = SearchScope(raw: "源::https://a.example.com:8443/x::y")
        XCTAssertEqual(scope.sourceUrl, "https://a.example.com:8443/x::y")
    }

    func testSingleGroupOnlyWhenExactlyOneSelected() {
        XCTAssertEqual(SearchScope(raw: "默认").singleGroup, "默认")
        XCTAssertEqual(SearchScope(raw: "默认,故事汇").singleGroup, "")
        XCTAssertEqual(SearchScope.all.singleGroup, "")
    }

    func testInitTrimsSurroundingWhitespace() {
        XCTAssertEqual(SearchScope(raw: "  默认 \n").raw, "默认")
    }

    // MARK: resolution

    func testAllScopeResolvesToEveryEnabledSource() {
        let sources = [makeSource("A", "https://a"), makeSource("B", "https://b", enabled: false)]
        let resolved = SearchScope.all.resolve(in: sources)
        XCTAssertEqual(resolved.sources.map { $0.bookSourceName }, ["A"])
        XCTAssertTrue(resolved.scope.isAll)
    }

    func testGroupScopeSelectsSourcesCarryingAnyListedGroup() {
        let sources = [makeSource("A", "https://a", group: "默认"),
                       makeSource("B", "https://b", group: "故事汇,默认"),
                       makeSource("C", "https://c", group: "其他")]
        let resolved = SearchScope(raw: "故事汇").resolve(in: sources)
        XCTAssertEqual(resolved.sources.map { $0.bookSourceName }, ["B"])
    }

    /// `AppPattern.splitGroupRegex` is `[,;，；]`: the full-width comma and semicolon count,
    /// a 顿号 does not. `\n` is an extra tolerance for hand-written source JSON.
    func testGroupSeparatorVariantsMatchAndroidRegex() {
        XCTAssertEqual(makeSource("A", "https://a", group: "默认,故事汇；其他，\n第三").groups,
                       ["默认", "故事汇", "其他", "第三"])
        XCTAssertEqual(makeSource("B", "https://b", group: "默认、故事汇").groups,
                       ["默认、故事汇"])
    }

    /// Android rewrites the stored scope when a group disappears, so a deleted group cannot
    /// silently pin every later search.
    func testDeadGroupIsDroppedAndScopeRewritten() {
        let sources = [makeSource("A", "https://a", group: "默认"),
                       makeSource("B", "https://b", group: "故事汇")]
        let resolved = SearchScope(raw: "默认,已删除").resolve(in: sources)
        XCTAssertEqual(resolved.scope.raw, "默认")
        XCTAssertEqual(resolved.sources.map { $0.bookSourceName }, ["A"])
    }

    func testEveryGroupDeadFallsBackToAll() {
        let sources = [makeSource("A", "https://a", group: "默认")]
        let resolved = SearchScope(raw: "已删除,也没了").resolve(in: sources)
        XCTAssertTrue(resolved.scope.isAll)
        XCTAssertEqual(resolved.sources.count, 1)
    }

    func testMissingSourceUrlFallsBackToAll() {
        let sources = [makeSource("A", "https://a")]
        let resolved = SearchScope(raw: " gone::https://removed").resolve(in: sources)
        XCTAssertTrue(resolved.scope.isAll)
        XCTAssertEqual(resolved.sources.count, 1)
    }

    func testSourceScopeResolvesToOneSourceEvenInsideGroup() {
        let sources = [makeSource("A", "https://a", group: "默认"),
                       makeSource("B", "https://b", group: "默认")]
        let resolved = SearchScope(raw: "B::https://b").resolve(in: sources)
        XCTAssertEqual(resolved.sources.map { $0.bookSourceName }, ["B"])
        XCTAssertTrue(resolved.scope.isSource)
    }

    // MARK: summary

    func testSummaryLabels() {
        XCTAssertEqual(SearchScope.all.summary(), "全部书源")
        XCTAssertEqual(SearchScope(raw: "默认").summary(), "分组：默认")
        XCTAssertEqual(SearchScope(raw: "默认,故事汇").summary(), "2 个分组")
        XCTAssertEqual(SearchScope(raw: "X::https://a").summary(), "单个书源")
        XCTAssertEqual(SearchScope(raw: "X::https://a").summary(sourceName: "追书"), "追书")
    }

    // MARK: merging results across sources

    private func book(_ name: String, _ author: String, _ origin: String,
                      cover: String? = nil, intro: String? = nil) -> SearchBook {
        SearchBook(name: name, author: author, bookUrl: "\(origin)/\(name)",
                   coverUrl: cover, intro: intro, origin: origin, originName: origin)
    }

    func testMergeFoldsSameTitleIntoOneRowWithEveryOrigin() {
        let merged = SearchMerger.merge([book("剑来", "烽火", "https://a")],
                                        [book("剑来", "烽火", "https://b"),
                                         book("剑来", "烽火", "https://c")])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].origins, ["https://a", "https://b", "https://c"])
        XCTAssertEqual(merged[0].originCount, 3)
    }

    func testMergeKeySeparatesDifferentAuthors() {
        let merged = SearchMerger.merge([book("剑来", "烽火", "https://a")],
                                        [book("剑来", "别人", "https://b")])
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeFillsOnlyMissingMetadata() {
        let first = book("剑来", "烽火", "https://a", cover: "https://a/1.jpg")
        let second = book("剑来", "烽火", "https://b", cover: "https://b/2.jpg", intro: "乙")
        let merged = SearchMerger.merge([first], [second])
        XCTAssertEqual(merged.count, 1)
        // An already-populated field is never overwritten by a later source.
        XCTAssertEqual(merged[0].coverUrl, "https://a/1.jpg")
        // A field the first source lacked is adopted from the second.
        XCTAssertEqual(merged[0].intro, "乙")
    }

    func testMergeAdoptsLaterIntroWhenEarlierIsEmpty() {
        let first = book("剑来", "烽火", "https://a", intro: "")
        let second = book("剑来", "烽火", "https://b", intro: "乙")
        let merged = SearchMerger.merge([first], [second])
        XCTAssertEqual(merged[0].intro, "乙")
    }

    func testMergeDoesNotDuplicateAnOriginAlreadyPresent() {
        let a = SearchBook(name: "剑来", author: "烽火", bookUrl: "https://a/1",
                           origin: "https://a", originName: "a", origins: ["https://a", "https://b"])
        let merged = SearchMerger.merge([a], [book("剑来", "烽火", "https://b")])
        XCTAssertEqual(merged[0].origins, ["https://a", "https://b"])
    }

    func testMergePreservesArrivalOrderForNewRows() {
        let merged = SearchMerger.merge([book("甲", "x", "https://a")],
                                        [book("乙", "y", "https://b"),
                                         book("甲", "x", "https://c"),
                                         book("丙", "z", "https://d")])
        XCTAssertEqual(merged.map { $0.name }, ["甲", "乙", "丙"])
    }

    // MARK: three-bucket ranking

    func testExactNameRanksAboveContainsAndOther() {
        let books = [book("剑来人", "某", "https://a"),
                     book("剑来", "烽火", "https://b"),
                     book(" unrelated", "剑来粉丝", "https://c")]
        let ranked = SearchMerger.rank(books, key: "剑来", precision: false)
        XCTAssertEqual(ranked.map { $0.name }, ["剑来", "剑来人", " unrelated"])
    }

    /// The whole point of the origins union: a book carried by more sources sorts first.
    func testBucketsSortByOriginCount() {
        let weak = SearchBook(name: "剑来", author: "烽火", bookUrl: "https://a/1",
                              origin: "https://a", originName: "a", origins: ["https://a"])
        let strong = SearchBook(name: "剑来", author: "烽火", bookUrl: "https://b/1",
                                origin: "https://b", originName: "b",
                                origins: ["https://b", "https://c", "https://d"])
        let ranked = SearchMerger.rank([weak, strong], key: "剑来", precision: false)
        XCTAssertEqual(ranked[0].origin, "https://b")
        XCTAssertEqual(ranked[0].originCount, 3)
    }

    func testPrecisionSearchDropsTheFuzzyBucket() {
        let books = [book("剑来", "烽火", "https://a"),
                     book("剑气长江", "某人", "https://b"),
                     book("别的书", "另一个作者", "https://c")]
        let ranked = SearchMerger.rank(books, key: "剑来", precision: true)
        XCTAssertEqual(ranked.map { $0.name }, ["剑来"])
    }

    func testNonPrecisionKeepsEverything() {
        let books = [book("剑来", "烽火", "https://a"),
                     book("剑气长江", "某人", "https://b"),
                     book("别的书", "作者含剑来", "https://c")]
        let ranked = SearchMerger.rank(books, key: "剑来", precision: false)
        XCTAssertEqual(ranked.count, 3)
    }

    func testAuthorMatchCountsAsExact() {
        // 别的书 matches on author, so it outranks the name-substring hit even though it
        // arrives second.
        let ranked = SearchMerger.rank([book("剑来传", "某人", "https://a"),
                                        book("别的书", "剑来", "https://b")],
                                       key: "剑来", precision: true)
        XCTAssertEqual(ranked.map { $0.name }, ["别的书", "剑来传"])
    }

    func testContainsBucketIsCaseInsensitive() {
        let ranked = SearchMerger.rank([book("Douluo", "tx", "https://a")],
                                       key: "douluo", precision: true)
        XCTAssertEqual(ranked.count, 1)
    }

    func testEmptyKeyLeavesOrderUntouched() {
        let books = [book("乙", "x", "https://a"), book("甲", "y", "https://b")]
        XCTAssertEqual(SearchMerger.rank(books, key: "  ", precision: true).map { $0.name }, ["乙", "甲"])
    }

    // MARK: history

    func testHistoryJsonUsesAndroidKeyNames() throws {
        let data = try JSONEncoder().encode([SearchKeyword(word: "剑来", usage: 3, lastUseTime: 1_700_000_000_000)])
        let json = String(data: data, encoding: .utf8)
        XCTAssertTrue(json!.contains("\"word\""), json!)
        XCTAssertTrue(json!.contains("\"usage\""), json!)
        XCTAssertTrue(json!.contains("\"lastUseTime\""), json!)
    }

    func testRecordReplacesRowInsteadOfDuplicating() {
        let base = [SearchKeyword(word: "剑来", usage: 2, lastUseTime: 1)]
        let after = SearchHistoryStore.record("剑来", in: base)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].usage, 3)
        XCTAssertGreaterThan(after[0].lastUseTime, 1)
    }

    func testRecordIgnoresBlankAndTrimsWords() {
        XCTAssertEqual(SearchHistoryStore.record("  ", in: []).count, 0)
        let after = SearchHistoryStore.record(" 剑来 ", in: [])
        XCTAssertEqual(after.map { $0.word }, ["剑来"])
    }

    func testByTimeSortsRecencyAndCapsAtLimit() {
        let items = (0..<40).map { SearchKeyword(word: "w\($0)", usage: 1, lastUseTime: Int64($0)) }
        let listed = SearchHistoryStore.byTime(items)
        XCTAssertEqual(listed.count, 30)
        XCTAssertEqual(listed.first?.word, "w39")
        XCTAssertEqual(listed.last?.word, "w10")
    }

    func testMatchingFiltersBySubstringAndSortsByUsage() {
        let items = [SearchKeyword(word: "剑来同人", usage: 1, lastUseTime: 5),
                     SearchKeyword(word: "剑来", usage: 9, lastUseTime: 4),
                     SearchKeyword(word: "凡人", usage: 50, lastUseTime: 3)]
        let matched = SearchHistoryStore.matching(items, "剑来")
        XCTAssertEqual(matched.map { $0.word }, ["剑来", "剑来同人"])
    }

    func testMatchingWithEmptyNeedleFallsBackToRecency() {
        let items = [SearchKeyword(word: "a", usage: 1, lastUseTime: 1),
                     SearchKeyword(word: "b", usage: 1, lastUseTime: 2)]
        XCTAssertEqual(SearchHistoryStore.matching(items, "").map { $0.word }, ["b", "a"])
    }

    func testHistoryPersistsThroughUserDefaultsSuite() {
        let suite = UserDefaults(suiteName: name)!
        suite.removeObject(forKey: SearchHistoryStore.key)
        SearchHistoryStore.save([SearchKeyword(word: "剑来", usage: 4, lastUseTime: 77)], to: suite)
        let loaded = SearchHistoryStore.load(from: suite)
        XCTAssertEqual(loaded.map { $0.word }, ["剑来"])
        XCTAssertEqual(loaded[0].usage, 4)
    }

    func testLoadToleratesOlderPartialPayloads() throws {
        let suite = UserDefaults(suiteName: "\(name)-partial")!
        // A row missing `usage` must not make the whole list disappear.
        suite.set(Data(#"[{"word":"剑来","lastUseTime":5}]"#.utf8), forKey: SearchHistoryStore.key)
        let loaded = SearchHistoryStore.load(from: suite)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].word, "剑来")
    }

    func testLoadOnEmptyDefaultsIsNotEmptyCrash() {
        let suite = UserDefaults(suiteName: "\(name)-empty")!
        suite.removeObject(forKey: SearchHistoryStore.key)
        XCTAssertEqual(SearchHistoryStore.load(from: suite), [])
    }
}

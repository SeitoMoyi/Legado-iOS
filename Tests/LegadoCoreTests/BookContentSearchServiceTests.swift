import XCTest
@testable import LegadoCore

/// Plan Phase 1 Part 5: 书内全书并发搜索 — cache-first matching, regex support, hit
/// offsets/snippets, cap-per-chapter, and the finished/progress event stream.
final class BookContentSearchServiceTests: XCTestCase {

    private var service: BookContentSearchService!

    override func setUp() {
        super.setUp()
        service = BookContentSearchService()
        service.maxHitsPerChapter = 3
        service.searchConcurrency = 4
    }

    override func tearDown() {
        // Strip the chapters this test seeded so cases stay independent.
        let all = BookContentService.shared
        for i in 0..<5 {
            all.clearCachedChapter(bookUrl: Self.bookUrl, chapterIndex: i)
        }
        super.tearDown()
    }

    private static let bookUrl = "https://test.example/book/1"

    private func makeBook() -> Book {
        Book(bookUrl: Self.bookUrl, name: "测试书", author: "作者", origin: "test", originName: "测试源")
    }

    private func makeChapters(_ titles: [String]) -> [BookChapter] {
        titles.enumerated().map { idx, title in
            BookChapter(bookUrl: Self.bookUrl, url: "https://test.example/c/\(idx)", title: title, index: idx)
        }
    }

    /// Seeds the on-disk cache for one chapter and returns its content.
    @discardableResult
    private func seed(_ index: Int, _ content: String) -> String {
        BookContentService.shared.saveCachedChapterContent(
            bookUrl: Self.bookUrl, chapterIndex: index, content: content)
        return content
    }

    private func collect(
        _ book: Book, _ chapters: [BookChapter],
        query: String, isRegex: Bool = false, includeUncached: Bool = false
    ) async -> (hits: [BookContentSearchService.Hit],
                finished: (chaptersSearched: Int, hits: Int, cancelled: Bool)?) {
        var hits: [BookContentSearchService.Hit] = []
        var finished: (chaptersSearched: Int, hits: Int, cancelled: Bool)?
        let stream = service.search(
            book: book, source: nil, chapters: chapters,
            query: query, isRegex: isRegex, includeUncached: includeUncached)
        for await event in stream {
            switch event {
            case .hit(let hit): hits.append(hit)
            case .finished(let f): finished = f
            case .progress: break
            }
        }
        return (hits, finished)
    }

    // MARK: - Plain keyword

    func testPlainKeywordHitsAcrossCachedChapters() async throws {
        seed(0, "本章没有目标词。")
        seed(1, "这里是正文。主角拔出了石中剑，石中剑发出了光芒。")
        seed(2, "石中剑再次出现。")

        let book = makeBook()
        let chapters = makeChapters(["第一章", "第二章", "第三章"])
        let (hits, finished) = await collect(book, chapters, query: "石中剑")

        XCTAssertEqual(hits.count, 3, "第二章两次 + 第三章一次")
        XCTAssertEqual(hits[0].chapterIndex, 1)
        XCTAssertEqual(hits[1].chapterIndex, 1)
        XCTAssertEqual(hits[2].chapterIndex, 2)
        // 结果按章节顺序流式输出
        XCTAssertTrue(hits[0].charPosition < hits[1].charPosition)
        // 命中文本与上下文
        XCTAssertEqual(hits[0].matchedText, "石中剑")
        XCTAssertTrue(hits[0].snippet.contains("石中剑"))
        // 字符偏移即关键词在章节文本中的真实位置
        let ch1 = BookContentService.shared.getCachedChapterContent(bookUrl: Self.bookUrl, chapterIndex: 1)!
        let idx = ch1.distance(from: ch1.startIndex, to: ch1.range(of: "石中剑")!.lowerBound)
        XCTAssertEqual(hits[0].charPosition, idx)

        let fin = try XCTUnwrap(finished)
        XCTAssertEqual(fin.chaptersSearched, 3)
        XCTAssertEqual(fin.hits, 3)
        XCTAssertFalse(fin.cancelled)
    }

    func testMaxHitsPerChapterCap() async {
        seed(0, "剑 剑 剑 剑 剑")
        let book = makeBook()
        let chapters = makeChapters(["第一章"])
        let (hits, _) = await collect(book, chapters, query: "剑")
        XCTAssertEqual(hits.count, 3, "maxHitsPerChapter = 3 封顶")
    }

    // MARK: - Regex

    func testRegexSearchMatchesPattern() async {
        seed(0, "第1章：开始\n第2章：继续\n正文不含编号。")
        let book = makeBook()
        let chapters = makeChapters(["第一章"])
        let (hits, _) = await collect(book, chapters, query: "第\\d+章", isRegex: true)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].matchedText, "第1章")
        XCTAssertEqual(hits[1].matchedText, "第2章")
    }

    func testInvalidRegexYieldsNoHitsWithoutCrash() async {
        seed(0, "正文")
        let book = makeBook()
        let chapters = makeChapters(["第一章"])
        let (hits, finished) = await collect(book, chapters, query: "([unclosed", isRegex: true)
        XCTAssertTrue(hits.isEmpty)
        XCTAssertNotNil(finished, "非法正则直接以 finished 收尾")
    }

    // MARK: - Cache boundary

    func testUncachedChapterSkippedWithoutSource() async throws {
        seed(0, "包含关键词的已缓存章节。")
        // 章节 1 无缓存，且 includeUncached=false：跳过
        let book = makeBook()
        let chapters = makeChapters(["第一章", "第二章"])
        let (hits, finished) = await collect(book, chapters, query: "关键词", includeUncached: false)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].chapterIndex, 0)
        let fin = try XCTUnwrap(finished)
        XCTAssertEqual(fin.chaptersSearched, 2, "未缓存章节也算「已搜索」，只是无命中")
    }

    func testEmptyQueryFinishesImmediately() async {
        seed(0, "正文")
        let book = makeBook()
        let chapters = makeChapters(["第一章"])
        let (hits, finished) = await collect(book, chapters, query: "   ")
        XCTAssertTrue(hits.isEmpty)
        XCTAssertNotNil(finished)
    }

    // MARK: - Query compile

    func testQueryCompileRejectsEmptyAndKeepsPlain() {
        XCTAssertNil(BookContentSearchService.SearchQuery.compile("", isRegex: false))
        XCTAssertNil(BookContentSearchService.SearchQuery.compile("  ", isRegex: false))
        XCTAssertNil(BookContentSearchService.SearchQuery.compile("([bad", isRegex: true))
        if case .plain(let kw)? = BookContentSearchService.SearchQuery.compile("石中剑", isRegex: false) {
            XCTAssertEqual(kw, "石中剑")
        } else {
            XCTFail("plain query should compile")
        }
    }
}

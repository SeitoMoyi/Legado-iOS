import XCTest
@testable import LegadoCore

/// P0-8: character-set resolution and `nextTocUrl` / `nextContentUrl` pagination.
final class CharsetAndPagingTests: XCTestCase {

    // MARK: helpers

    private func gbkData(_ text: String) -> Data {
        Data(text.data(using: CharsetDetector.gb18030)!)
    }

    private func html(_ body: String, charsetMeta: String? = nil) -> String {
        let head = charsetMeta.map { "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=\($0)\">" } ?? ""
        return "<html><head>\(head)<title>t</title></head><body>\(body)</body></html>"
    }

    // MARK: - Charset detection chain

    func testPremiseGbkBytesFailStrictUtf8() {
        // The scoring pass depends on this: invalid UTF-8 is detectable, not silently replaced.
        let gbk = gbkData("第三章 试探期的结束")
        XCTAssertNil(String(data: gbk, encoding: .utf8))
        XCTAssertFalse(String(decoding: gbk, as: UTF8.self).isEmpty) // what the old code produced
    }

    func testUtf8ContentPassesThrough() {
        let data = Data("<p>中文内容</p>".utf8)
        XCTAssertEqual(CharsetDetector.decode(data), "<p>中文内容</p>")
    }

    func testDecodesGbkDeclaredInHttpHeader() {
        let body = gbkData(html("<div id=\"txt\">第三章 试探期的结束与开始</div>"))
        let headers = ["Content-Type": "text/html; charset=GBK"]
        let decoded = CharsetDetector.decode(body, headers: headers)
        XCTAssertTrue(decoded.contains("第三章 试探期的结束与开始"), "got: \(decoded)")
    }

    func testDecodesGbkCaseInsensitiveAndQuotedHeader() {
        let body = gbkData("中文测试")
        let decoded = CharsetDetector.decode(body, headers: ["content-type": "text/html;charset=\"GB2312\""])
        XCTAssertEqual(decoded, "中文测试")
    }

    func testDecodesGbkDeclaredOnlyInMeta() {
        // No Content-Type charset; the sniffed `<meta>` must win over force-UTF8.
        let inner = "<div id=\"txt\">第四章 意外的收获</div>"
        let gbk = gbkData(html(inner, charsetMeta: "gbk"))
        let decoded = CharsetDetector.decode(gbk, headers: ["Content-Type": "text/html"])
        XCTAssertTrue(decoded.contains("第四章 意外的收获"), "got: \(decoded)")
    }

    func testStatisticalDetectorHandlesGbkWithoutAnyDeclaration() {
        let long = String(repeating: "他抬起头，看见远处的山在雾中若隐若现。", count: 40)
        let gbk = gbkData(html("<div>\(long)</div>"))
        let decoded = CharsetDetector.decode(gbk, headers: [:])
        XCTAssertTrue(decoded.contains("若隐若现"), "statistical path failed: \(decoded.prefix(60))")
    }

    func testBig5NeedsAnExplicitDeclaration() {
        // Documented limitation: NSString.stringEncoding(for:) mislabels Big5, so a Big5
        // page without a charset declaration cannot be recovered reliably.
        let text = "第九章 意外的收穫與結局測試"
        guard let encoded = text.data(using: CharsetDetector.big5Encoding) else {
            return XCTFail("fixture could not be encoded to Big5")
        }
        // With a declaration it works.
        let declared = CharsetDetector.decode(encoded, headers: ["Content-Type": "text/plain; charset=big5"])
        XCTAssertEqual(declared, text)
        // Statistical detection on the same bytes does not pick Big5.
        XCTAssertNotEqual(CharsetDetector.statisticalEncoding(for: encoded), CharsetDetector.big5Encoding)
    }

    func testBomIsStripped() {
        let withBom = Data([0xEF, 0xBB, 0xBF]) + "標題內容".data(using: .utf8)!
        XCTAssertEqual(CharsetDetector.decode(withBom), "標題內容")
    }

    func testEmptyDataDecodesToEmptyString() {
        XCTAssertEqual(CharsetDetector.decode(Data()), "")
    }

    func testDeclaredCharsetWinsOverHeaderAndMeta() {
        let gbk = gbkData(html("<meta charset=\"utf-8\"><div>中文宣告</div>", charsetMeta: "utf-8"))
        // declared says gbk; the page lies about utf-8.
        let decoded = CharsetDetector.decode(gbk, headers: ["Content-Type": "text/html; charset=utf-8"],
                                             declared: "gbk")
        XCTAssertTrue(decoded.contains("中文宣告"), "got: \(decoded)")
    }

    func testEncodingNameMapping() {
        for name in ["gbk", "GBK", "x-gbk", "gb2312", "GB_18030", "chinese"] {
            XCTAssertEqual(CharsetDetector.encoding(named: name), CharsetDetector.gb18030, "\(name)")
        }
        XCTAssertEqual(CharsetDetector.encoding(named: "utf-8"), .utf8)
        XCTAssertEqual(CharsetDetector.encoding(named: "Big5"), CharsetDetector.big5Encoding)
        XCTAssertNotNil(CharsetDetector.encoding(named: "big5-hkscs"))
        XCTAssertEqual(CharsetDetector.encoding(named: "Shift_JIS"), .shiftJIS)
        XCTAssertNotNil(CharsetDetector.encoding(named: "EUC-KR"))
        XCTAssertNil(CharsetDetector.encoding(named: "klingon"))
        XCTAssertNil(CharsetDetector.encoding(named: ""))
    }

    func testMetaCharsetParsingForms() {
        XCTAssertEqual(CharsetDetector.metaCharset(in: "<meta charset=\"gbk\">"), "gbk")
        XCTAssertEqual(CharsetDetector.metaCharset(in: "<meta charset=gb2312 >"), "gb2312")
        XCTAssertEqual(
            CharsetDetector.metaCharset(in: "<meta http-equiv=Content-Type content=\"text/html; charset=big5\">"),
            "big5")
        XCTAssertNil(CharsetDetector.metaCharset(in: "<meta name=\"viewport\">"))
    }

    func testPlausibilityFavorsCjk() {
        let chinese = "他在山間行走，風很大。"
        let mojibake = "Ê±¼äºº"
        XCTAssertGreaterThan(CharsetDetector.plausibility(chinese), CharsetDetector.plausibility(mojibake))
        XCTAssertEqual(CharsetDetector.plausibility("plain ascii"), 0)
    }

    // MARK: - replaceRegex chaining

    func testApplyReplacePairsChainsMultipleRules() {
        let text = "第一章 广告文字A 正文 广告文字B"
        let spec = "广告文字A##A1##广告文字B##B2"
        let result = BookContentService.applyReplacePairs(text, spec: spec)
        XCTAssertTrue(result.contains("A1"))
        XCTAssertTrue(result.contains("B2"))
        XCTAssertFalse(result.contains("广告文字"))
    }

    func testApplyReplacePairsKeepsSinglePairBehaviour() {
        let result = BookContentService.applyReplacePairs("hello 广告 world", spec: "广告##AD")
        XCTAssertEqual(result, "hello AD world")
    }

    func testApplyReplacePairsIgnoresInvalidRegexAndEmptyPatterns() {
        XCTAssertEqual(BookContentService.applyReplacePairs("abc", spec: "##"), "abc")
        XCTAssertEqual(BookContentService.applyReplacePairs("abc", spec: ""), "abc")
        // A broken pattern must leave the text untouched, not crash or blank it.
        XCTAssertEqual(BookContentService.applyReplacePairs("abc", spec: "([unclosed##X"), "abc")
    }

    // MARK: - TOC normalisation

    func testNormalizeTocDedupesByUrlAndReindexes() {
        let raw = [
            BookChapter(bookUrl: "b", url: "u1", title: "第一章", index: 0),
            BookChapter(bookUrl: "b", url: "u2", title: "第二章", index: 5),
            BookChapter(bookUrl: "b", url: "u1", title: "第一章 dup", index: 9),
            BookChapter(bookUrl: "b", url: "u3", title: "第三章", index: 77)
        ]
        let normalized = BookContentService.normalizeToc(raw, listRule: "li a")
        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized.map { $0.url }, ["u1", "u2", "u3"])
        XCTAssertEqual(normalized.map { $0.title }, ["第一章", "第二章", "第三章"])
        XCTAssertEqual(normalized.map { $0.index }, [0, 1, 2])
    }

    func testNormalizeTocHonoursReversePrefix() {
        let raw = [
            BookChapter(bookUrl: "b", url: "u1", title: "一", index: 0),
            BookChapter(bookUrl: "b", url: "u2", title: "二", index: 1)
        ]
        let reversed = BookContentService.normalizeToc(raw, listRule: "-li a")
        XCTAssertEqual(reversed.map { $0.title }, ["二", "一"])
        XCTAssertEqual(reversed.map { $0.index }, [0, 1])

        // '+' only means "skip nothing", it must not flip the order.
        let plus = BookContentService.normalizeToc(raw, listRule: "+li a")
        XCTAssertEqual(plus.map { $0.title }, ["一", "二"])
    }

    // MARK: - makeAnalyzer / paging constants

    func testPageCapsAreSane() {
        XCTAssertLessThan(BookContentService.maxContentPages, BookContentService.maxTocPages)
        XCTAssertGreaterThan(BookContentService.maxContentPages, 1)
        XCTAssertGreaterThan(BookContentService.maxConcurrentPages, 0)
    }
}

/// Drives `NetworkClient.shared` through `MockWebDAVURLProtocol` to exercise the
/// `nextContentUrl` / `nextTocUrl` loops end-to-end.
final class PagedFetchTests: XCTestCase {

    private var savedClient: NetworkClient!
    private var seenURLs: [String] = []
    private let seenLock = NSLock()
    private let bookUrl = "https://paged.test/book"

    override func setUp() {
        super.setUp()
        savedClient = NetworkClient.shared
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockWebDAVURLProtocol.self]
        NetworkClient.shared = NetworkClient(session: URLSession(configuration: config))
        seenURLs = []
        MockWebDAVURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockWebDAVURLProtocol.requestHandler = nil
        NetworkClient.shared = savedClient
        BookContentService.shared.clearCache(for: bookUrl)
        super.tearDown()
    }

    private func source(ruleContent: ContentRule, ruleToc: TocRule? = nil) -> BookSource {
        BookSource(bookSourceUrl: "https://paged.test", bookSourceName: "分页测试源",
                   ruleToc: ruleToc, ruleContent: ruleContent)
    }

    private func stub(_ routes: [String: (body: String, headers: [String: String])]) {
        MockWebDAVURLProtocol.requestHandler = { request in
            let url = request.url!
            self.seenLock.lock()
            self.seenURLs.append(url.absoluteString)
            self.seenLock.unlock()
            guard let route = routes[url.path] else {
                let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data())
            }
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                      headerFields: route.headers)!
            return (resp, Data(route.body.utf8))
        }
    }

    private func page(_ text: String, next: String?) -> String {
        let anchor = next.map { "<a class=\"more\" href=\"\($0)\">next</a>" } ?? ""
        return "<html><body><div id=\"txt\">\(text)</div>\(anchor)</body></html>"
    }

    func testChapterSplitAcrossThreePagesIsJoinedInOrder() async throws {
        stub([
            "/c1": (page("第一段一", next: "/c2"), ["Content-Type": "text/html; charset=utf-8"]),
            "/c2": (page("第一段二", next: "/c3"), ["Content-Type": "text/html; charset=utf-8"]),
            "/c3": (page("第一段三", next: nil), ["Content-Type": "text/html; charset=utf-8"])
        ])

        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        let content = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter,
            source: source(ruleContent: ContentRule(content: "#txt@text", nextContentUrl: ".more@href")),
            nextChapterUrl: "https://paged.test/nextchapter")

        XCTAssertTrue(content.contains("第一段一"), content)
        XCTAssertTrue(content.contains("第一段二"), content)
        XCTAssertTrue(content.contains("第一段三"), content)
        XCTAssertEqual(seenURLs.count, 3)
        XCTAssertTrue(content.range(of: "第一段一")!.upperBound < content.range(of: "第一段三")!.lowerBound)
    }

    func testChapterStopsWhenNextUrlIsTheNextChapter() async throws {
        stub([
            "/c1": (page("本章内容", next: "/c2"), ["Content-Type": "text/html"]),
            "/c2": (page("不该出现", next: nil), ["Content-Type": "text/html"])
        ])

        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        let content = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter,
            source: source(ruleContent: ContentRule(content: "#txt@text", nextContentUrl: ".more@href")),
            nextChapterUrl: "https://paged.test/c2")

        XCTAssertTrue(content.contains("本章内容"), content)
        XCTAssertFalse(content.contains("不该出现"), content)
        XCTAssertEqual(seenURLs, ["https://paged.test/c1"])
    }

    func testChapterLoopTerminatesOnSelfReferencingNextUrl() async throws {
        stub([
            "/c1": (page("循环内容", next: "/c1"), ["Content-Type": "text/html"])
        ])

        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        let content = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter,
            source: source(ruleContent: ContentRule(content: "#txt@text", nextContentUrl: ".more@href")),
            nextChapterUrl: nil)

        XCTAssertTrue(content.contains("循环内容"))
        XCTAssertEqual(seenURLs.count, 1, "visited set must stop the cycle: \(seenURLs)")
    }

    func testChapterWithoutNextRuleFetchesOnce() async throws {
        stub(["/c1": (page("单页内容", next: "/c2"), ["Content-Type": "text/html"])])

        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        _ = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter,
            source: source(ruleContent: ContentRule(content: "#txt@text")),
            nextChapterUrl: nil)

        XCTAssertEqual(seenURLs, ["https://paged.test/c1"])
    }

    func testChapterIsCachedAfterFetchAndReused() async throws {
        stub(["/c1": (page("缓存内容", next: nil), ["Content-Type": "text/html"])])
        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        let src = source(ruleContent: ContentRule(content: "#txt@text"))

        _ = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: src)
        let firstRequestCount = seenURLs.count
        let second = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: src)

        XCTAssertEqual(firstRequestCount, 1)
        XCTAssertEqual(seenURLs.count, firstRequestCount, "second read must come from disk cache")
        XCTAssertTrue(second.contains("缓存内容"))
    }

    func testTocFollowsNextTocUrlAndDedupes() async throws {
        func tocPage(_ entries: [(slug: String, title: String)], next: String?) -> String {
            let items = entries.map { "<li><a href=\"/read/\($0.slug)\">\($0.title)</a></li>" }.joined()
            let anchor = next.map { "<a class=\"nt\" href=\"\($0)\">more</a>" } ?? ""
            return "<html><body><ul>\(items)</ul>\(anchor)</body></html>"
        }
        stub([
            "/toc": (tocPage([("c1", "第一章"), ("c2", "第二章")], next: "/toc2"),
                     ["Content-Type": "text/html"]),
            // c1 repeats on purpose: dedupe must drop it.
            "/toc2": (tocPage([("c3", "第三章"), ("c1", "第一章")], next: nil),
                      ["Content-Type": "text/html"])
        ])

        let book = Book(bookUrl: self.bookUrl, name: "分页书", author: "作者",
                        origin: "https://paged.test", originName: "分页测试源",
                        tocUrl: "https://paged.test/toc")
        let src = source(
            ruleContent: ContentRule(content: "#txt@text"),
            ruleToc: TocRule(chapterList: "ul li", chapterName: "a@text", chapterUrl: "a@href",
                             nextTocUrl: ".nt@href"))

        let (_, chapters) = try await BookContentService.shared.fetchBookDetail(book: book, source: src)

        XCTAssertEqual(chapters.map { $0.title }, ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map { $0.index }, [0, 1, 2])
        XCTAssertEqual(chapters.map { $0.url },
                       ["https://paged.test/read/c1", "https://paged.test/read/c2",
                        "https://paged.test/read/c3"])
    }

    func testRetryOptionRefetchesOnServerError() async throws {
        var attempts = 0
        let okBody = Data(page("重试成功", next: nil).utf8)
        MockWebDAVURLProtocol.requestHandler = { request in
            attempts += 1
            let url = request.url!
            if attempts < 3 {
                let resp = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data())
            }
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                      headerFields: ["Content-Type": "text/html"])!
            return (resp, okBody)
        }

        let parsed = try XCTUnwrap(NetworkClient.parseLegadoUrl(
            "https://paged.test/c1,{\"retry\":3}", defaultHeader: nil, baseUrl: "https://paged.test"))
        XCTAssertEqual(parsed.retry, 3)

        let response = try await NetworkClient.shared.request(parsed: parsed)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(attempts, 3)
    }

    func testRetryIsClampedAndFourXIsNotRetried() async throws {
        var attempts = 0
        MockWebDAVURLProtocol.requestHandler = { request in
            attempts += 1
            let url = request.url!
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("nope".utf8))
        }
        let parsed = try XCTUnwrap(NetworkClient.parseLegadoUrl(
            "https://paged.test/x,{\"retry\":999}", defaultHeader: nil, baseUrl: "https://paged.test"))
        XCTAssertEqual(parsed.retry, NetworkClient.maxRetry)

        let response = try await NetworkClient.shared.request(parsed: parsed)
        XCTAssertEqual(response.statusCode, 404)
        XCTAssertEqual(attempts, 1, "4xx is a real answer and must not be retried")
    }
}

final class NetworkRequestRegressionTests: XCTestCase {
    func testRelativeUrlsUseUrlResolutionInsteadOfStringConcatenation() throws {
        let base = "https://example.com/books/detail.html"
        let cases = [
            "/search": "https://example.com/search",
            "next.html": "https://example.com/books/next.html",
            "../toc": "https://example.com/toc",
            "//cdn.example.com/chapter": "https://cdn.example.com/chapter"
        ]
        for (relative, expected) in cases {
            XCTAssertEqual(try XCTUnwrap(NetworkClient.parseLegadoUrl(relative, baseUrl: base)).url.absoluteString, expected)
        }
        XCTAssertNil(NetworkClient.parseLegadoUrl(""))
        XCTAssertNil(NetworkClient.parseLegadoUrl("/relative-without-base"))
        XCTAssertNil(NetworkClient.parseLegadoUrl("file:///tmp/book.txt"))
    }

    func testOptionsAfterCommaInUrlAndCaseInsensitiveHeaders() throws {
        let request = try XCTUnwrap(NetworkClient.parseLegadoUrl(
            #"https://example.com/a,b,{"method":"POST","headers":{"user-agent":"new","content-type":"text/plain"},"body":{"key":"value"}}"#,
            defaultHeader: #"{"User-Agent":"old","Content-Type":"old"}"#))
        XCTAssertEqual(request.url.path, "/a,b")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers.filter { $0.key.lowercased() == "user-agent" }.count, 1)
        XCTAssertEqual(request.headers["user-agent"], "new")
        XCTAssertEqual(request.headers.filter { $0.key.lowercased() == "content-type" }.count, 1)
        XCTAssertEqual(request.headers["content-type"], "text/plain")
    }

    func testPostBodyHonorsDeclaredCharset() throws {
        let request = try XCTUnwrap(NetworkClient.parseLegadoUrl(
            #"https://example.com,{"method":"POST","charset":"gbk","body":"关键词=中文"}"#))
        XCTAssertEqual(request.body, "关键词=中文".data(using: CharsetDetector.gb18030))
    }

    func testPublicRequestInitializerClampsRetry() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertEqual(NetworkClient.ParsedRequest(url: url, method: "GET", headers: [:], body: nil, retry: -1).retry, 0)
        XCTAssertEqual(NetworkClient.ParsedRequest(url: url, method: "GET", headers: [:], body: nil, retry: Int.max).retry, NetworkClient.maxRetry)
    }

    func testCancelledRequestDoesNotStartOrRetry() async throws {
        let request = try XCTUnwrap(NetworkClient.parseLegadoUrl("https://cancelled.test,{\"retry\":3}"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NetworkClient().request(parsed: request)
        }
        do {
            _ = try await task.value
            XCTFail("cancelled work must throw before issuing a request")
        } catch is CancellationError { }
    }

    func testCookieDomainUsesDnsLabelBoundaries() {
        XCTAssertTrue(NetworkClient.cookieDomain(".example.com", matchesHost: "www.example.com"))
        XCTAssertTrue(NetworkClient.cookieDomain("EXAMPLE.COM", matchesHost: "example.com"))
        XCTAssertFalse(NetworkClient.cookieDomain("evil-example.com", matchesHost: "example.com"))
        XCTAssertFalse(NetworkClient.cookieDomain("example.com", matchesHost: "example.com.attacker.test"))
        XCTAssertFalse(NetworkClient.cookieDomain("api.example.com", matchesHost: "example.com"))
        XCTAssertFalse(NetworkClient.cookieDomain("", matchesHost: "example.com"))
    }
}

extension PagedFetchTests {
    func testDetailRulesChooseMetadataAndFetchSeparateToc() async throws {
        stub([
            "/book": (#"{"introductionZh":"do not override rules","payload":{"name":"正确书名","author":"规则作者","intro":"规则简介","toc":"/toc"}}"#, [:]),
            "/toc": ("<ul><li><a href='/one'>第一章</a></li></ul>", [:])
        ])
        var src = source(ruleContent: ContentRule(content: "#txt@text"),
                         ruleToc: TocRule(chapterList: "li", chapterName: "a@text", chapterUrl: "a@href"))
        src.ruleBookInfo = BookInfoRule(initRule: "$.payload", name: "$.name", author: "$.author", intro: "$.intro", tocUrl: "$.toc")
        let result = try await BookContentService.shared.fetchBookDetailResult(
            book: Book(bookUrl: bookUrl, name: "旧书名", author: "旧作者"), source: src)
        XCTAssertEqual(result.book.name, "正确书名")
        XCTAssertEqual(result.book.intro, "规则简介")
        XCTAssertEqual(result.book.author, "规则作者")
        XCTAssertEqual(result.book.tocUrl, "https://paged.test/toc")
        XCTAssertEqual(result.chapters.map(\.title), ["第一章"])
        XCTAssertTrue(result.complete)
        XCTAssertEqual(seenURLs, ["https://paged.test/book", "https://paged.test/toc"])
    }

    func testChapterUrlIsNotRewrittenForSpecificApiLayouts() async throws {
        let apiBookUrl = "https://paged.test/api/novel/123"
        defer { BookContentService.shared.clearCache(for: apiBookUrl) }
        stub(["/chapter/456": (page("书源指定的正文", next: nil), [:])])
        let chapter = BookChapter(bookUrl: apiBookUrl, url: "https://paged.test/chapter/456", title: "第一章", index: 0)
        let text = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: source(ruleContent: ContentRule(content: "#txt@text")))
        XCTAssertEqual(text, "书源指定的正文")
        XCTAssertEqual(seenURLs, ["https://paged.test/chapter/456"])
    }

    func testFailedParallelFragmentDoesNotCachePartialChapter() async throws {
        stub([
            "/c1": (#"{"body":"第一段","next":["/c2","/missing"]}"#, [:]),
            "/c2": (#"{"body":"第二段"}"#, [:])
        ])
        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        let text = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter, source: source(ruleContent: ContentRule(content: "$.body", nextContentUrl: "$.next[*]")))
        XCTAssertTrue(text.contains("第一段"))
        XCTAssertTrue(text.contains("第二段"))
        XCTAssertFalse(BookContentService.shared.hasCachedChapter(bookUrl: bookUrl, chapterIndex: 0))
    }

    func testParallelPagesDeduplicateAndStopBeforeNextChapter() async throws {
        stub([
            "/c1": (#"{"body":"第一段","next":["/c1","/c2","/c2","/nextChapter","/unreachable"]}"#, [:]),
            "/c2": (#"{"body":"第二段"}"#, [:])
        ])
        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "第一章", index: 0)
        let text = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter, source: source(ruleContent: ContentRule(content: "$.body", nextContentUrl: "$.next[*]")),
            nextChapterUrl: "https://paged.test/nextChapter")
        XCTAssertEqual(text, "第一段\n第二段")
        XCTAssertEqual(seenURLs, ["https://paged.test/c1", "https://paged.test/c2"])
    }

    func testFailedParallelTocPageIsMarkedIncomplete() async throws {
        stub([
            "/toc": ("<ul><li><a href='/one'>第一章</a></li></ul><a class='next' href='/toc2'>2</a><a class='next' href='/missing'>3</a>", [:]),
            "/toc2": ("<ul><li><a href='/two'>第二章</a></li></ul>", [:])
        ])
        let result = try await BookContentService.shared.fetchBookDetailResult(
            book: Book(bookUrl: bookUrl, name: "书", author: "作者", tocUrl: "https://paged.test/toc"),
            source: source(ruleContent: ContentRule(content: "text"), ruleToc: TocRule(
                chapterList: "li", chapterName: "a@text", chapterUrl: "a@href", nextTocUrl: "a.next@href")))
        XCTAssertEqual(result.chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertFalse(result.complete)
    }

    func testCachedLocalEditOverridesOriginalFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "原文件".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let chapter = BookChapter(bookUrl: bookUrl, url: file.absoluteString, title: "第一章", index: 0)
        BookContentService.shared.saveCachedChapterContent(bookUrl: bookUrl, chapterIndex: 0, content: "编辑后的正文")
        let edited = try await BookContentService.shared.fetchChapterContent(chapter: chapter)
        XCTAssertEqual(edited, "编辑后的正文")
        BookContentService.shared.clearCachedChapter(bookUrl: bookUrl, chapterIndex: 0)
        let original = try await BookContentService.shared.fetchChapterContent(chapter: chapter)
        XCTAssertEqual(original, "原文件")
    }
}

extension PagedFetchTests {
    func testSearchKeepsParameterNamesContainingSearchKey() async throws {
        stub(["/search": (#"{"books":[{"name":"书","author":"作者","url":"/book"}]}"#, [:])])
        var src = source(ruleContent: ContentRule(content: "text"))
        src.searchUrl = "/search?searchKey={{key}}&page={{page}}"
        src.ruleSearch = SearchRule(bookList: "$.books[*]", name: "$.name", author: "$.author", bookUrl: "$.url")
        let books = try await BookSearchService.shared.search(source: src, key: "test", page: 2)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(seenURLs, ["https://paged.test/search?searchKey=test&page=2"])
    }

    func testParallelContentCannotExceedTotalPageCap() async throws {
        let next = (1...BookContentService.maxContentPages + 5).map { "/p\($0)" }
        let initial = String(data: try JSONSerialization.data(withJSONObject: ["body": "开始", "next": next]), encoding: .utf8)!
        var routes = ["/c1": (body: initial, headers: [String: String]())]
        for path in next { routes[path] = (#"{"body":"续页"}"#, [:]) }
        stub(routes)
        let chapter = BookChapter(bookUrl: bookUrl, url: "https://paged.test/c1", title: "章", index: 0)
        _ = try await BookContentService.shared.fetchChapterContent(
            chapter: chapter, source: source(ruleContent: ContentRule(content: "$.body", nextContentUrl: "$.next[*]")))
        XCTAssertEqual(seenURLs.count, BookContentService.maxContentPages)
        XCTAssertFalse(BookContentService.shared.hasCachedChapter(bookUrl: bookUrl, chapterIndex: 0))
    }
}

extension PagedFetchTests {
    func testJavaPostUsesSourceHeadersAndRelativeUrls() throws {
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://paged.test/login")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=source")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom"), "explicit")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        var src = source(ruleContent: ContentRule(content: "text"))
        src.header = #"{"Cookie":"session=source"}"#
        let engine = JSEngine(bookSource: src, baseUrl: src.bookSourceUrl)
        XCTAssertEqual(engine.eval(script: #"java.post('/login', '{}', {'X-Custom':'explicit'}).body()"#) as? String, "ok")
    }

    func testHeaderScriptCanFetchWithoutRecursiveHeaderEvaluation() {
        stub(["/header": ("header-value", [:])])
        var src = source(ruleContent: ContentRule(content: "text"))
        src.header = #"<js>JSON.stringify({'X-Value':java.ajax('/header')})</js>"#
        let header = JSEngine.resolvedSourceHeader(src)
        XCTAssertTrue(header?.contains("header-value") == true)
        XCTAssertEqual(seenURLs, ["https://paged.test/header"])
    }
}

extension PagedFetchTests {
    func testDirectoryFormattingRunsAfterPaginationDeduplicationAndReverse() async throws {
        stub([
            "/toc": (#"{"chapters":[{"name":"第三章","url":"/3","vip":"yes"},{"name":"第二章","url":"/2"}],"next":"/toc2"}"#, [:]),
            "/toc2": (#"{"chapters":[{"name":"第二章重复","url":"/2"},{"name":"第一章","url":"/1"}]}"#, [:])
        ])
        let rule = TocRule(chapterList: "-$.chapters[*]", chapterName: "$.name", chapterUrl: "$.url",
                           formatJs: "++gInt + ':' + index + ':' + title", isVip: "$.vip", nextTocUrl: "$.next")
        let result = try await BookContentService.shared.fetchBookDetailResult(
            book: Book(bookUrl: bookUrl, name: "书", author: "作者", tocUrl: "https://paged.test/toc"),
            source: source(ruleContent: ContentRule(content: "text"), ruleToc: rule))
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.chapters.map(\.title), ["1:1:第一章", "2:2:第二章", "3:3:第三章"])
        XCTAssertEqual(result.chapters.map(\.index), [0, 1, 2])
        XCTAssertEqual(result.chapters.last?.isVip, true)
        XCTAssertEqual(result.book.latestChapterTitle, "3:3:第三章")
    }

    func testFormattedLinklessVolumeDoesNotMakeNetworkRequest() async throws {
        stub(["/toc": (#"{"chapters":[{"name":"第一卷","volume":"true","intro":"卷介绍"}]}"#, [:])])
        let result = try await BookContentService.shared.fetchBookDetailResult(
            book: Book(bookUrl: bookUrl, name: "书", author: "作者", tocUrl: "https://paged.test/toc"),
            source: source(ruleContent: ContentRule(content: "text"), ruleToc: TocRule(
                chapterList: "$.chapters[*]", chapterName: "$.name", chapterUrl: "$.url",
                formatJs: "title + '（卷）'", isVolume: "$.volume", updateTime: "$.intro")))
        let volume = try XCTUnwrap(result.chapters.first)
        XCTAssertEqual(volume.title, "第一卷（卷）")
        let text = try await BookContentService.shared.fetchChapterContent(chapter: volume, source: source(ruleContent: ContentRule(content: "text")))
        XCTAssertEqual(text, "卷介绍")
        XCTAssertEqual(seenURLs, ["https://paged.test/toc"])
        BookContentService.shared.saveCachedChapterContent(bookUrl: bookUrl, chapterIndex: 0, content: "编辑卷介绍")
        let edited = try await BookContentService.shared.fetchChapterContent(chapter: volume)
        XCTAssertEqual(edited, "编辑卷介绍")
    }
}

extension PagedFetchTests {
    func testDetailInitAndTemplatedIntroExecuteTogether() async throws {
        stub([
            "/book": (#"{"payload":{"name":"正确书名","introductionZh":"真正的简介","toc":"/toc","syncAt":1700000000}}"#, [:]),
            "/toc": ("<li><a href='/one'>第一章</a></li>", [:])
        ])
        var src = source(ruleContent: ContentRule(content: "text"), ruleToc: TocRule(
            chapterList: "li", chapterName: "a@text", chapterUrl: "a@href"))
        src.ruleBookInfo = BookInfoRule(
            initRule: "<js>JSON.stringify(JSON.parse(result).payload)</js>", name: "$.name",
            intro: "<js>var data = JSON.parse(result); '最近同步：' + java.timeFormat('{{$.syncAt}}' * 1000) + '\\n' + data.introductionZh;</js>",
            tocUrl: "$.toc")
        let result = try await BookContentService.shared.fetchBookDetailResult(
            book: Book(bookUrl: bookUrl, name: "旧书名", author: "作者"), source: src)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.book.name, "正确书名")
        XCTAssertTrue(result.book.intro?.hasPrefix("最近同步：2023-11-") == true)
        XCTAssertTrue(result.book.intro?.hasSuffix("真正的简介") == true)
        XCTAssertFalse(result.book.intro?.contains("var data") == true)
        XCTAssertEqual(result.chapters.count, 1)
    }
}

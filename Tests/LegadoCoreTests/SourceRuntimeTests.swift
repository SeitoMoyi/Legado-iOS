import XCTest
import JavaScriptCore
@testable import LegadoCore

final class SourceRuntimeTests: XCTestCase {
    private var savedClient: NetworkClient!
    private var urls: [String] = []
    private let lock = NSLock()
    private let base = "https://runtime.test"

    override func setUp() {
        savedClient = NetworkClient.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        NetworkClient.shared = NetworkClient(session: URLSession(configuration: configuration))
        SourceLibraryStore.shared.clearCache()
        MockWebDAVURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        NetworkClient.shared = savedClient
        MockWebDAVURLProtocol.requestHandler = nil
        SourceLibraryStore.shared.clearCache()
    }

    private func stub(_ routes: [String: String]) {
        MockWebDAVURLProtocol.requestHandler = { request in
            self.lock.lock(); self.urls.append(request.url!.path); self.lock.unlock()
            let body = routes[request.url!.path]
            return (HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200,
                                    httpVersion: nil, headerFields: nil)!, body.map { Data($0.utf8) })
        }
    }

    private func source(hook: String? = nil, library: String? = nil) -> BookSource {
        BookSource(bookSourceUrl: base, bookSourceName: "运行时样本", searchUrl: "/search?key={{key}}", jsLib: library,
                   ruleSearch: SearchRule(bookList: "$.items[*]", name: "$.name", author: "$.author", bookUrl: "$.url"),
                   ruleBookInfo: BookInfoRule(name: "$.name", author: "$.author", intro: "$.intro", tocUrl: "$.toc"),
                   ruleToc: TocRule(preUpdateJs: hook, chapterList: "$.chapters[*]", chapterName: "$.name", chapterUrl: "$.url"),
                   ruleContent: ContentRule(content: "$.body"))
    }

    private func book() -> Book {
        var book = Book(bookUrl: base + "/old-book", name: "书名", author: "作者", origin: base, tocUrl: base + "/old-toc")
        book.durChapterIndex = 3
        book.durChapterPos = 24
        book.variable = #"{"custom":"existing"}"#
        return book
    }

    func testInlineLibraryLoadsBeforeHeadersAndRulesWithoutSharingGlobals() throws {
        var src = source(library: "var counter = 0; function label(value) { return '库:' + value; }")
        src.header = #"<js>JSON.stringify({'X-Test':label('header')})</js>"#
        let first = JSEngine(bookSource: src)
        try first.checkReady()
        XCTAssertEqual(first.eval(script: "label('正文')") as? String, "库:正文")
        XCTAssertEqual(first.eval(script: "++counter") as? Int, 1)
        let header = try XCTUnwrap(JSEngine.resolvedSourceHeader(src, engine: first))
        XCTAssertTrue(header.contains("库:header"))
        let second = JSEngine(bookSource: src)
        XCTAssertEqual(second.eval(script: "++counter") as? Int, 1)
    }

    func testRemoteLibraryMapPreservesOrderCachesTextAndDoesNotLeakLoginHeaders() throws {
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            self.urls.append(request.url!.path)
            let script = request.url!.path == "/b.js" ? "var order=['b'];" : "order.push('a');"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(script.utf8))
        }
        var src = source(library: #"{"b":"https://runtime.test/b.js","a":"https://runtime.test/a.js"}"#)
        src.loginHeader = #"{"Authorization":"Bearer fixture","Cookie":"fixture=1"}"#
        let first = JSEngine(bookSource: src)
        try first.checkReady()
        XCTAssertEqual(first.eval(script: "order.join(',')") as? String, "b,a")
        _ = first.eval(script: "order.push('local')")
        let second = JSEngine(bookSource: src)
        try second.checkReady()
        XCTAssertEqual(second.eval(script: "order.join(',')") as? String, "b,a")
        XCTAssertEqual(urls, ["/b.js", "/a.js"])
    }

    func testLibraryFailuresAreReportedBeforeBookRequests() async {
        stub([:])
        let src = source(library: #"{"missing":"https://runtime.test/missing.js"}"#)
        do {
            _ = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src)
            XCTFail("A missing dependency must not silently produce a partial book")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("jsLib"))
        }
        XCTAssertEqual(urls, ["/missing.js"])
        let invalid = JSEngine(bookSource: source(library: "function broken( {"))
        XCTAssertThrowsError(try invalid.checkReady())
        XCTAssertNil(invalid.eval(script: "'must not execute'"))
    }

    func testLibraryFieldIsModeledAndSurvivesJsonRoundTrip() throws {
        let data = Data(#"{"bookSourceUrl":"https://runtime.test","jsLib":"function helper(){return 3;}","future":true}"#.utf8)
        let src = try XCTUnwrap(BookSource.decodeWithExtras(from: data))
        XCTAssertEqual(src.jsLib, "function helper(){return 3;}")
        XCTAssertNil(src.extra["jsLib"])
        XCTAssertEqual(src.extra["future"], .bool(true))
        XCTAssertEqual(try BookSource.decodeWithExtras(from: JSONEncoder().encode(src)), src)
    }

    func testRefreshTocUrlUpdatesTheBookBeforeTheDirectoryRequest() async throws {
        stub([
            "/old-book": #"{"name":"书名","author":"作者","toc":"/fresh-toc"}"#,
            "/fresh-toc": #"{"chapters":[{"name":"第一章","url":"/one"}]}"#
        ])
        let src = source(hook: "java.refreshTocUrl(); if (!book.tocUrl.endsWith('/fresh-toc')) throw Error('stale'); book.putVariable('hook','done');")
        let result = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src, runPreUpdateJs: true)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.book.tocUrl, base + "/fresh-toc")
        XCTAssertEqual(result.book.getVariable("hook"), "done")
        XCTAssertEqual(result.book.getVariable("custom"), "existing")
        XCTAssertEqual(result.book.durChapterIndex, 3)
        XCTAssertEqual(result.chapters.first?.title, "第一章")
        XCTAssertEqual(urls, ["/old-book", "/fresh-toc"])
    }

    func testReGetBookFindsAnExactMatchBeforeRequestingAnExpiredUrl() async throws {
        stub([
            "/search": #"{"items":[{"name":"书名","author":"其他作者","url":"/wrong"},{"name":"书名","author":"作者","url":"/new-book"}]}"#,
            "/new-book": #"{"name":"书名","author":"作者","toc":"/new-toc"}"#,
            "/new-toc": #"{"chapters":[{"name":"新第一章","url":"/one"}]}"#
        ])
        let src = source(hook: "java.reGetBook(); if (!book.bookUrl.endsWith('/new-book')) throw Error('stale');")
        let result = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src, runPreUpdateJs: true)
        XCTAssertEqual(result.book.bookUrl, base + "/new-book")
        XCTAssertEqual(result.book.tocUrl, base + "/new-toc")
        XCTAssertEqual(result.chapters.first?.bookUrl, base + "/new-book")
        XCTAssertEqual(result.book.getVariable("custom"), "existing")
        XCTAssertEqual(result.book.durChapterPos, 24)
        XCTAssertEqual(urls, ["/search", "/new-book", "/new-toc"])
    }

    func testHookUsesLibraryAndDirectBookMutations() async throws {
        stub(["/direct": #"{"chapters":[{"name":"第一章","url":"/one"}]}"#])
        let src = source(hook: "book.tocUrl = directory();", library: "function directory(){return '/direct';}")
        let result = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src, runPreUpdateJs: true)
        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(urls, ["/direct"])
    }

    func testHookIsOptInAndErrorsDoNotFetchOrCachePartialDirectory() async throws {
        stub([
            "/old-book": #"{"toc":"/old-toc"}"#,
            "/old-toc": #"{"chapters":[{"name":"章","url":"/one"}]}"#
        ])
        let src = source(hook: "throw new Error('broken hook')")
        let initial = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src)
        XCTAssertEqual(initial.chapters.count, 1)
        let initialRequests = urls
        do {
            _ = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src, runPreUpdateJs: true)
            XCTFail("The hook error must propagate")
        } catch { XCTAssertTrue(error.localizedDescription.contains("preUpdateJs")) }
        XCTAssertEqual(urls, initialRequests)
    }

    func testPreUpdateMethodsAreRejectedOutsideTheHook() {
        let engine = JSEngine(bookSource: source(), book: book())
        XCTAssertThrowsError(try engine.evalChecked(script: "java.refreshTocUrl()", stage: "rule"))
        XCTAssertThrowsError(try engine.evalChecked(script: "java.reGetBook()", stage: "rule"))
    }

    func testCancelledHookDoesNotStartNetworkRequests() async {
        stub([:])
        let src = source(hook: "java.refreshTocUrl()")
        let original = book()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SourcePreUpdateService().run(book: original, source: src)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(urls.isEmpty)
    }
}

extension SourceRuntimeTests {
    func testCancellingHookCancelsItsInFlightNativeRequest() async {
        let started = expectation(description: "Details request started")
        let stopped = expectation(description: "Details request cancelled")
        SuspendedRuntimeURLProtocol.onStart = { started.fulfill() }
        SuspendedRuntimeURLProtocol.onStop = { stopped.fulfill() }
        defer {
            SuspendedRuntimeURLProtocol.onStart = nil
            SuspendedRuntimeURLProtocol.onStop = nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuspendedRuntimeURLProtocol.self]
        NetworkClient.shared = NetworkClient(session: URLSession(configuration: configuration))
        let original = book()
        let src = source(hook: "java.refreshTocUrl()")
        let task = Task { try await SourcePreUpdateService().run(book: original, source: src) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
    }
}

private final class SuspendedRuntimeURLProtocol: URLProtocol {
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?() }
    override func stopLoading() { Self.onStop?() }
}

extension SourceRuntimeTests {
    func testJavaVariablesSurviveTheHookAndReachDirectoryRules() async throws {
        stub(["/direct": #"{"chapters":[{"name":"原章名","url":"/one"}]}"#])
        var src = source(hook: "java.put('prefix','新'); book.tocUrl='/direct';")
        src.ruleToc?.chapterName = "@js:java.get('prefix') + java.get('bookName')"
        let result = try await BookContentService.shared.fetchBookDetailResult(book: book(), source: src, runPreUpdateJs: true)
        XCTAssertEqual(result.book.getVariable("prefix"), "新")
        XCTAssertEqual(result.book.getVariable("custom"), "existing")
        XCTAssertEqual(result.chapters.first?.title, "新书名")
    }
}

extension SourceRuntimeTests {
    func testJavaGetDoesNotResurrectDeletedOrEmptyBookVariables() throws {
        let engine = JSEngine(bookSource: source(), book: book())
        XCTAssertEqual(try engine.evalChecked(script: "java.put('key','old'); book.putVariable('key',null); java.get('key');", stage: "test") as? String, "")
        XCTAssertEqual(try engine.evalChecked(script: "java.put('key','old'); book.putVariable('key',''); java.get('key');", stage: "test") as? String, "")
        XCTAssertEqual(try engine.evalChecked(script: "java.put('key','new'); java.get('key');", stage: "test") as? String, "new")
    }

    func testBookBridgeAndLibraryContextsAreReleased() throws {
        weak var releasedEngine: JSEngine?
        weak var releasedContext: JSContext?
        try autoreleasepool {
            let engine = JSEngine(bookSource: source(library: "function helper(){return 'ok';}"), book: book())
            try engine.checkReady()
            _ = try engine.evalChecked(script: "java.put('release-test',helper());", stage: "test")
            releasedEngine = engine
            releasedContext = engine.context
        }
        XCTAssertNil(releasedEngine)
        XCTAssertNil(releasedContext, "Native variable callbacks must not retain the exported book JS object")
    }
}

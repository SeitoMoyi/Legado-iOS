import XCTest
import LegadoRuntime
@testable import LegadoCore

final class RuntimeIntegrationTests: XCTestCase {
    @MainActor
    func testAsyncCategoriesCanCancelWithoutBlockingTheUIActor() async throws {
        let saved = NetworkClient.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: configuration)
        NetworkClient.shared = NetworkClient(session: session)
        defer { NetworkClient.shared = saved; MockWebDAVURLProtocol.requestHandler = nil; session.invalidateAndCancel() }
        let started = expectation(description: "Category script started off the UI actor")
        MockWebDAVURLProtocol.requestHandler = { request in
            started.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("ready".utf8))
        }
        let source = BookSource(bookSourceUrl: "https://runtime.test", bookSourceName: "Categories",
                                exploreUrl: "@js:java.ajax('/signal');while(true){}")
        let task = Task { try await BookExploreService.shared.loadExploreCategories(source: source) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
        let normal = BookSource(bookSourceUrl: "https://runtime.test", bookSourceName: "Normal",
                                exploreUrl: #"[{"title":"One","url":"/one"}]"#)
        let categories = try await BookExploreService.shared.loadExploreCategories(source: normal)
        XCTAssertEqual(categories.first?.title, "One")
    }

    func testSourceEngineInterruptsRepeatedLoopsAndRecovers() throws {
        let engine = JSEngine()
        try engine.checkReady()
        engine.timeout = 0.005
        for _ in 0..<20 {
            XCTAssertNil(engine.eval(script: "while(true){}"))
            XCTAssertTrue(engine.didTimeOut)
            XCTAssertEqual(engine.eval(script: "2+3") as? Int, 5)
            XCTAssertNil(engine.lastScriptError)
        }
        XCTAssertEqual(engine.evalString("true"), "true")
        XCTAssertEqual(engine.renderTemplate("{{true}}"), "true")
    }

    func testReplacementLoopIsTerminatedAndFollowingRuleStillRuns() async {
        let processor = ContentProcessor()
        let bad = ReplaceRule(id: 1, name: "Loop", pattern: "a", replacement: "@js:while(true){}", timeoutMillisecond: 10)
        let good = ReplaceRule(id: 2, name: "Following", pattern: "a", replacement: "b", isRegex: false, order: 1)
        processor.rules = [bad, good]
        let disabled = expectation(description: "Loop rule disabled")
        processor.onRuleAutoDisabled = { rule in XCTAssertEqual(rule.id, bad.id); disabled.fulfill() }
        let context = ProcessContext(bookName: "Book", bookOrigin: "test", chapterTitle: "Title",
                                     style: ReadStyleConfig(), prefs: ReaderPrefs())
        let result = await processor.process(rawContent: "a", context: context)
        await fulfillment(of: [disabled], timeout: 2)
        XCTAssertTrue(result.bodyText.contains("b"))
        XCTAssertEqual(result.effectiveRules.map(\.id), [good.id])
    }

    func testCancelledPureJavaScriptHooksDoNotExhaustWorkerPool() async throws {
        let saved = NetworkClient.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: configuration)
        NetworkClient.shared = NetworkClient(session: session)
        defer { NetworkClient.shared = saved; MockWebDAVURLProtocol.requestHandler = nil; session.invalidateAndCancel() }
        let started = expectation(description: "Two hook workers reached JavaScript")
        started.expectedFulfillmentCount = 2
        MockWebDAVURLProtocol.requestHandler = { request in
            started.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("ready".utf8))
        }
        let source = BookSource(bookSourceUrl: "https://runtime.test", bookSourceName: "Cancellation",
                                ruleToc: TocRule(preUpdateJs: "java.ajax('/signal'); for(;;){}"))
        let book = Book(bookUrl: "https://runtime.test/book", name: "Book", author: "Author", origin: source.bookSourceUrl)
        let first = Task { try await SourcePreUpdateService().run(book: book, source: source) }
        let second = Task { try await SourcePreUpdateService().run(book: book, source: source) }
        await fulfillment(of: [started], timeout: 3)
        first.cancel(); second.cancel()
        _ = try? await first.value; _ = try? await second.value
        var normal = source
        normal.ruleToc?.preUpdateJs = "book.tocUrl='/fresh'"
        let normalSource = normal
        let ready = expectation(description: "Workers accept another hook after cancellation")
        let next = Task {
            let result = try await SourcePreUpdateService().run(book: book, source: normalSource)
            XCTAssertEqual(result.tocUrl, "/fresh")
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 3)
        next.cancel()
        _ = try? await next.value
    }
}

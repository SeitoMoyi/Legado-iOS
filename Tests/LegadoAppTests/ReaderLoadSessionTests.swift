import XCTest
import LegadoCore
@testable import LegadoApp

final class ReaderLoadSessionTests: XCTestCase {
    @MainActor
    func testSourceChangeInvalidatesOldRequestsWithoutClosingSession() async {
        let session = ReaderLoadSession()
        let oldStarted = expectation(description: "Old source request started")
        let oldFinished = expectation(description: "Old source result rejected")
        let newFinished = expectation(description: "Replacement source accepted")
        var continuation: CheckedContinuation<Void, Never>?
        var displayedSource = ""
        session.start("canvas-0") { ticket in
            await withCheckedContinuation { continuation = $0; oldStarted.fulfill() }
            if session.accepts(ticket) { displayedSource = "old" }
            oldFinished.fulfill()
        }
        await fulfillment(of: [oldStarted], timeout: 3)
        session.cancelPending()
        session.start("currentChapter") { ticket in
            if session.accepts(ticket) { displayedSource = "new" }
            newFinished.fulfill()
        }
        await fulfillment(of: [newFinished], timeout: 3)
        continuation?.resume()
        await fulfillment(of: [oldFinished], timeout: 3)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(displayedSource, "new")
        session.stop()
    }

    @MainActor
    func testExitCancelsFirstUncachedChapterAndAllowsFreshPresentation() async throws {
        let saved = NetworkClient.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderLoadingURLProtocol.self]
        let network = URLSession(configuration: configuration)
        NetworkClient.shared = NetworkClient(session: network)
        defer {
            network.invalidateAndCancel()
            NetworkClient.shared = saved
            ReaderLoadingURLProtocol.onStart = nil
            ReaderLoadingURLProtocol.onStop = nil
        }

        let started = expectation(description: "First uncached chapter request started")
        let cancelled = expectation(description: "Underlying request cancelled")
        ReaderLoadingURLProtocol.onStart = { request in
            if request.url?.path == "/slow" { started.fulfill() }
        }
        ReaderLoadingURLProtocol.onStop = { cancelled.fulfill() }
        let source = BookSource(bookSourceUrl: "https://reader.test", bookSourceName: "Reader test",
                                ruleContent: ContentRule(content: "$.body"))
        let bookURL = "https://reader.test/" + UUID().uuidString
        let chapter = BookChapter(bookUrl: bookURL, url: "https://reader.test/slow", title: "First", index: 0)
        defer { BookContentService.shared.clearCache(for: bookURL) }

        let session = ReaderLoadSession()
        let finished = expectation(description: "Cancelled load returned")
        var applied = false
        var prefetched = false
        session.start("currentChapter") { ticket in
            defer { finished.fulfill() }
            do {
                _ = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: source)
                guard session.accepts(ticket) else { return }
                applied = true
                session.start("prefetch") { _ in prefetched = true }
            } catch {
                // The reader ignores cancellation instead of presenting a load error.
                XCTAssertFalse(session.accepts(ticket))
            }
        }
        await fulfillment(of: [started], timeout: 3)
        session.stop()
        XCTAssertFalse(session.isActive)
        await fulfillment(of: [cancelled, finished], timeout: 3)
        XCTAssertFalse(applied)
        XCTAssertFalse(prefetched)

        // A new reader must not inherit the cancelled task/loading state.
        let reopened = ReaderLoadSession()
        var retry = chapter
        retry.url = "https://reader.test/fast"
        let content = try await reopened.value("canvas-0") {
            try await BookContentService.shared.fetchChapterContent(chapter: retry, source: source)
        }
        XCTAssertEqual(content, "Readable body")
        reopened.stop()
    }

    @MainActor
    func testLateResultCannotUpdateClosedReaderOrLaunchMoreWork() async {
        let session = ReaderLoadSession()
        let started = expectation(description: "Uncooperative source started")
        let finished = expectation(description: "Late source returned")
        var continuation: CheckedContinuation<Void, Never>?
        var applied = false
        var launchedAfterExit = false
        session.start("currentChapter") { ticket in
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
            if session.accepts(ticket) { applied = true }
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        session.stop()
        session.start("latePrefetch") { _ in launchedAfterExit = true }
        continuation?.resume()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertFalse(applied)
        XCTAssertFalse(launchedAfterExit)
    }

    @MainActor
    func testSupersededChapterCannotOverwriteNewerLoad() async {
        let session = ReaderLoadSession()
        let oldStarted = expectation(description: "Old request started")
        let newStarted = expectation(description: "New request started")
        let oldFinished = expectation(description: "Old request finished late")
        let newFinished = expectation(description: "New request accepted")
        var oldContinuation: CheckedContinuation<Void, Never>?
        var newContinuation: CheckedContinuation<Void, Never>?
        var displayedChapter = ""
        session.start("currentChapter") { ticket in
            await withCheckedContinuation { oldContinuation = $0; oldStarted.fulfill() }
            if session.accepts(ticket) { displayedChapter = "old" }
            oldFinished.fulfill()
        }
        await fulfillment(of: [oldStarted], timeout: 3)
        session.start("currentChapter") { ticket in
            await withCheckedContinuation { newContinuation = $0; newStarted.fulfill() }
            if session.accepts(ticket) { displayedChapter = "new" }
            newFinished.fulfill()
        }
        await fulfillment(of: [newStarted], timeout: 3)
        oldContinuation?.resume()
        await fulfillment(of: [oldFinished], timeout: 3)
        XCTAssertEqual(displayedChapter, "")
        newContinuation?.resume()
        await fulfillment(of: [newFinished], timeout: 3)
        XCTAssertEqual(displayedChapter, "new")
        session.stop()
    }

    @MainActor
    func testExitCancelsScrollingRequestAndRemainingPrefetchQueue() async {
        let saved = NetworkClient.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderLoadingURLProtocol.self]
        let network = URLSession(configuration: configuration)
        NetworkClient.shared = NetworkClient(session: network)
        defer {
            network.invalidateAndCancel()
            NetworkClient.shared = saved
            ReaderLoadingURLProtocol.onStart = nil
            ReaderLoadingURLProtocol.onStop = nil
        }
        let started = expectation(description: "Scroll and prefetch both started")
        started.expectedFulfillmentCount = 2
        let stopped = expectation(description: "Scroll and prefetch both cancelled")
        stopped.expectedFulfillmentCount = 2
        let finished = expectation(description: "Prefetch stopped")
        let unexpected = expectation(description: "Remaining chapter must not be fetched")
        unexpected.isInverted = true
        ReaderLoadingURLProtocol.onStart = { request in
            if request.url?.path == "/slow" { started.fulfill() } else { unexpected.fulfill() }
        }
        ReaderLoadingURLProtocol.onStop = { stopped.fulfill() }
        let source = BookSource(bookSourceUrl: "https://reader.test", bookSourceName: "Reader test",
                                ruleContent: ContentRule(content: "$.body"))
        let bookURL = "https://reader.test/" + UUID().uuidString
        let chapters = ["fast", "slow", "fast"].enumerated().map {
            BookChapter(bookUrl: bookURL, url: "https://reader.test/" + $0.element, title: "Chapter", index: $0.offset)
        }
        defer { BookContentService.shared.clearCache(for: bookURL) }
        let session = ReaderLoadSession()
        session.start("diskPrefetch") { _ in
            await BookContentService.shared.preDownloadChapters(around: 0, chapters: chapters, source: source)
            finished.fulfill()
        }
        let scroll = Task {
            try await session.value("canvas-1") {
                try await BookContentService.shared.fetchChapterContent(chapter: chapters[1], source: source)
            }
        }
        await fulfillment(of: [started], timeout: 3)
        session.stop()
        await fulfillment(of: [stopped, finished], timeout: 3)
        do {
            _ = try await scroll.value
            XCTFail("Closed reader must not receive chapter text")
        } catch { }
        await fulfillment(of: [unexpected], timeout: 0.2)
    }
}

private final class ReaderLoadingURLProtocol: URLProtocol {
    static var onStart: ((URLRequest) -> Void)?
    static var onStop: (() -> Void)?
    private var cancellationCallback: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/slow" { cancellationCallback = Self.onStop }
        Self.onStart?(request)
        guard request.url?.path != "/slow" else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"body":"Readable body"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        cancellationCallback?()
        cancellationCallback = nil
    }
}

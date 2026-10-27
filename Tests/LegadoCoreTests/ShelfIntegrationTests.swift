import XCTest
import ZIPFoundation
@testable import LegadoCore

final class ShelfIntegrationTests: XCTestCase {
    func testBookListURLDownloadValidatesStatusBeforePreview() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); MockWebDAVURLProtocol.requestHandler = nil }
        MockWebDAVURLProtocol.requestHandler = { request in
            let status = request.url?.path == "/missing" ? 404 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(#"[{"name":"Book","author":"Author"}]"#.utf8))
        }
        let values = try await ShelfImportService.load("https://list.test/books.json", session: session)
        XCTAssertEqual(values.map(\.name), ["Book"])
        do { _ = try await ShelfImportService.load("https://list.test/missing", session: session); XCTFail("Expected HTTP failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("404")) }
    }

    func testBookListUsesNativeIdentityFieldsAndDeduplicates() throws {
        let data = Data(#"[{"name":" Book ","author":"Author","intro":"Info","bookUrl":"file:///other-device/private","durChapterIndex":99},{"name":"Book","author":"Author"},{"name":""}]"#.utf8)
        let list = try ShelfImportService.parse(data)
        XCTAssertEqual(list, [ShelfBookInfo(name: "Book", author: "Author", intro: "Info")])
        XCTAssertThrowsError(try ShelfImportService.parse(Data("{}".utf8)))
        XCTAssertThrowsError(try ShelfImportService.parse(Data("[]".utf8)))
    }

    func testBookListSearchRequiresExactAuthorAndSkipsDisabledSources() async throws {
        let original = NetworkClient.shared
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: config)
        NetworkClient.shared = NetworkClient(session: session)
        defer { NetworkClient.shared = original; session.invalidateAndCancel(); MockWebDAVURLProtocol.requestHandler = nil }
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertNotEqual(request.url?.host, "disabled.test")
            let body = #"[{"name":"Book","author":"Author translator","url":"/wrong"},{"name":"Book","author":"Author","url":"/correct"}]"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        var source = BookSource(bookSourceUrl: "https://shelf-import.test", bookSourceName: "Source")
        source.searchUrl = "/search?key={{key}}"; source.ruleSearch = SearchRule(bookList: "$[*]", name: "$.name", author: "$.author", bookUrl: "$.url")
        var disabled = source; disabled.bookSourceUrl = "https://disabled.test"; disabled.enabled = false
        let book = try await ShelfImportService.find(ShelfBookInfo(name: "Book", author: "Author"), sources: [disabled, source])
        XCTAssertEqual(book?.bookUrl, "https://shelf-import.test/correct")
        XCTAssertEqual(book?.origin, source.bookSourceUrl)
        let missing = try await ShelfImportService.find(ShelfBookInfo(name: "Book", author: "Other"), sources: [source])
        XCTAssertNil(missing)
    }

    func testCancellingBookListSearchCancelsTheUnderlyingRequest() async throws {
        let original = NetworkClient.shared
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ShelfSuspendedURLProtocol.self]
        let session = URLSession(configuration: config)
        NetworkClient.shared = NetworkClient(session: session)
        let started = expectation(description: "Request started")
        let stopped = expectation(description: "Request cancelled")
        ShelfSuspendedURLProtocol.onStart = { started.fulfill() }; ShelfSuspendedURLProtocol.onStop = { stopped.fulfill() }
        defer { NetworkClient.shared = original; session.invalidateAndCancel(); ShelfSuspendedURLProtocol.onStart = nil; ShelfSuspendedURLProtocol.onStop = nil }
        var source = BookSource(bookSourceUrl: "https://suspended-shelf.test", bookSourceName: "Slow")
        source.searchUrl = "/search"; source.ruleSearch = SearchRule(bookList: "$[*]")
        let sources = [source]
        let task = Task { try await ShelfImportService.find(ShelfBookInfo(name: "Book"), sources: sources) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    }

    func testAbandoningChangeSourceStreamCancelsItsWorkers() async throws {
        let original = NetworkClient.shared
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ShelfSuspendedURLProtocol.self]
        let session = URLSession(configuration: config); NetworkClient.shared = NetworkClient(session: session)
        let started = expectation(description: "Change-source started"), stopped = expectation(description: "Change-source stopped")
        ShelfSuspendedURLProtocol.onStart = { started.fulfill() }; ShelfSuspendedURLProtocol.onStop = { stopped.fulfill() }
        defer { NetworkClient.shared = original; session.invalidateAndCancel(); ShelfSuspendedURLProtocol.onStart = nil; ShelfSuspendedURLProtocol.onStop = nil }
        var source = BookSource(bookSourceUrl: "https://suspended-change.test", bookSourceName: "Slow"); source.searchUrl = "/search"
        let book = Book(bookUrl: "book", name: "Book", author: "Author")
        let sources = [source]
        let consumer = Task {
            for await _ in ChangeSourceService.shared.candidates(book: book, sources: sources, checkAuthor: true) { }
        }
        await fulfillment(of: [started], timeout: 2)
        consumer.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        await consumer.value
    }

    func testLogsAreBoundedThreadSafeAndRedactCommonCredentials() {
        let store = AppLogStore()
        DispatchQueue.concurrentPerform(iterations: 150) { index in store.record("Test", "Entry \(index)") }
        XCTAssertEqual(store.snapshot().count, 100)
        store.record("Test", "Authorization: Bearer secret\nhttps://example.test/a?token=hidden&other=ok\n{\"password\":\"private\"}")
        let message = store.snapshot()[0].message
        XCTAssertFalse(message.contains("secret")); XCTAssertFalse(message.contains("hidden")); XCTAssertFalse(message.contains("private"))
        XCTAssertTrue(message.contains("other=ok"))
        store.clear(); XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testEPUBEmbedsDeduplicatedImagesAndReportsMissingResourcesAndChapters() throws {
        let book = Book(bookUrl: "https://export-shelf.test/book", name: "Images", author: "Author")
        let chapters = (0..<3).map { BookChapter(bookUrl: book.bookUrl, url: "c\($0)", title: "Chapter \($0)", index: $0) }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=")!
        let body = "First\n[image:https://image.test/a]\n[image:https://image.test/a]\n[image:https://image.test/missing]"
        let report = try BookExportService.exportEPUBReport(book: book, chapters: chapters, contentProvider: { $0 == 0 ? body : nil }, imageProvider: { $0.hasSuffix("/a") ? image : nil })
        defer { try? FileManager.default.removeItem(at: report.url.deletingLastPathComponent()) }
        XCTAssertEqual(report.includedChapters, 1)
        XCTAssertEqual(report.missingChapters.map(\.index), [1, 2])
        XCTAssertEqual(report.missingImages, ["https://image.test/missing"])
        let archive = try Archive(url: report.url, accessMode: .read)
        XCTAssertEqual(archive.filter { $0.path.hasPrefix("OEBPS/images/") }.count, 1)
        func read(_ name: String) throws -> Data {
            var result = Data(); _ = try archive.extract(try XCTUnwrap(archive[name])) { result.append($0) }; return result
        }
        XCTAssertEqual(try read("OEBPS/images/i0.png"), image)
        let chapter = String(decoding: try read("OEBPS/chapter_0001.xhtml"), as: UTF8.self)
        XCTAssertTrue(chapter.contains("src=\"images/i0.png\"")); XCTAssertTrue(chapter.contains("未导出图片"))
        XCTAssertFalse(chapter.contains("[image:"))
        let opf = String(decoding: try read("OEBPS/content.opf"), as: UTF8.self)
        XCTAssertTrue(opf.contains("media-type=\"image/png\""))
    }

    func testTXTReportAndSameNameExportsDoNotOverwriteFiles() throws {
        let book = Book(bookUrl: "book", name: "Same", author: "Author")
        let chapters = [BookChapter(bookUrl: "book", url: "c", title: "One", index: 0), BookChapter(bookUrl: "book", url: "d", title: "Two", index: 1)]
        let first = try BookExportService.exportTXTReport(book: book, chapters: chapters, contentProvider: { $0 == 0 ? "First body" : nil })
        let second = try BookExportService.exportTXTReport(book: book, chapters: chapters, contentProvider: { _ in "Second body" })
        defer { try? FileManager.default.removeItem(at: first.url.deletingLastPathComponent()); try? FileManager.default.removeItem(at: second.url.deletingLastPathComponent()) }
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(first.missingChapters.map(\.title), ["Two"])
        XCTAssertTrue(try String(contentsOf: first.url).contains("First body"))
        XCTAssertTrue(second.missingChapters.isEmpty)
    }

    func testRemoteImageMarkersCannotReadLocalFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([137, 80, 78, 71, 13, 10, 26, 10]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let book = Book(bookUrl: "https://remote.test", name: "Remote", author: "Author", origin: "https://remote.test")
        XCTAssertNil(BookExportService.cachedImage(book: book, reference: file.absoluteString))
    }
}

private final class ShelfSuspendedURLProtocol: URLProtocol {
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?() }
    override func stopLoading() { Self.onStop?() }
}

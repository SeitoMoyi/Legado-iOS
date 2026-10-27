import XCTest
import ZIPFoundation
@testable import LegadoCore

final class ConsolidationTests: XCTestCase {
    func testUnknownAndroidLongBitmapsKeepAll64BitsDuringBackupRoundTrip() throws {
        let data = Data(#"{"bookUrl":"book","name":"Book","author":"Author","readConfig":{"delTag":9223372036854775807,"negative":-9223372036854775808}}"#.utf8)
        let book = try XCTUnwrap(Book.decodeWithExtras(from: data))
        XCTAssertEqual(book.readerSetting("delTag"), .int(Int64.max))
        XCTAssertEqual(book.readerSetting("negative"), .int(Int64.min))
        let restored = try XCTUnwrap(Book.decodeWithExtras(from: JSONEncoder().encode(book)))
        XCTAssertEqual(restored.readerSetting("delTag"), .int(Int64.max))
        XCTAssertEqual(restored.readerSetting("negative"), .int(Int64.min))
    }

    func testRefreshedSessionHeaderDrivesLoginStatusAndLogoutAvailability() {
        let url = "https://login-status.test/" + UUID().uuidString
        defer { SourceSessionStore.save(header: nil, for: url) }
        let source = BookSource(bookSourceUrl: url, bookSourceName: "Source")
        XCTAssertFalse(source.isLogged)
        SourceSessionStore.save(header: #"{"Authorization":"test"}"#, for: url)
        XCTAssertTrue(source.isLogged)
        SourceSessionStore.save(header: "", for: url)
        XCTAssertFalse(source.isLogged)
    }

    func testWebDAVListingsRejectForeignOriginsAndPorts() {
        let base = URL(string: "https://dav.test/legado/")!
        let names = ["https://evil.test/backup2026-10-27.zip", "https://dav.test:444/backup2026-10-27.zip", "/legado/backup2026-10-27.zip"]
        let xml = "<multistatus>" + names.map { "<response><href>\($0)</href></response>" }.joined() + "</multistatus>"
        let backups = WebDAVService().parseBackupsFromPropfindXML(xml, baseURL: base)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.url.host, "dav.test")
        XCTAssertEqual(WebDAVService.parseDirectoryEntries(from: xml, baseURL: base).count, 1)
        XCTAssertTrue(WebDAVService.isSameOrigin(URL(string: "https://dav.test:443/a")!, base))
        XCTAssertFalse(WebDAVService.isSameOrigin(URL(string: "http://dav.test/a")!, base))
        XCTAssertFalse(WebDAVService.isSameOrigin(URL(string: "https://user:pass@dav.test/a")!, base))
    }

    func testWebDAVForeignDownloadIsRejectedBeforeSendingCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); MockWebDAVURLProtocol.requestHandler = nil }
        MockWebDAVURLProtocol.requestHandler = { request in XCTFail("No foreign request should be sent"); throw URLError(.badURL) }
        do {
            _ = try await WebDAVService(session: session).downloadFileData(url: URL(string: "https://evil.test/book.txt")!, config: WebDAVConfig(url: "https://dav.test", username: "user", password: "secret"))
            XCTFail("Expected origin rejection")
        } catch { XCTAssertTrue(error is WebDAVError) }
    }

    func testWebDAVRedirectGuardRetainsAuthOnlyForConfiguredOrigin() {
        let config = WebDAVConfig(url: "https://dav.test", username: "user", password: "secret")
        let guardDelegate = WebDAVRedirectGuard(config: config)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://dav.test/")!)
        let response = HTTPURLResponse(url: URL(string: "https://dav.test/")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://evil.test/")!)) { XCTAssertNil($0) }
        guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://dav.test/other/")!)) {
            XCTAssertEqual($0?.value(forHTTPHeaderField: "Authorization"), config.basicAuthHeader)
        }
    }

    func testMalformedKnownBackupMembersFailInsteadOfDroppingRows() throws {
        for (name, body) in [("bookSource.json", "[3]"), ("bookshelf.json", "not json"), ("replaceRule.json", "{}"), ("rssSources.json", "[false]")] {
            let archive = try Archive(accessMode: .create)
            let data = Data(body.utf8)
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { offset, size in data.subdata(in: Int(offset)..<Int(offset) + size) }
            XCTAssertThrowsError(try WebDAVService().parseArchivePayload(archive), name)
        }
    }

    func testPartialReaderPreferencesKeepDefaultsAndUnknownFutureKeys() throws {
        let settings = try JSONDecoder().decode(ReaderBackupSettings.self, from: Data(#"{"selectedStyle":1,"prefs":{"ttsTimer":25,"future":{"flag":true}}}"#.utf8))
        XCTAssertEqual(settings.prefs.ttsTimer, 25)
        XCTAssertEqual(settings.prefs.clickActions, ReaderPrefs.defaultClickActions)
        let restored = try JSONDecoder().decode(ReaderBackupSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.prefs.extra["future"], .object(["flag": .bool(true)]))
    }

    func testRSSBindingExposesNativeFieldShapesAndScopedSourceValues() throws {
        let key = "https://rss-object.test/" + UUID().uuidString
        let source = RssSource(sourceUrl: key, sourceName: "RSS", articleStyle: 2, ruleContent: "p@html")
        let engine = JSEngine(rssSource: source)
        XCTAssertEqual(engine.evalString("source.ruleContent"), "p@html")
        XCTAssertEqual(engine.evalString("source.getTag()"), "RSS")
        XCTAssertEqual(engine.evalString("source.getKey()"), key)
        XCTAssertEqual(engine.evalString("source.articleStyle"), "2")
        _ = try engine.evalChecked(script: "source.put('probe','value')", stage: "test")
        XCTAssertEqual(JSEngine(rssSource: source).evalString("source.get('probe')"), "value")
        let other = RssSource(sourceUrl: key + "/other", sourceName: "Other")
        XCTAssertEqual(JSEngine(rssSource: other).evalString("source.get('probe')"), "")
        _ = engine.eval(script: "source.put('probe','')")
    }

    func testRSSArticleVariablesAreIsolatedAndRestoredForContentRequests() async throws {
        var source = RssSource(sourceUrl: "https://rss-variable.test", sourceName: "RSS", header: "@js:JSON.stringify({'X-Article':java.get('previous')})", ruleArticles: "$[*]", ruleTitle: "@js:var old=java.get('previous')||'';java.put('previous',result.title);result.title+old", ruleLink: "$.link", ruleContent: "p@text")
        source.loadWithBaseUrl = true
        let articles = try RssService.shared.parseArticlesFromContent(#"[{"title":"A","link":"/a"},{"title":"B","link":"/b"}]"#, source: source, categoryUrl: source.sourceUrl)
        XCTAssertEqual(articles.map(\.title), ["A", "B"])
        XCTAssertNotEqual(articles[0].variable, articles[1].variable)
        let old = NetworkClient.shared
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: config); NetworkClient.shared = NetworkClient(session: session)
        defer { NetworkClient.shared = old; session.invalidateAndCancel(); MockWebDAVURLProtocol.requestHandler = nil }
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Article"), "A")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("<p>Body</p>".utf8))
        }
        let content = try await RssService.shared.fetchArticleContent(article: articles[0], source: source)
        XCTAssertEqual(content, "Body")
    }

    func testLoginRetainsInfoUpdatedByTheSourceScript() async throws {
        var source = BookSource(bookSourceUrl: "https://login-info.test", bookSourceName: "Login")
        source.loginUrl = #"@js:function login(){source.putLoginInfo('{"account":"updated"}');source.putLoginHeader('{"X-Session":"ok"}')}"#
        let result = try await SourceLoginService.execute(source: source, credentials: ["account": "old"])
        XCTAssertEqual(result.info, #"{"account":"updated"}"#)
    }

    func testLongExportNamesKeepTheirFormatExtension() {
        let filename = BookExportService.sanitizeFileName(String(repeating: "长", count: 120) + ".epub")
        XCTAssertTrue(filename.hasSuffix(".epub"))
        XCTAssertEqual(filename.count, 80)
    }
}

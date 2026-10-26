import XCTest
@testable import LegadoCore

final class SourceFlowCompatibilityTests: XCTestCase {
    private var savedClient: NetworkClient!
    private var session: URLSession!
    private let base = "https://source-flow.test"
    override func setUp() {
        savedClient = NetworkClient.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        session = URLSession(configuration: configuration)
        NetworkClient.shared = NetworkClient(session: session)
        SourceSessionStore.save(header: nil, for: base)
    }
    override func tearDown() {
        SourceSessionStore.save(header: nil, for: base)
        NetworkClient.shared = savedClient
        MockWebDAVURLProtocol.requestHandler = nil
        session.invalidateAndCancel()
    }

    func testResponseCheckPassThroughAndReplacementRetainsFinalURLAndHeader() throws {
        let incoming = NetworkResponse(statusCode: 403, bodyString: "login", data: Data("login".utf8), headers: [:], url: URL(string: base + "/redirect"))
        var source = BookSource(bookSourceUrl: base, bookSourceName: "Source")
        source.loginCheckJs = "result"
        let pass = try JSEngine(bookSource: source).checkedResponse(incoming, requestedURL: URL(string: base)!)
        XCTAssertEqual(pass.bodyString, "login")
        XCTAssertEqual(pass.url?.path, "/redirect")
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/retry")
            return (HTTPURLResponse(url: URL(string: self.base + "/final")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("replacement".utf8))
        }
        source.loginCheckJs = "source.putLoginHeader('{\"X-Session\":\"fresh\"}'); java.connect(source.bookSourceUrl+'/retry')"
        let replaced = try JSEngine(bookSource: source).checkedResponse(incoming, requestedURL: URL(string: base)!)
        XCTAssertEqual(replaced.bodyString, "replacement")
        XCTAssertEqual(replaced.statusCode, 200)
        XCTAssertEqual(replaced.url?.path, "/final")
        let header = try XCTUnwrap(JSEngine.resolvedSourceHeader(source))
        XCTAssertTrue(header.contains("fresh"))
    }

    func testResponseCheckRejectsBooleanAndInterruptsInfiniteScript() throws {
        var source = BookSource(bookSourceUrl: base, bookSourceName: "Source")
        let response = NetworkResponse(statusCode: 200, bodyString: "body", data: Data(), headers: [:])
        source.loginCheckJs = "true"
        XCTAssertThrowsError(try JSEngine(bookSource: source).checkedResponse(response, requestedURL: URL(string: base)!))
        source.loginCheckJs = "while(true){}"
        let engine = JSEngine(bookSource: source); engine.timeout = 0.02
        XCTAssertThrowsError(try engine.checkedResponse(response, requestedURL: URL(string: base)!))
    }

    func testSearchAppliesResponseCheckBeforeStatusAndExtraction() async throws {
        MockWebDAVURLProtocol.requestHandler = { request in
            let body = request.url?.path == "/replacement" ? #"[{"name":"Recovered","url":"/book"}]"# : "login"
            return (HTTPURLResponse(url: request.url!, statusCode: body == "login" ? 403 : 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        var source = BookSource(bookSourceUrl: base, bookSourceName: "Source")
        source.searchUrl = "/search"
        source.loginCheckJs = "java.connect(source.bookSourceUrl+'/replacement')"
        source.ruleSearch = SearchRule(bookList: "$[*]", name: "$.name", bookUrl: "$.url")
        let result = try await BookSearchService.shared.search(source: source, key: "book")
        XCTAssertEqual(result.first?.name, "Recovered")
        XCTAssertEqual(result.first?.bookUrl, base + "/book")
    }

    func testNativeLoginFunctionAndButtonActionReceiveCredentials() async throws {
        var source = BookSource(bookSourceUrl: base, bookSourceName: "Source")
        source.loginUrl = #"@js:function login(){source.putLoginHeader(JSON.stringify({'X-User':source.getLoginInfoMap().get('account')}))} function code(v){return 'sent:'+v.account}"#
        let login = try await SourceLoginService.execute(source: source, credentials: ["account": "reader"])
        XCTAssertTrue(login.header?.contains("reader") == true)
        let action = try await SourceLoginService.execute(source: source, credentials: ["account": "reader"], action: "code(result)")
        XCTAssertEqual(action.message, "sent:reader")
        XCTAssertNil(action.header)
        XCTAssertEqual(SourceLoginRow.parse(#"[{"name":"Send code","type":"button","action":"code(result)"}]"#).first?.action, "code(result)")
    }

    func testRSSCategoriesUseLibraryIdentityVariablesAndNativeSeparators() async throws {
        var source = RssSource(sourceUrl: base, sourceName: "RSS")
        source.variable = "news"
        source.extra["jsLib"] = .string("function section(){return source.sourceName+'::/'+source.getVariable()+'&&Other::/other'}")
        source.sortUrl = "@js:section()"
        let categories = try await RssService.shared.loadCategories(source: source)
        XCTAssertEqual(categories.map(\.title), ["RSS", "Other"])
        XCTAssertEqual(categories.map(\.url), [base + "/news", base + "/other"])
        source.sortUrl = #"[{"title":"JSON extension","url":"/json"}]"#
        let jsonCategories = try await RssService.shared.loadCategories(source: source)
        XCTAssertEqual(jsonCategories.first?.url, base + "/json")
    }

    func testRSSRulesShareSourceLibraryAndPreserveReverseAndHTMLDescription() throws {
        var source = RssSource(sourceUrl: base, sourceName: "RSS", ruleArticles: "-$.items", ruleTitle: "$.title@js:decorate(result)", ruleDescription: "$.description", ruleLink: "$.link")
        source.extra["jsLib"] = .string("function decorate(v){return source.sourceName+':'+v}")
        let articles = try RssService.shared.parseArticlesFromContent(#"{"items":[{"title":"A","link":"/a","description":"<p>A<img src='/i'></p>"},{"title":"B","link":"/b"}]}"#, source: source, categoryUrl: base)
        XCTAssertEqual(articles.map(\.title), ["RSS:B", "RSS:A"])
        XCTAssertTrue(articles.last?.content?.contains("<img") == true)
    }

    func testRSSRequestEvaluatesPageTemplateHeadersAndPageSentinel() async throws {
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-RSS"), "token")
            XCTAssertEqual(request.url?.query, "page=2")
            let body = #"[{"title":"Two","link":"/two"}]"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        var source = RssSource(sourceUrl: base, sourceName: "RSS", header: "@js:JSON.stringify({'X-RSS':source.getVariable()})", ruleArticles: "$[*]", ruleNextPage: "PAGE", ruleTitle: "$.title", ruleLink: "$.link")
        source.variable = "token"
        let result = try await RssService.shared.fetchArticlePage(source: source, pageUrl: base + "/feed?page={{page}}", page: 2)
        XCTAssertEqual(result.articles.first?.title, "Two")
        XCTAssertEqual(result.nextPageUrl, base + "/feed?page=2")
    }

    func testRSSDocumentHonorsCustomStyleAndPreservesMarkupAndPlainText() {
        let source = RssSource(style: "body{color:red}")
        let html = RssDocument.html(content: "<p>Hello<img src='/a'></p>", source: source)
        XCTAssertTrue(html.contains("<img src='/a'>"))
        XCTAssertTrue(html.contains("body{color:red}"))
        XCTAssertFalse(html.contains("font:17px"))
        let plain = RssDocument.html(content: "1 < 2\nA & B", source: RssSource())
        XCTAssertTrue(plain.contains("1 &lt; 2<br>A &amp; B"))
    }

    func testRuleLinksResolveDeepLinksAndRejectLocalOrCredentialURLs() async throws {
        let remote = base + "/rules.json?q=a%20b"
        var components = URLComponents(string: "legado://bookSource/importOnline")!
        components.queryItems = [URLQueryItem(name: "src", value: remote)]
        XCTAssertEqual(RuleLinkService.resolve(components.string!)?.absoluteString, remote)
        XCTAssertEqual(RuleLinkService.resolve(remote)?.absoluteString, remote)
        XCTAssertNil(RuleLinkService.resolve("legado://import?src=file:///tmp/private"))
        XCTAssertNil(RuleLinkService.resolve("https://user:pass@source-flow.test"))
        MockWebDAVURLProtocol.requestHandler = { request in
            let data = Data("\u{FEFF}{\"sourceName\":\"Feed\",\"sourceUrl\":\"https://feed.test\"}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let json = try await RuleLinkService.fetch(remote, session: session)
        XCTAssertEqual(ScanPayload.detect(json), .rssSources(json: json))
    }
}

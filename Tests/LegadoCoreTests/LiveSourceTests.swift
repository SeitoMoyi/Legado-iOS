import XCTest
import Foundation
#if canImport(LegadoCore)
@testable import LegadoCore
#endif

/// Live-source smoke tests.
///
/// These hit real book sources (`m.suixkan.com` and the 机翻机器人 reverse proxy at
/// `book.xkvi.top`, listed at `https://list.xkvi.top/legado/booksource.json`) and exist to
/// check the rule engine against sites that actually change. They are **not** a release gate:
/// CI runs `swift test --skip LiveSourceTests`, and even a local run degrades to a skip
/// instead of a failure whenever a host is down, slow, or the machine is offline — so
/// "the site is having a day off" can never look like "the parser is broken".
final class LiveSourceTests: XCTestCase {

    /// The community-maintained source list (机翻机器人 = 国内反代 of n.novelia.cc).
    static let xkviListUrl = "https://list.xkvi.top/legado/booksource.json"

    /// GETs each URL with a short timeout. Any HTTP response counts as reachable (a 404 or 405
    /// still proves the host answers); only a transport failure skips.
    private func requireReachable(_ urls: [String],
                                  file: StaticString = #filePath, line: UInt = #line) async throws {
        for raw in urls {
            guard let url = URL(string: raw) else {
                throw XCTSkip("无法解析测试地址：\(raw)", file: file, line: line)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                throw XCTSkip("\(url.host ?? raw) 不可达（\(error.localizedDescription)），跳过联网用例",
                              file: file, line: line)
            }
        }
    }

    /// Fetches and decodes the xkvi source list. Skips (rather than fails) when offline.
    private func loadXkviSources(file: StaticString = #filePath, line: UInt = #line) async throws -> [BookSource] {
        try await requireReachable([Self.xkviListUrl], file: file, line: line)
        guard let url = URL(string: Self.xkviListUrl) else {
            throw XCTSkip("无法解析书源列表地址", file: file, line: line)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let sources = BookSource.decodeListWithExtras(from: data) ?? []
        guard !sources.isEmpty else {
            throw XCTSkip("书源列表为空或无法解析", file: file, line: line)
        }
        return sources
    }

    func testSearchWithLiveSources() async throws {
        let jsonStr = """
        {
            "bookSourceName": "阅友小说",
            "bookSourceUrl": "http://m.suixkan.com",
            "bookSourceGroup": "通用",
            "enabled": true,
            "searchUrl": "http://m.suixkan.com/api/book/search?keyword={{key}}&page={{page}}",
            "ruleSearch": {
              "bookList": "$.data.list",
              "name": "$.bookName",
              "author": "$.authorName",
              "bookUrl": "http://m.suixkan.com/c/{{$.id}}.html",
              "coverUrl": "$.bookPic",
              "intro": "$.intro",
              "lastChapter": "$.latestChapterName",
              "wordCount": "$.words"
            }
        }
        """
        let source = try JSONDecoder().decode(BookSource.self, from: jsonStr.data(using: .utf8)!)
        try await requireReachable([source.bookSourceUrl])
        let books = try await BookSearchService.shared.search(source: source, key: "斗破苍穹")
        print("Search results count: \(books.count)")
        for b in books.prefix(3) {
            print("Found book: \(b.name) by \(b.author) -> \(b.bookUrl)")
        }
        XCTAssertFalse(books.isEmpty, "Should find books for 斗破苍穹")
    }

    // MARK: - xkvi (n.novelia.cc 国内反代) 书源可用性

    /// 书源列表 URL 可用性 + 结构校验：能取回、能解析、必填规则字段齐全、`jsLib` 等未建模字段经 #15 透传保留。
    func testXkviSourceListAvailability() async throws {
        let start = Date()
        let sources = try await loadXkviSources()
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("书源列表拉取成功：\(sources.count) 个源，耗时 \(ms)ms")

        guard let robot = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else {
            XCTFail("列表中应包含 book.xkvi.top 的机翻机器人源")
            return
        }
        XCTAssertEqual(robot.bookSourceName, "机翻机器人")
        XCTAssertFalse(robot.searchUrl?.isEmpty ?? true, "searchUrl 不能为空")
        XCTAssertFalse(robot.ruleSearch?.bookList?.isEmpty ?? true, "ruleSearch.bookList 不能为空")
        XCTAssertFalse(robot.ruleBookInfo?.name?.isEmpty ?? true, "ruleBookInfo.name 不能为空")
        XCTAssertFalse(robot.ruleToc?.chapterList?.isEmpty ?? true, "ruleToc.chapterList 不能为空")
        XCTAssertFalse(robot.ruleContent?.content?.isEmpty ?? true, "ruleContent.content 不能为空")
        // Plan §二 #15: jsLib / enabledCookieJar 等 Android 字段导入后必须原样保留
        XCTAssertFalse(robot.extra.isEmpty, "未建模字段应保留在 extra 中")
        XCTAssertNotNil(robot.extra["jsLib"])
        print("extra keys: \(robot.extra.keys.sorted())")

        // 反代 API 可用性：用已知有效的小说详情端点探测（须携带书源 header JS 求值出的共享 AccessToken Cookie）。
        // 站点根路径对源功能无关；API 对无 Cookie 请求一律 502。
        try await requireReachable([robot.bookSourceUrl])
        let probeUrl = "\(robot.bookSourceUrl)/api/novel/syosetu/n4197mn"
        var request = URLRequest(url: URL(string: probeUrl)!)
        request.timeoutInterval = 15
        if let cookie = Self.resolvedCookie(source: robot) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            print("已携带书源 Cookie：\(cookie.prefix(60))...")
        }
        let (resp, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("API 探测 \(probeUrl) → HTTP \(status), \(resp.count) bytes")
        XCTAssertTrue((200...299).contains(status), "携带书源 Cookie 后小说详情 API 应可访问（实际 HTTP \(status)）")
    }

    /// Evaluates the source's `header` JS (same path as `BookContentService`) to extract the
    /// `Cookie` line — book.xkvi.top rejects cookie-less API requests with 502.
    private static func resolvedCookie(source: BookSource) -> String? {
        guard let h = source.header ?? source.loginHeader, !h.isEmpty else { return nil }
        var script = h
        if h.contains("<js>") {
            guard let start = h.range(of: "<js>")?.upperBound,
                  let end = h.range(of: "</js>")?.lowerBound else { return nil }
            script = String(h[start..<end])
        } else if h.hasPrefix("@js:") {
            script = String(h.dropFirst(4))
        } else {
            return nil
        }
        let engine = JSEngine(bookSource: source, baseUrl: source.bookSourceUrl)
        guard let evaluated = engine.context.evaluateScript(script)?.toString(),
              !evaluated.isEmpty, evaluated != "undefined",
              let data = evaluated.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["Cookie"] as? String
    }

    /// 原始探测搜索 API 的 HTTP 状态码（携带书源 resolved header，与 App 实际请求一致）：
    /// 502/401 表示需要有效登录 Token。
    private func searchApiStatus(_ source: BookSource, keyword: String) async -> Int {
        guard let parsed = NetworkClient.parseLegadoUrl(
            "\(source.bookSourceUrl)/api/novel?page=0&pageSize=20&query=\(keyword)&provider=kakuyomu,syosetu,novelup,hameln,pixiv,alphapolis&type=0&level=1&translate=0&sort=0",
            defaultHeader: JSEngine.resolvedSourceHeader(source)) else { return 0 }
        do {
            let response = try await NetworkClient.shared.request(parsed: parsed)
            return response.statusCode
        } catch {
            return 0
        }
    }

    /// 探索分类 (<js> exploreUrl) 解析 + 搜索 API 全链路（未登录 level=1）。
    func testXkviJifanSearchFlow() async throws {
        let sources = try await loadXkviSources()
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else {
            XCTFail("机翻机器人源不存在"); return
        }

        // 1. 探索分类（<js> 动态脚本）
        let categories = BookExploreService.shared.parseExploreCategories(source: source)
        print("探索分类数量: \(categories.count)")
        for c in categories.prefix(8) { print("  · \(c.title) -> \(c.url)") }
        XCTAssertFalse(categories.isEmpty, "<js> exploreUrl 应解析出分类")

        // 2. 搜索：接口需登录 Token；书源自带共享 AccessToken 失效时跳过（用户可在 App 内表单登录）
        try await requireReachable([source.bookSourceUrl])
        let apiStatus = await searchApiStatus(source, keyword: "异世界")
        print("搜索 API 状态码：\(apiStatus)")
        guard apiStatus == 200 else {
            throw XCTSkip("搜索接口需要有效登录 Token（HTTP \(apiStatus)，书源自带共享 AccessToken 已失效，请在 App 内重新登录后运行）")
        }
        let searchStart = Date()
        let books = try await BookSearchService.shared.search(source: source, key: "异世界")
        let ms = Int(Date().timeIntervalSince(searchStart) * 1000)
        print("搜索到 \(books.count) 本书，耗时 \(ms)ms")
        for b in books.prefix(3) { print("  · \(b.name) / \(b.author) -> \(b.bookUrl)") }
        XCTAssertFalse(books.isEmpty, "登录后搜索应返回结果")
    }

    /// 分页搜索：第 1/2 页都应满页且互不重复。
    func testXkviJifanPaginationSearch() async throws {
        let sources = try await loadXkviSources()
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else { return }

        try await requireReachable([source.bookSourceUrl])
        let apiStatus = await searchApiStatus(source, keyword: "异世界")
        guard apiStatus == 200 else {
            throw XCTSkip("搜索接口需要有效登录 Token（HTTP \(apiStatus)，书源自带共享 AccessToken 已失效，请在 App 内重新登录后运行）")
        }
        let page1Books = try await BookSearchService.shared.search(source: source, key: "异世界", page: 1)
        print("Page 1 results count: \(page1Books.count)")
        XCTAssertEqual(page1Books.count, 20, "Page 1 should return 20 books")

        let page2Books = try await BookSearchService.shared.search(source: source, key: "异世界", page: 2)
        print("Page 2 results count: \(page2Books.count)")
        XCTAssertEqual(page2Books.count, 20, "Page 2 should return 20 books")

        XCTAssertNotEqual(page1Books.first?.bookUrl, page2Books.first?.bookUrl, "Page 1 and Page 2 should have different books")
    }

    /// 详情 + 目录 + 正文全链路（syosetu n4197mn，经反代域名访问）。
    func testXkviJifanDetailTocContentFlow() async throws {
        let sources = try await loadXkviSources()
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else { return }

        let testBook = Book(
            bookUrl: "https://book.xkvi.top/api/novel/syosetu/n4197mn",
            name: "女装后被异世界公主选为战神骑士！？",
            author: "",
            origin: source.bookSourceUrl,
            originName: source.bookSourceName
        )

        try await requireReachable([source.bookSourceUrl, testBook.bookUrl])
        let (detailedBook, chapters) = try await BookContentService.shared.fetchBookDetail(book: testBook, source: source)

        print("Fetched detailed book: '\(detailedBook.name)'")
        print("Author: '\(detailedBook.author)', chapters: \(chapters.count)")

        XCTAssertFalse(detailedBook.author.isEmpty, "Author should not be empty")
        XCTAssertNotEqual(detailedBook.author, "未知作者")
        XCTAssertNotNil(detailedBook.intro)
        XCTAssertFalse(detailedBook.intro!.isEmpty)
        XCTAssertFalse(chapters.isEmpty, "Chapters should be parsed")

        if let firstRealChapter = chapters.first(where: { !$0.url.isEmpty }) {
            print("Fetching chapter content: \(firstRealChapter.title) -> \(firstRealChapter.url)")
            let content = try await BookContentService.shared.fetchChapterContent(chapter: firstRealChapter, source: source)
            print("Chapter content length: \(content.count), preview: \(content.prefix(120))")
            XCTAssertFalse(content.isEmpty, "Chapter content should not be empty")
        }
    }

    /// 登录全链路：loginUrl JS 换取 Token → 登录态搜索 (level=0) → 登录态探索分类。
    /// 凭证从环境变量读取（LEGADO_XKVI_USER / LEGADO_XKVI_PASS），未设置时跳过，避免凭证入库。
    func testXkviJifanLoginFlow() async throws {
        guard let username = ProcessInfo.processInfo.environment["LEGADO_XKVI_USER"],
              let password = ProcessInfo.processInfo.environment["LEGADO_XKVI_PASS"],
              !username.isEmpty, !password.isEmpty else {
            throw XCTSkip("未设置 LEGADO_XKVI_USER / LEGADO_XKVI_PASS，跳过登录用例")
        }
        let sources = try await loadXkviSources()
        guard var source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else {
            XCTFail("机翻机器人源不存在"); return
        }

        // 1. 表单脚本登录（App 内「表单登录」走的同一套 JSEngine 流程）
        let creds = ["账号": username, "密码": password]
        source.loginInfo = try String(data: JSONSerialization.data(withJSONObject: creds), encoding: .utf8)
        let jsEngine = JSEngine(bookSource: source, baseUrl: source.bookSourceUrl)
        var capturedHeader: String? = nil
        jsEngine.onLoginHeaderUpdated = { capturedHeader = $0 }
        let loginScript = try XCTUnwrap(source.loginUrl, "loginUrl 不能为空")
        _ = jsEngine.context.evaluateScript(loginScript)

        let tokenHeader = try XCTUnwrap(capturedHeader, "登录未能捕获 Token Header（检查账号密码或站点可用性）")
        print("登录成功，Token Header: \(tokenHeader.prefix(80))...")
        source.loginHeader = tokenHeader

        // 2. 登录态搜索（searchUrl JS: level = token ? 0 : 1）
        try await requireReachable([source.bookSourceUrl])
        let books = try await BookSearchService.shared.search(source: source, key: "异世界")
        print("登录态搜索结果: \(books.count) 本")
        for b in books.prefix(3) { print("  · \(b.name) / \(b.author)") }
        XCTAssertFalse(books.isEmpty, "登录后搜索应返回结果")

        // 3. 登录态探索分类：getLoginHeader() 返回 Token → level=0 分类 + 阅读历史/收藏
        let categories = BookExploreService.shared.parseExploreCategories(source: source)
        let titles = categories.map { $0.title }
        print("登录态探索分类: \(titles)")
        XCTAssertFalse(categories.isEmpty)
        XCTAssertFalse(titles.contains("账号未登录"), "登录后不应再显示「账号未登录」占位")
        XCTAssertTrue(titles.contains("阅读历史"), "登录后应出现阅读历史分类")

        // 4. 登录态浏览分类（全部，level=0）
        if let allCategory = categories.first(where: { $0.title == "全部" && $0.url != nil }) {
            let exploreBooks = try await BookExploreService.shared.fetchExploreBooks(
                source: source, categoryUrl: allCategory.url!, page: 1)
            print("登录态分类「全部」返回 \(exploreBooks.count) 本")
            XCTAssertFalse(exploreBooks.isEmpty, "登录后分类浏览应返回书籍（此前未登录为 HTTP 502）")
        }
    }

    /// 分卷章节连续性（kakuyomu 16818093077104932645，含分卷无 chapterId）。
    func testXkviJifanVolumeDividersChapterContiguity() async throws {
        let sources = try await loadXkviSources()
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else { return }

        let testBook = Book(
            bookUrl: "https://book.xkvi.top/api/novel/kakuyomu/16818093077104932645",
            name: "只是抱着胳膊在后方看戏的转生者，不小心给勇者鼓了个掌，结果被当成了幕后黑手。",
            author: "森空亭",
            origin: source.bookSourceUrl,
            originName: source.bookSourceName
        )

        try await requireReachable([source.bookSourceUrl, testBook.bookUrl])
        let (detailedBook, chapters) = try await BookContentService.shared.fetchBookDetail(book: testBook, source: source)

        print("[Test] Fetched '\(detailedBook.name)', total readable chapters: \(chapters.count)")
        XCTAssertGreaterThan(chapters.count, 0)
        XCTAssertEqual(chapters.count, detailedBook.totalChapterNum)

        for (idx, ch) in chapters.enumerated() {
            XCTAssertEqual(ch.index, idx, "Chapter '\(ch.title)' index \(ch.index) must strictly equal array index \(idx)")
        }
    }
}

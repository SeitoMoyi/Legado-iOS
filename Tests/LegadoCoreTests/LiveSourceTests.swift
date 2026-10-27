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
            print("已携带书源 Cookie（不记录内容）")
        }
        let (resp, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("API 探测 \(probeUrl) → HTTP \(status), \(resp.count) bytes")
        XCTAssertTrue((200...299).contains(status), "携带书源 Cookie 后小说详情 API 应可访问（实际 HTTP \(status)）")
    }

    /// Evaluates the source's `header` JS (same path as `BookContentService`) to extract the
    /// `Cookie` line — book.xkvi.top rejects cookie-less API requests with 502.
    private static func resolvedCookie(source: BookSource) -> String? {
        guard let header = JSEngine.resolvedSourceHeader(source), let data = header.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return values.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value
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
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else { throw XCTSkip("The current remote source list contains no xkvi entry") }

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
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else { throw XCTSkip("The current remote source list contains no xkvi entry") }

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
        print("Kind: '\(detailedBook.kind ?? "")'")
        // kind 解析对齐 Android getStringList：JSONPath 数组规则必须返回完整标签列表
        XCTAssertFalse(detailedBook.kind?.isEmpty ?? true, "kind should be parsed (getStringList parity)")
        XCTAssertTrue(detailedBook.kind!.contains(","), "kind should contain multiple tags joined by ',' (got: \(detailedBook.kind ?? ""))")

        XCTAssertFalse(detailedBook.author.isEmpty, "Author should not be empty")
        XCTAssertNotEqual(detailedBook.author, "未知作者")
        XCTAssertNotNil(detailedBook.intro)
        XCTAssertFalse(detailedBook.intro!.isEmpty)
        XCTAssertFalse(chapters.isEmpty, "Chapters should be parsed")

        if let firstRealChapter = chapters.first(where: { $0.isVolume != true && !$0.url.isEmpty }) {
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
        let linkedJSON = try await RuleLinkService.fetch(Self.xkviListUrl)
        let sources = try XCTUnwrap(BookSource.decodeListWithExtras(from: Data(linkedJSON.utf8)))
        print("LIVE CHECK: rule-link source download and preview decoding")
        let subscription = try await RuleSubscriptionService().fetch(RuleSub(name: "Live source", url: Self.xkviListUrl, type: 0))
        guard case .bookSources(let subscribedSources) = subscription else { return XCTFail("Expected book source subscription") }
        XCTAssertEqual(subscribedSources.map(\.bookSourceUrl), sources.map(\.bookSourceUrl))
        print("LIVE CHECK: real rule-subscription download and source preview")
        guard var source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else {
            XCTFail("机翻机器人源不存在"); return
        }

        try await requireReachable([source.bookSourceUrl])
        defer { SourceSessionStore.save(header: nil, for: source.bookSourceUrl) }
        let result = try await SourceLoginService.execute(
            source: source, credentials: ["账号": username, "密码": password])
        source.loginHeader = try XCTUnwrap(result.header, "登录未返回凭据")
        source.loginInfo = result.info
        print("登录完成（不记录凭据）")

        // 2. 登录态搜索（searchUrl JS: level = token ? 0 : 1）
        let books = try await BookSearchService.shared.search(source: source, key: "异世界")
        print("登录态搜索结果: \(books.count) 本")
        for b in books.prefix(3) { print("  · \(b.name) / \(b.author)") }
        XCTAssertFalse(books.isEmpty, "登录后搜索应返回结果")

        let secondPage = try await BookSearchService.shared.search(source: source, key: "异世界", page: 2)
        XCTAssertFalse(secondPage.isEmpty)
        XCTAssertTrue(Set(books.map(\.bookUrl)).isDisjoint(with: Set(secondPage.map(\.bookUrl))), "Search pages must not repeat")
        print("LIVE CHECK: authenticated pagination")

        var recoveryChapter: BookChapter?
        if let book = books.first {
            let matched = try await ShelfImportService.find(ShelfBookInfo(name: book.name, author: book.author), sources: [source])
            XCTAssertEqual(matched?.bookUrl, book.bookUrl)
            XCTAssertEqual(matched?.name, book.name)
            XCTAssertEqual(matched?.author, book.author)
            print("LIVE CHECK: book-list import exact live title and author resolution")
            let (detail, chapters) = try await BookContentService.shared.fetchBookDetail(book: Book(bookUrl: book.bookUrl, name: book.name, author: book.author, origin: source.bookSourceUrl, originName: source.bookSourceName), source: source)
            XCTAssertFalse(detail.name.isEmpty)
            XCTAssertFalse(detail.intro?.contains("var value =") ?? false, "Introduction must contain parsed text")
            let readable = chapters.filter { $0.isVolume != true && !$0.url.isEmpty }
            XCTAssertFalse(readable.isEmpty)
            recoveryChapter = readable.first
            XCTAssertFalse(detail.intro?.isEmpty ?? true)
            XCTAssertEqual(chapters.map(\.index), Array(chapters.indices))
            print("LIVE CHECK: introduction and contiguous chapter list")
            for chapter in [readable.first, readable.count > 62 ? readable[62] : nil].compactMap({ $0 }) {
                BookContentService.shared.clearCachedChapter(bookUrl: chapter.bookUrl, chapterIndex: chapter.index)
                let body = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: source)
                XCTAssertFalse(body.isEmpty)
                XCTAssertFalse(body.contains("var value ="))
                let cachedBody = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: source)
                XCTAssertEqual(body, cachedBody)
                print("LIVE CHECK: chapter \(chapter.index), \(body.count) characters, cache reuse")
            }
            let refreshed = try await BookContentService.shared.fetchBookDetail(book: detail, source: source, runPreUpdateJs: true)
            XCTAssertEqual(refreshed.book.bookUrl, detail.bookUrl)
            XCTAssertFalse(refreshed.chapters.isEmpty)
            print("LIVE CHECK: explicit source refresh")

            for chapter in chapters.dropFirst().prefix(5) {
                BookContentService.shared.clearCachedChapter(bookUrl: chapter.bookUrl, chapterIndex: chapter.index)
            }
            let authenticatedSource = source
            let task = Task {
                await BookContentService.shared.preDownloadChapters(around: 0, chapters: chapters, source: authenticatedSource, count: 5)
            }
            try await Task.sleep(nanoseconds: 150_000_000)
            let start = Date()
            task.cancel()
            await task.value
            XCTAssertLessThan(Date().timeIntervalSince(start), 3, "Leaving must promptly stop live prefetch")
            let cachedAfterCancel = chapters.dropFirst().prefix(5).filter {
                BookContentService.shared.hasCachedChapter(bookUrl: $0.bookUrl, chapterIndex: $0.index)
            }.count
            XCTAssertLessThan(cachedAfterCancel, 5, "Cancellation must stop the remaining uncached queue")
            print("LIVE CHECK: in-flight prefetch cancellation")
            if let last = readable.last {
                BookContentService.shared.clearCachedChapter(bookUrl: last.bookUrl, chapterIndex: last.index)
                let body = try await BookContentService.shared.fetchChapterContent(chapter: last, source: source)
                XCTAssertFalse(body.isEmpty)
                print("LIVE CHECK: chapter request after cancellation")
            }
        }

        // 3. 登录态探索分类：getLoginHeader() 返回 Token → level=0 分类 + 阅读历史/收藏
        let categories = try await BookExploreService.shared.loadExploreCategories(source: source)
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
        var stale = source
        stale.loginHeader = "{\"Authorization\":\"Bearer deliberately-invalid-live-test\"}"
        SourceSessionStore.save(header: nil, for: source.bookSourceUrl)
        let recovered = try await BookSearchService.shared.search(source: stale, key: "异世界")
        XCTAssertFalse(recovered.isEmpty, "loginCheckJs must recover expired login")
        XCTAssertNotNil(SourceSessionStore.header(for: source.bookSourceUrl))
        let chapter = try XCTUnwrap(recoveryChapter)
        SourceSessionStore.save(header: nil, for: source.bookSourceUrl)
        // Some chapters are public and never return 401. Feed the source's actual
        // expiry message to its hook, then perform real login and chapter HTTP calls.
        let chapterURL = try XCTUnwrap(URL(string: chapter.url))
        let chapterEngine = JSEngine(bookSource: stale, baseUrl: chapter.url)
        let expiry = NetworkResponse(statusCode: 401, bodyString: "Token不合法或者过期", data: Data(), headers: [:], url: chapterURL)
        let replacement = try chapterEngine.checkedResponse(expiry, requestedURL: chapterURL)
        XCTAssertEqual(replacement.statusCode, 200)
        XCTAssertNotNil(SourceSessionStore.header(for: source.bookSourceUrl))
        BookContentService.shared.clearCachedChapter(bookUrl: chapter.bookUrl, chapterIndex: chapter.index)
        let recoveredChapter = try await BookContentService.shared.fetchChapterContent(chapter: chapter, source: stale)
        XCTAssertFalse(recoveredChapter.isEmpty, "Chapter requests must also refresh expired login")
        print("LIVE CHECK: chapter-specific expired-session recovery")
        var cachedSessionOnly = source
        cachedSessionOnly.loginHeader = nil
        XCTAssertTrue(cachedSessionOnly.isLogged)
        let reusedSession = try await BookSearchService.shared.search(source: cachedSessionOnly, key: "异世界", page: 2)
        XCTAssertFalse(reusedSession.isEmpty)
        print("LIVE CHECK: fresh engine reuses refreshed session")
        print("LIVE CHECK: expired-session refresh and cached login state")

    }

    /// 分卷章节连续性（kakuyomu 16818093077104932645，含分卷无 chapterId）。
    func testXkviJifanVolumeDividersChapterContiguity() async throws {
        let sources = try await loadXkviSources()
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("xkvi.top") }) else { throw XCTSkip("The current remote source list contains no xkvi entry") }

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

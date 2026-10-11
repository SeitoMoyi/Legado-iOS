import XCTest
@testable import LegadoCore

final class LegadoCoreTests: XCTestCase {

    func testCryptoUtils() throws {
        let md5 = CryptoUtils.md5("hello world")
        XCTAssertEqual(md5, "5eb63bbbe01eeed093cb22bb8f5acdc3")

        let b64 = CryptoUtils.base64Encode("Legado iOS")
        XCTAssertEqual(b64, "TGVnYWRvIGlPUw==")
        let decoded = CryptoUtils.base64Decode(b64)
        XCTAssertEqual(decoded, "Legado iOS")
    }

    func testJSEngine() throws {
        let engine = JSEngine()

        // Test math
        let result = engine.eval(script: "1 + 2 * 3") as? NSNumber
        XCTAssertEqual(result?.intValue, 7)

        // Test java.put and java.get
        _ = engine.eval(script: "java.put('myKey', 'myValue')")
        let retrieved = engine.eval(script: "java.get('myKey')") as? String
        XCTAssertEqual(retrieved, "myValue")

        // Test java.md5Encode
        let md5 = engine.eval(script: "java.md5Encode('test')") as? String
        XCTAssertEqual(md5, "098f6bcd4621d373cade4e832627b4f6")

        // Test template interpolation
        let rendered = engine.renderTemplate("https://domain.com?key={{'search' + 'Key'}}&page={{1 + 1}}")
        XCTAssertEqual(rendered, "https://domain.com?key=searchKey&page=2")
    }

    func testJSONPath() throws {
        let json: [String: Any] = [
            "code": 200,
            "data": [
                "book": [
                    "title": "Three Body Problem",
                    "author": "Liu Cixin"
                ],
                "chapters": [
                    ["name": "Chapter 1"],
                    ["name": "Chapter 2"]
                ]
            ]
        ]

        let title = JSONPath.evaluate(path: "$.data.book.title", json: json) as? String
        XCTAssertEqual(title, "Three Body Problem")

        let chapters = JSONPath.evaluate(path: "$.data.chapters[*].name", json: json) as? [String]
        XCTAssertEqual(chapters, ["Chapter 1", "Chapter 2"])
    }

    func testHtmlRuleAnalyzer() throws {
        let html = """
        <html>
            <body>
                <div class="book-info">
                    <h1 class="title">My Great Book</h1>
                    <span class="author">Author Name</span>
                </div>
                <div class="chapter-list">
                    <a href="/ch1.html">Chapter 1: The Beginning</a>
                    <a href="/ch2.html">Chapter 2: The Journey</a>
                </div>
            </body>
        </html>
        """

        let analyzer = RuleAnalyzer(content: html, baseUrl: "https://example.com")

        let title = analyzer.getString("h1.title@text")
        XCTAssertEqual(title, "My Great Book")

        let author = analyzer.getString("span.author@text")
        XCTAssertEqual(author, "Author Name")

        let chapters = analyzer.getStringList("div.chapter-list a@text")
        XCTAssertEqual(chapters, ["Chapter 1: The Beginning", "Chapter 2: The Journey"])

        let links = analyzer.getStringList("div.chapter-list a@href", isUrl: true)
        XCTAssertEqual(links, ["https://example.com/ch1.html", "https://example.com/ch2.html"])
    }

    func testBookSourceJsonDecoding() throws {
        let json = """
        {
            "bookSourceName": "Test Source",
            "bookSourceUrl": "https://test.com",
            "searchUrl": "https://test.com/search?key={{key}}",
            "ruleSearch": {
                "bookList": "div.book",
                "name": "h3@text",
                "author": "span.author@text",
                "bookUrl": "a@href"
            },
            "ruleToc": {
                "chapterList": "div.chapters a",
                "chapterName": "text",
                "chapterUrl": "href"
            },
            "ruleContent": {
                "content": "#content@text"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let source = try JSONDecoder().decode(BookSource.self, from: data)

        XCTAssertEqual(source.bookSourceName, "Test Source")
        XCTAssertEqual(source.bookSourceUrl, "https://test.com")
        XCTAssertEqual(source.ruleSearch?.name, "h3@text")
        XCTAssertEqual(source.ruleToc?.chapterList, "div.chapters a")
        XCTAssertEqual(source.ruleContent?.content, "#content@text")
    }

    func testRealBookSourcesJsonDecoding() throws {
        // Find defaultData/bookSources.json relative to tests
        let currentFileUrl = URL(fileURLWithPath: #file)
        let rootDir = currentFileUrl
            .deletingLastPathComponent() // Tests/LegadoCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // legado-master
        let assetFile = rootDir.appendingPathComponent("app/src/main/assets/defaultData/bookSources.json")

        guard FileManager.default.fileExists(atPath: assetFile.path) else {
            print("Skipping real bookSources.json test: file not found at \(assetFile.path)")
            return
        }

        let data = try Data(contentsOf: assetFile)
        let sources = try JSONDecoder().decode([BookSource].self, from: data)

        XCTAssertFalse(sources.isEmpty)
        let first = sources[0]
        XCTAssertEqual(first.bookSourceName, "消消乐听书")
        XCTAssertEqual(first.bookSourceUrl, "https://www.kaixin7days.com")
        XCTAssertNotNil(first.ruleSearch)
        XCTAssertNotNil(first.ruleToc)
    }

    func testUserEpubFileParsing() throws {
        let epubPath = "/Users/peibinxu/Downloads/我，当备胎女友就可以.epub"
        let epubUrl = URL(fileURLWithPath: epubPath)

        guard FileManager.default.fileExists(atPath: epubPath) else {
            print("Skipping epub test: file not found at \(epubPath)")
            return
        }

        let parsed = try EpubParser.shared.parse(epubUrl: epubUrl)

        XCTAssertTrue(parsed.book.name.contains("我，当备胎女友就可以"))
        XCTAssertFalse(parsed.chapters.isEmpty)
        print("Successfully parsed EPUB: \(parsed.book.name)")
        print("Total chapters parsed: \(parsed.chapters.count)")

        // Verify chapters
        let ch0 = parsed.chapters[0]
        let ch1 = parsed.chapters[1]
        let ch2 = parsed.chapters[2]

        print("Chapter 0: \(ch0.title) -> \(ch0.url)")
        print("Chapter 1: \(ch1.title) -> \(ch1.url)")
        print("Chapter 2: \(ch2.title) -> \(ch2.url)")

        XCTAssertFalse(ch0.title.isEmpty)
        XCTAssertEqual(ch1.title, "序章")
        XCTAssertTrue(ch2.title.contains("第1话"))

        // Verify chapter content extraction via BookContentService and EpubParser
        let content0 = EpubParser.extractChapterContent(fromUrlString: ch0.url, bookUrl: ch0.bookUrl)
        let content1 = EpubParser.extractChapterContent(fromUrlString: ch1.url, bookUrl: ch1.bookUrl)
        let content2 = EpubParser.extractChapterContent(fromUrlString: ch2.url, bookUrl: ch2.bookUrl)

        XCTAssertFalse(content0.isEmpty)
        XCTAssertFalse(content1.isEmpty, "Prologue content should not be empty")
        XCTAssertFalse(content2.isEmpty, "Chapter 1 content should not be empty")

        print("Ch0 content preview: \(content0.prefix(60))...")
        print("Ch1 (序章) content preview: \(content1.prefix(100))...")
        print("Ch2 (第1话) content preview: \(content2.prefix(100))...")

        // Verify chapter 14 (illustrations) extracts [image:...] blocks
        if parsed.chapters.count > 14 {
            let ch14 = parsed.chapters[14]
            let content14 = EpubParser.extractChapterContent(fromUrlString: ch14.url, bookUrl: ch14.bookUrl)
            print("Ch14 (插图) content preview: \(content14.prefix(120))...")
            XCTAssertTrue(content14.contains("[image:"), "Chapter 14 should contain image blocks")
        }
    }

    func testAkuyakuEpubParsing() throws {
        let epubPath = "/Users/peibinxu/Downloads/zh.Ysgy.悪役魔法使いの改心２.epub"
        let epubUrl = URL(fileURLWithPath: epubPath)

        guard FileManager.default.fileExists(atPath: epubPath) else {
            print("Skipping akuyaku epub test: file not found at \(epubPath)")
            return
        }

        let parsed = try EpubParser.shared.parse(epubUrl: epubUrl)
        print("Successfully parsed Akuyaku EPUB: \(parsed.book.name)")
        print("Total chapters: \(parsed.chapters.count)")
        for (i, ch) in parsed.chapters.prefix(6).enumerated() {
            print("Ch[\(i)]: \(ch.title) -> \(ch.url)")
            let content = EpubParser.extractChapterContent(fromUrlString: ch.url, bookUrl: ch.bookUrl)
            print("   Content length: \(content.count), preview: \(content.prefix(80))...")
        }
    }

    func testJsonRuleAnalyzerWithTemplates() throws {
        let json: [String: Any] = [
            "items": [
                [
                    "titleZh": "备胎女友",
                    "titleJp": "本命...",
                    "providerId": "kakuyomu",
                    "novelId": "12345678",
                    "cover": "https://example.com/cover.jpg"
                ]
            ]
        ]

        let analyzer = RuleAnalyzer(content: json, baseUrl: "https://book.xkvi.top")
        let elements = analyzer.getElements("items")
        XCTAssertEqual(elements.count, 1)

        guard let firstItem = elements.first as? [String: Any] else {
            XCTFail("Expected first element to be [String: Any]")
            return
        }

        let itemAnalyzer = RuleAnalyzer(content: firstItem, baseUrl: "https://book.xkvi.top")
        let name = itemAnalyzer.getString("<js>result.titleZh || result.titleJp</js>")
        XCTAssertEqual(name, "备胎女友")

        let bookUrl = itemAnalyzer.getString("/api/novel/{{$.providerId}}/{{$..novelId}}", isUrl: true)
        XCTAssertEqual(bookUrl, "https://book.xkvi.top/api/novel/kakuyomu/12345678")
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
        let books = try await BookSearchService.shared.search(source: source, key: "斗破苍穹")
        print("Search results count: \(books.count)")
        for b in books.prefix(3) {
            print("Found book: \(b.name) by \(b.author) -> \(b.bookUrl)")
        }
        XCTAssertFalse(books.isEmpty, "Should find books for 斗破苍穹")
    }

    func testJifanRobotFullFlow() async throws {
        let currentFileUrl = URL(fileURLWithPath: #file)
        let rootDir = currentFileUrl
            .deletingLastPathComponent() // Tests/LegadoCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
        let assetFile = rootDir.appendingPathComponent("Sources/LegadoApp/Resources/bookSources.json")
        guard FileManager.default.fileExists(atPath: assetFile.path) else {
            print("Skipping testJifanRobotFullFlow: bookSources.json not found at \(assetFile.path)")
            return
        }

        let data = try Data(contentsOf: assetFile)
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard var jifanSource = sources.first(where: { $0.bookSourceName == "机翻机器人" }) else {
            XCTFail("机翻机器人 source not found")
            return
        }

        // 1. Perform login
        let creds = ["账号": "SeitoMoyi", "密码": "Seito111520"]
        let credData = try JSONSerialization.data(withJSONObject: creds)
        let credJson = String(data: credData, encoding: .utf8)!
        jifanSource.loginInfo = credJson

        let jsEngine = JSEngine(bookSource: jifanSource, baseUrl: jifanSource.bookSourceUrl)
        var capturedHeader: String? = nil
        jsEngine.onLoginHeaderUpdated = { capturedHeader = $0 }
        _ = jsEngine.eval(script: jifanSource.loginUrl!)

        guard let tokenHeader = capturedHeader, !tokenHeader.isEmpty else {
            XCTFail("Login failed to capture token header")
            return
        }
        print("Captured Login Header: \(tokenHeader.prefix(60))...")
        jifanSource.loginHeader = tokenHeader

        // 2. Search books
        let books = try await BookSearchService.shared.search(source: jifanSource, key: "恶役")
        print("Found books from 机翻机器人: \(books.count)")
        XCTAssertFalse(books.isEmpty, "Should find books from 机翻机器人")
        let firstBook = books[0]
        print("First book: \(firstBook.name) -> \(firstBook.bookUrl)")

        // 3. Fetch TOC (chapter list)
        let modelBook = Book(
            bookUrl: firstBook.bookUrl,
            name: firstBook.name,
            author: firstBook.author,
            origin: jifanSource.bookSourceUrl,
            originName: jifanSource.bookSourceName
        )
        let chapters = try await BookContentService.shared.fetchChapterList(book: modelBook, source: jifanSource)
        print("Fetched TOC chapters: \(chapters.count)")
        XCTAssertFalse(chapters.isEmpty, "Should fetch chapters from 机翻机器人")

        // 4. Fetch content for first non-volume chapter
        if let firstRealChapter = chapters.first(where: { !$0.url.isEmpty }) {
            print("Fetching chapter content: \(firstRealChapter.title) -> \(firstRealChapter.url)")
            let content = try await BookContentService.shared.fetchChapterContent(chapter: firstRealChapter, source: jifanSource)
            print("Chapter content length: \(content.count), preview:\n\(content.prefix(200))")
            XCTAssertFalse(content.isEmpty, "Chapter content should not be empty")
        }
    }

    func testPaginationSearchJifanRobot() async throws {
        let currentFileUrl = URL(fileURLWithPath: #file)
        let rootDir = currentFileUrl
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetFile = rootDir.appendingPathComponent("Sources/LegadoApp/Resources/bookSources.json")
        guard FileManager.default.fileExists(atPath: assetFile.path) else { return }

        let data = try Data(contentsOf: assetFile)
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let jifanSource = sources.first(where: { $0.bookSourceName == "机翻机器人" }) else { return }

        // Test Page 1
        let page1Books = try await BookSearchService.shared.search(source: jifanSource, key: "异世界", page: 1)
        print("Page 1 results count: \(page1Books.count)")
        XCTAssertEqual(page1Books.count, 20, "Page 1 should return 20 books")

        // Test Page 2
        let page2Books = try await BookSearchService.shared.search(source: jifanSource, key: "异世界", page: 2)
        print("Page 2 results count: \(page2Books.count)")
        XCTAssertEqual(page2Books.count, 20, "Page 2 should return 20 books")

        // Ensure Page 1 and Page 2 contain different books
        XCTAssertNotEqual(page1Books.first?.bookUrl, page2Books.first?.bookUrl, "Page 1 and Page 2 should have different books")

        // Test multi-source pagination streaming
        var receivedBatches = 0
        for await (source, books) in BookSearchService.shared.searchMultiSources(sources: [jifanSource], key: "异世界", page: 2) {
            print("Received batch from \(source.bookSourceName) for page 2: \(books.count) books")
            receivedBatches += 1
            XCTAssertFalse(books.isEmpty)
        }
        XCTAssertEqual(receivedBatches, 1)
    }

    func testFetchBookDetailAuthorAndIntro() async throws {
        let currentFileUrl = URL(fileURLWithPath: #file)
        let rootDir = currentFileUrl
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetFile = rootDir.appendingPathComponent("Sources/LegadoApp/Resources/bookSources.json")
        guard FileManager.default.fileExists(atPath: assetFile.path) else { return }

        let data = try Data(contentsOf: assetFile)
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let jifanSource = sources.first(where: { $0.bookSourceName == "机翻机器人" }) else { return }

        // Test book from Novelia: syosetu n4197mn
        let testBook = Book(
            bookUrl: "https://n.novelia.cc/api/novel/syosetu/n4197mn",
            name: "女装后被异世界公主选为战神骑士！？",
            author: "",
            origin: jifanSource.bookSourceUrl,
            originName: jifanSource.bookSourceName
        )

        let (detailedBook, chapters) = try await BookContentService.shared.fetchBookDetail(book: testBook, source: jifanSource)

        print("Fetched detailed book: '\(detailedBook.name)'")
        print("Author: '\(detailedBook.author)'")
        print("Intro length: \(detailedBook.intro?.count ?? 0), preview: \(detailedBook.intro?.prefix(80) ?? "")")
        print("Chapters count: \(chapters.count)")

        XCTAssertFalse(detailedBook.author.isEmpty, "Author should not be empty")
        XCTAssertNotEqual(detailedBook.author, "未知作者")
        XCTAssertTrue(detailedBook.author.contains("神泉"), "Author should contain the actual author name")
        XCTAssertNotNil(detailedBook.intro)
        XCTAssertFalse(detailedBook.intro!.isEmpty)
        XCTAssertFalse(detailedBook.intro!.hasPrefix("源站："), "Intro should be real story synopsis, not debug metadata")
        XCTAssertFalse(chapters.isEmpty, "Chapters should be parsed")
    }

    func testWebDAVConfigAndOperations() async throws {
        // 1. Config tests
        let config = WebDAVConfig(
            url: "https://dav.jianguoyun.com/dav",
            username: "test@example.com",
            password: "password123",
            remotePath: "/legado/"
        )

        XCTAssertEqual(config.directoryURL?.absoluteString, "https://dav.jianguoyun.com/dav/legado/")
        XCTAssertTrue(config.basicAuthHeader.starts(with: "Basic "))

        // 2. Mock URLSession for WebDAVService
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockWebDAVURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        let webdavService = WebDAVService(session: mockSession)

        // Mock testConnection (PROPFIND returning 207)
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), config.basicAuthHeader)
            let response = HTTPURLResponse(url: request.url!, statusCode: 207, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let testResult = try await webdavService.testConnection(config: config)
        XCTAssertTrue(testResult.contains("成功"))

        // Mock backup
        var uploadedBooksData: Data?
        var uploadedSourcesData: Data?

        func readBody(from req: URLRequest) -> Data? {
            if let d = req.httpBody { return d }
            guard let stream = req.httpBodyStream else { return nil }
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var result = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 {
                    result.append(buffer, count: read)
                } else {
                    break
                }
            }
            return result
        }

        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), config.basicAuthHeader)
            if request.httpMethod == "MKCOL" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, nil)
            } else if request.httpMethod == "PUT" {
                if request.url?.lastPathComponent == "bookshelf.json" {
                    uploadedBooksData = readBody(from: request)
                } else if request.url?.lastPathComponent == "bookSource.json" {
                    uploadedSourcesData = readBody(from: request)
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, nil)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let testBooks = [Book(bookUrl: "test://b1", name: "测试书名", author: "测试作者")]
        let testSources = [BookSource(bookSourceUrl: "https://test.com", bookSourceName: "测试书源")]

        let backupResult = try await webdavService.backup(books: testBooks, sources: testSources, config: config)
        XCTAssertEqual(backupResult.booksCount, 1)
        XCTAssertEqual(backupResult.sourcesCount, 1)
        XCTAssertNotNil(uploadedBooksData)
        XCTAssertNotNil(uploadedSourcesData)

        // Mock restore
        MockWebDAVURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), config.basicAuthHeader)
            if request.url?.lastPathComponent == "bookshelf.json" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, uploadedBooksData)
            } else if request.url?.lastPathComponent == "bookSource.json" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, uploadedSourcesData)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let restoreResult = try await webdavService.restore(config: config)
        XCTAssertEqual(restoreResult.books?.count, 1)
        XCTAssertEqual(restoreResult.books?.first?.name, "测试书名")
        XCTAssertEqual(restoreResult.sources?.count, 1)
        XCTAssertEqual(restoreResult.sources?.first?.bookSourceName, "测试书源")
    }

    func testExploreCategoriesParsing() throws {
        let altUrl = URL(fileURLWithPath: "Sources/LegadoApp/Resources/bookSources.json")
        let data = try Data(contentsOf: altUrl)
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let robot = sources.first(where: { $0.bookSourceName == "机翻机器人" }) else {
            XCTFail("Robot source not found")
            return
        }
        let cats = BookExploreService.shared.parseExploreCategories(source: robot)
        XCTAssertFalse(cats.isEmpty, "Categories should not be empty")
        print("Parsed robot categories count: \(cats.count)")
        let titles = cats.map { $0.title }
        print("Category titles: \(titles)")
        XCTAssertTrue(titles.contains("阅读历史") || titles.contains("全部来源") || titles.contains("kakuyomu"))
    }

    func testAndroidLegadoZipBackupParsing() throws {
        let zipPath = "/Users/peibinxu/Downloads/backup2026-09-29-25060RK16C.zip"
        guard FileManager.default.fileExists(atPath: zipPath) else {
            print("Skipping local test: backup zip not present")
            return
        }
        let zipUrl = URL(fileURLWithPath: zipPath)
        let result = try WebDAVService.shared.restoreFromZip(fileUrl: zipUrl)

        XCTAssertNotNil(result.books, "Books should be decoded")
        XCTAssertEqual(result.books?.count, 228, "Should decode exactly 228 books from Android Legado backup")
        XCTAssertNotNil(result.sources, "Sources should be decoded")
        XCTAssertEqual(result.sources?.count, 2, "Should decode exactly 2 sources from Android Legado backup")

        let sourceNames = result.sources?.map { $0.bookSourceName } ?? []
        XCTAssertTrue(sourceNames.contains("机翻机器人"))
        XCTAssertTrue(sourceNames.contains("ESJ Zone@zone"))

        let sampleBook = result.books?.first(where: { $0.name.contains("高中生作曲家") })
        XCTAssertNotNil(sampleBook)
        print("Sample book durChapterIndex: \(sampleBook?.durChapterIndex ?? 0), title: \(sampleBook?.durChapterTitle ?? "")")
        XCTAssertEqual(sampleBook?.durChapterIndex, 115)
        XCTAssertEqual(sampleBook?.durChapterTitle, "第4话　误解")
    }

    func testESJZoneParsingAndHtmlClean() throws {
        // 1. Test cleanHtml
        let dirtyHtml = "<p>这是一段包含<strong>加粗</strong>和&lrm;特殊符号的简介。</p><br/><p>第二段内容&nbsp;&quot;引言&quot;&amp;测试</p>"
        let cleaned = BookContentService.cleanHtml(dirtyHtml)
        XCTAssertFalse(cleaned.contains("<p>"))
        XCTAssertFalse(cleaned.contains("</p>"))
        XCTAssertFalse(cleaned.contains("<br/>"))
        XCTAssertFalse(cleaned.contains("&lrm;"))
        XCTAssertFalse(cleaned.contains("&nbsp;"))
        XCTAssertTrue(cleaned.contains("\"引言\"&测试"))
        XCTAssertTrue(cleaned.contains("这是一段包含加粗和特殊符号的简介。"))
        XCTAssertTrue(cleaned.contains("第二段内容"))

        // 2. Test ESJ TOC multi-step CSS chain rule: #chapterList@a[data-title], p.non, summary
        let esjHtml = """
        <html>
        <body>
            <ul class="list-unstyled">
                <li><span>类别：</span><a href="#">轻小说</a></li>
                <li><span>作者：</span><a href="#">测试作者</a></li>
            </ul>
            <div id="chapterList">
                <div class="row">
                    <a href="https://esjzone.cc/forum/123/1.html" data-title="第1话 开始">第1话 开始</a>
                    <a href="https://esjzone.cc/forum/123/2.html" data-title="第2话 旅途">第2话 旅途</a>
                </div>
            </div>
        </body>
        </html>
        """

        let analyzer = RuleAnalyzer(content: esjHtml, baseUrl: "https://esjzone.cc/detail/123.html")
        let author = analyzer.getString("ul.list-unstyled@li.1@a@text")
        XCTAssertEqual(author, "测试作者")

        let elements = analyzer.getElements("#chapterList@a[data-title], p.non, summary")
        XCTAssertEqual(elements.count, 2)

        let titles = elements.compactMap { el in
            RuleAnalyzer(content: el, baseUrl: "https://esjzone.cc/detail/123.html").getString("text")
        }
        XCTAssertEqual(titles, ["第1话 开始", "第2话 旅途"])

        let links = elements.compactMap { el in
            RuleAnalyzer(content: el, baseUrl: "https://esjzone.cc/detail/123.html").getString("a@href", isUrl: true)
        }
        XCTAssertEqual(links, ["https://esjzone.cc/forum/123/1.html", "https://esjzone.cc/forum/123/2.html"])
    }

    func testChapterCacheAndClearing() throws {
        let testBookUrl = "https://example.com/novel/test12345"
        let chIndex = 0
        let testContent = "这是测试缓存的第一章正文内容。"

        // Ensure clean state
        BookContentService.shared.clearCache(for: testBookUrl)
        XCTAssertNil(BookContentService.shared.getCachedChapterContent(bookUrl: testBookUrl, chapterIndex: chIndex))
        XCTAssertEqual(BookContentService.shared.getCacheCount(for: testBookUrl), 0)

        // Save cache
        BookContentService.shared.saveCachedChapterContent(bookUrl: testBookUrl, chapterIndex: chIndex, content: testContent)
        XCTAssertEqual(BookContentService.shared.getCachedChapterContent(bookUrl: testBookUrl, chapterIndex: chIndex), testContent)
        XCTAssertEqual(BookContentService.shared.getCacheCount(for: testBookUrl), 1)

        // Clear cache
        BookContentService.shared.clearCache(for: testBookUrl)
        XCTAssertNil(BookContentService.shared.getCachedChapterContent(bookUrl: testBookUrl, chapterIndex: chIndex))
        XCTAssertEqual(BookContentService.shared.getCacheCount(for: testBookUrl), 0)
    }
}

class MockWebDAVURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockWebDAVURLProtocol.requestHandler else {
            XCTFail("Handler not set.")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}


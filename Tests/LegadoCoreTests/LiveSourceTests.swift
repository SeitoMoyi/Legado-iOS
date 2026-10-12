import XCTest
import Foundation
#if canImport(LegadoCore)
@testable import LegadoCore
#endif

/// Live-source smoke tests.
///
/// These hit real book sources (`m.suixkan.com`, 机翻机器人, `n.novelia.cc`) and exist to check
/// the rule engine against sites that actually change. They are **not** a release gate: CI runs
/// `swift test --skip LiveSourceTests`, and even a local run degrades to a skip instead of a
/// failure whenever a host is down, slow, or the machine is offline — so "the site is having a
/// day off" can never look like "the parser is broken".
final class LiveSourceTests: XCTestCase {

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
        try await requireReachable([jifanSource.bookSourceUrl])
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
        try await requireReachable([jifanSource.bookSourceUrl])
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

        try await requireReachable([jifanSource.bookSourceUrl, testBook.bookUrl])
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

    func testBookWithVolumeDividersChapterContiguity() async throws {
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

        // Test book: "只是抱着胳膊在后方看戏的转生者，不小心给勇者鼓了个掌，结果被当成了幕后黑手。"
        // URL: https://n.novelia.cc/api/novel/kakuyomu/16818093077104932645
        // This novel contains volume divisions (序章, 第一章, 英雄指定启动篇, etc.) without chapterId.
        let testBook = Book(
            bookUrl: "https://n.novelia.cc/api/novel/kakuyomu/16818093077104932645",
            name: "只是抱着胳膊在后方看戏的转生者，不小心给勇者鼓了个掌，结果被当成了幕后黑手。",
            author: "森空亭",
            origin: jifanSource.bookSourceUrl,
            originName: jifanSource.bookSourceName
        )

        try await requireReachable([jifanSource.bookSourceUrl, testBook.bookUrl])
        let (detailedBook, chapters) = try await BookContentService.shared.fetchBookDetail(book: testBook, source: jifanSource)

        print("[Test] Fetched '\(detailedBook.name)', total readable chapters: \(chapters.count)")
        XCTAssertGreaterThan(chapters.count, 0)
        XCTAssertEqual(chapters.count, detailedBook.totalChapterNum)

        // Verify that EVERY chapter index matches its array position exactly (0, 1, 2, ..., count-1)
        for (idx, ch) in chapters.enumerated() {
            XCTAssertEqual(ch.index, idx, "Chapter '\(ch.title)' index \(ch.index) must strictly equal array index \(idx)")
        }

        // Verify first and last chapters
        XCTAssertTrue(chapters[0].title.contains("第1话"))
        XCTAssertEqual(chapters[0].index, 0)
        XCTAssertTrue(chapters.last!.title.contains("第27话"))
        XCTAssertEqual(chapters.last!.index, chapters.count - 1)
    }
}

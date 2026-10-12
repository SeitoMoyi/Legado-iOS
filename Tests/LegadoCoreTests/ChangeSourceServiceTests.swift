import XCTest
@testable import LegadoCore

/// P0-4: candidate matching rules. These run offline, so they are the parts that can be
/// pinned without a live network.
final class ChangeSourceServiceTests: XCTestCase {

    private func book(_ name: String = "测试书", _ author: String = "某人") -> Book {
        Book(bookUrl: "https://a.test/book/1", name: name, author: author,
             origin: "https://a.test", originName: "A")
    }

    private func found(_ name: String, _ author: String, url: String = "https://b.test/book/2") -> SearchBook {
        SearchBook(name: name, author: author, bookUrl: url, origin: "https://b.test",
                   originName: "B")
    }

    func testAuthorNormalization() {
        XCTAssertEqual(ChangeSourceService.normalizeAuthor("作者：张三"), "张三")
        XCTAssertEqual(ChangeSourceService.normalizeAuthor("作者: 张三 "), "张三")
        XCTAssertEqual(ChangeSourceService.normalizeAuthor("张三 著"), "张三")
        XCTAssertEqual(ChangeSourceService.normalizeAuthor("  张三"), "张三")
    }

    func testTitleMustMatchExactly() {
        XCTAssertFalse(ChangeSourceService.matches(book: book("测试书"), found: found("测试书籍", "某人"),
                                                   checkAuthor: false),
                       "a prefix match is not the same book")
        XCTAssertTrue(ChangeSourceService.matches(book: book("测试书"), found: found("测试书", "完全不同"),
                                                  checkAuthor: false))
    }

    func testAuthorCheckIsSubstringWhenEnabled() {
        XCTAssertTrue(ChangeSourceService.matches(book: book("测试书", "张三"),
                                                  found: found("测试书", "张三 李四"), checkAuthor: true),
                       "sources append translators to the author field")
        XCTAssertFalse(ChangeSourceService.matches(book: book("测试书", "张三"),
                                                   found: found("测试书", "王五"), checkAuthor: true))
    }

    func testPlaceholderAuthorIsNotChecked() {
        XCTAssertTrue(ChangeSourceService.matches(book: book("测试书", "未知作者"),
                                                  found: found("测试书", "随便谁"), checkAuthor: true))
        XCTAssertTrue(ChangeSourceService.matches(book: book("测试书", ""),
                                                  found: found("测试书", "随便谁"), checkAuthor: true))
    }

    func testAuthorPrefixVariantsAreStripped() {
        for raw in ["作 者：张三", "作者：张三", "张三著"] {
            XCTAssertEqual(ChangeSourceService.normalizeAuthor(raw), "张三", raw)
        }
    }

    func testConcurrencyCapIsSafe() {
        XCTAssertGreaterThan(ChangeSourceService.maxConcurrent, 0)
        XCTAssertLessThanOrEqual(ChangeSourceService.maxConcurrent, 16,
                                 "must stay below the reader's own prefetch pressure")
    }
}

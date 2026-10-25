import XCTest
#if canImport(LegadoCore)
import LegadoCore
#endif
@testable import LegadoCore

/// 扫码结果分流锁（Plan 第一批 Part 3）：扫码/相册识别出的字符串必须按 GSON 字段形态
/// 落到正确的导入通道，URL 与普通文本不误判。
final class ScanPayloadTests: XCTestCase {

    func testDetectsBookSourceObjectAndArray() {
        let single = #"{"bookSourceName":"示例源","bookSourceUrl":"https://a.com"}"#
        XCTAssertEqual(ScanPayload.detect(single), .bookSources(json: single))

        let array = #"[{"bookSourceName":"A","bookSourceUrl":"https://a.com"},{"bookSourceName":"B","bookSourceUrl":"https://b.com"}]"#
        XCTAssertEqual(ScanPayload.detect(array), .bookSources(json: array))
    }

    func testDetectsReplaceRule() {
        let json = #"{"name":"去广告","pattern":"^广告.*$","replacement":"","isRegex":true}"#
        XCTAssertEqual(ScanPayload.detect(json), .replaceRules(json: json))
    }

    func testDetectsRssSource() {
        let json = #"{"sourceName":"订阅","sourceUrl":"https://rss.example","sortUrl":"分类::/a"}"#
        XCTAssertEqual(ScanPayload.detect(json), .rssSources(json: json))
    }

    func testDetectsDictRule() {
        let json = #"{"name":"百度汉语","urlRule":"https://hanyu.baidu.com/s?wd={{key}}","showRule":".content@html"}"#
        XCTAssertEqual(ScanPayload.detect(json), .dictRules(json: json))
    }

    func testDetectsWebDAVConfig() {
        let json = #"{"url":"https://dav.jianguoyun.com/dav/","username":"a@b.com","password":"token","remotePath":"legado"}"#
        XCTAssertEqual(ScanPayload.detect(json), .webdavConfig(json: json))
    }

    func testDetectsImportURLs() {
        XCTAssertEqual(ScanPayload.detect("https://example.com/source.json"),
                       .importURL("https://example.com/source.json"))
        XCTAssertEqual(ScanPayload.detect("legado://import/source?src=https://x.com/s.json"),
                       .importURL("legado://import/source?src=https://x.com/s.json"))
        XCTAssertEqual(ScanPayload.detect("yuedu://x"), .importURL("yuedu://x"))
    }

    func testPlainTextAndNonPayloadJSONFallBackToText() {
        XCTAssertEqual(ScanPayload.detect("随便一段文字"), .text("随便一段文字"))
        XCTAssertEqual(ScanPayload.detect(#"{"note":"没有已知字段的 JSON"}"#),
                       .text(#"{"note":"没有已知字段的 JSON"}"#))
        XCTAssertEqual(ScanPayload.detect("12345"), .text("12345"))
        XCTAssertEqual(ScanPayload.detect("  "), .text("  "))
    }

    func testKindLabels() {
        XCTAssertEqual(ScanPayload.detect(#"{"bookSourceUrl":"https://a.com"}"#).kindLabel, "书源")
        XCTAssertEqual(ScanPayload.detect("https://a.com").kindLabel, "导入链接")
        XCTAssertEqual(ScanPayload.detect("文本").kindLabel, "文本")
    }
}

/// 添加网址的书源匹配锁：bookUrlPattern 优先，前缀其次，同 host 兜底，最长前缀胜出。
final class BookUrlMatcherTests: XCTestCase {

    private func source(url: String, pattern: String? = nil) -> BookSource {
        BookSource(bookSourceUrl: url, bookSourceName: url, bookUrlPattern: pattern)
    }

    func testURLPatternWinsOverPrefix() {
        let byPrefix = source(url: "https://a.com")
        let byPattern = source(url: "https://b.com", pattern: #".*example\.com/book/\d+.*"#)
        let match = BookUrlMatcher.match(url: "https://example.com/book/123.html",
                                         sources: [byPrefix, byPattern])
        XCTAssertEqual(match?.source.bookSourceUrl, "https://b.com")
        XCTAssertEqual(match?.by, .urlPattern)
    }

    func testHostPrefixMatch() {
        let source = source(url: "https://example.com")
        let match = BookUrlMatcher.match(url: "https://example.com/book/9.html", sources: [source])
        XCTAssertEqual(match?.source.bookSourceUrl, "https://example.com")
        XCTAssertEqual(match?.by, .hostPrefix)
    }

    func testLongestPrefixWins() {
        let root = source(url: "https://example.com")
        let deeper = source(url: "https://example.com/book")
        let match = BookUrlMatcher.match(url: "https://example.com/book/9.html", sources: [root, deeper])
        XCTAssertEqual(match?.source.bookSourceUrl, "https://example.com/book")
    }

    func testSameHostFallbackWithoutPrefix() {
        // 源 URL 带路径，目标 URL 在另一路径下 → 前缀不中，但 host 相同。
        let source = source(url: "https://example.com/read")
        let match = BookUrlMatcher.match(url: "https://example.com/api/book/1", sources: [source])
        XCTAssertEqual(match?.source.bookSourceUrl, "https://example.com/read")
    }

    func testNoMatchReturnsNil() {
        let source = source(url: "https://other.com")
        XCTAssertNil(BookUrlMatcher.match(url: "https://example.com/book/1", sources: [source]))
        XCTAssertNil(BookUrlMatcher.match(url: "", sources: [source]))
        XCTAssertNil(BookUrlMatcher.match(url: "https://a.com", sources: []))
    }
}

import XCTest
@testable import LegadoCore

/// Plan §二 #15: models must round-trip Android fields they do not declare.
///
/// Android serialises `BookSource` / `RssSource` / `Book` with GSON, so a payload can carry
/// `jsLib`, `concurrentRate`, `Book.customTag`, `Book.charset`, … iOS models whitelist their
/// own keys; these tests pin the `extra` passthrough that keeps undeclared keys lossless
/// through import → export / WebDAV backup.
final class JSONExtrasTests: XCTestCase {

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func jsonArray(_ elements: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: elements)
    }

    // MARK: - BookSource

    func testBookSourcePreservesUnmodeledAndroidFields() throws {
        let data = json([
            "bookSourceUrl": "https://example.com",
            "bookSourceName": "示例源",
            "jsLib": "<js>lib()</js>",
            "concurrentRate": "1/1000",
            "enabledCookieJar": true,
            "ruleReview": "class.review@text",
            "variableComment": "说明"
        ])

        let decoded = try XCTUnwrap(BookSource.decodeWithExtras(from: data))
        XCTAssertEqual(decoded.extra["jsLib"], JSONValue.string("<js>lib()</js>"))
        XCTAssertEqual(decoded.extra["concurrentRate"], JSONValue.string("1/1000"))
        XCTAssertEqual(decoded.extra["enabledCookieJar"], JSONValue.bool(true))
        XCTAssertEqual(decoded.extra["ruleReview"], JSONValue.string("class.review@text"))
        XCTAssertEqual(decoded.variableComment, "说明")

        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        XCTAssertEqual(reencoded["jsLib"] as? String, "<js>lib()</js>")
        XCTAssertEqual(reencoded["concurrentRate"] as? String, "1/1000")
        XCTAssertEqual(reencoded["enabledCookieJar"] as? Bool, true)
        XCTAssertEqual(reencoded["ruleReview"] as? String, "class.review@text")
        // The passthrough container itself must never leak into the payload.
        XCTAssertNil(reencoded["extra"])
        // Declared fields still encode normally.
        XCTAssertEqual(reencoded["bookSourceName"] as? String, "示例源")
    }

    func testBookSourceWithoutExtrasEncodesNoExtraKey() throws {
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "干净源")
        let dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        XCTAssertNil(dict["extra"])
        XCTAssertTrue(dict["bookSourceUrl"] != nil)
    }

    func testTolerantDecodeCapturesExtras() throws {
        let data = json([
            "bookSourceUrl": "https://example.com",
            "jsLib": "lib"
        ])
        let decoded = TolerantJSON.decode(BookSource.self, from: data, fallback: BookSource(bookSourceUrl: "", bookSourceName: ""))
        XCTAssertEqual(decoded?.extra["jsLib"], JSONValue.string("lib"))
    }

    // MARK: - Book

    func testBookPreservesUnmodeledAndroidFields() throws {
        let data = json([
            "bookUrl": "https://example.com/book/1",
            "name": "书名",
            "author": "作者",
            "customTag": "玄幻",
            "customIntro": "简介",
            "charset": "gbk",
            "type": 0,
            "order": 3,
            "syncTime": 1_700_000_000_000
        ])

        let decoded = try XCTUnwrap(Book.decodeWithExtras(from: data))
        XCTAssertEqual(decoded.extra["customTag"], JSONValue.string("玄幻"))
        XCTAssertEqual(decoded.extra["charset"], JSONValue.string("gbk"))
        XCTAssertEqual(decoded.extra["type"], JSONValue.int(0))
        XCTAssertEqual(decoded.extra["order"], JSONValue.int(3))
        XCTAssertEqual(decoded.extra["syncTime"], JSONValue.int(1_700_000_000_000))

        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        XCTAssertEqual(reencoded["customTag"] as? String, "玄幻")
        XCTAssertEqual(reencoded["charset"] as? String, "gbk")
        XCTAssertEqual(reencoded["order"] as? Int, 3)
        XCTAssertEqual(reencoded["syncTime"] as? Int, 1_700_000_000_000)
        XCTAssertNil(reencoded["extra"])
    }

    // MARK: - RssSource

    func testRssSourceModelFieldsAndExtras() throws {
        let data = json([
            "sourceUrl": "https://sspai.com/feed",
            "sourceName": "少数派",
            "loginUrl": "https://sspai.com/login",
            "loginUi": "[{\"name\":\"账号\",\"type\":\"text\"}]",
            "variable": "{\"token\":\"abc\"}",
            "enabledCookieJar": true
        ])

        let decoded = try XCTUnwrap(RssSource.decodeWithExtras(from: data))
        // loginUrl / loginUi / variable are modeled Android parity fields now.
        XCTAssertEqual(decoded.loginUrl, "https://sspai.com/login")
        XCTAssertEqual(decoded.loginUi, "[{\"name\":\"账号\",\"type\":\"text\"}]")
        XCTAssertEqual(decoded.variable, "{\"token\":\"abc\"}")
        // enabledCookieJar stays an extra.
        XCTAssertEqual(decoded.extra["enabledCookieJar"], JSONValue.bool(true))

        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        XCTAssertEqual(reencoded["loginUrl"] as? String, "https://sspai.com/login")
        XCTAssertEqual(reencoded["enabledCookieJar"] as? Bool, true)
        XCTAssertNil(reencoded["extra"])
    }

    func testRssSourcePartialJSONDecodesWithDefaults() throws {
        let data = json(["sourceUrl": "https://example.com/feed"])
        let decoded = try XCTUnwrap(RssSource.decodeWithExtras(from: data))
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.articleStyle, 0)
        XCTAssertEqual(decoded.sourceName, "")
    }

    func testListRoundTripKeepsPerElementExtras() throws {
        let data = jsonArray([
            ["bookSourceUrl": "https://a.com", "bookSourceName": "A", "jsLib": "a-lib"],
            ["bookSourceUrl": "https://b.com", "bookSourceName": "B", "concurrentRate": "2/500"]
        ])
        let list = try XCTUnwrap(BookSource.decodeListWithExtras(from: data))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].extra["jsLib"], JSONValue.string("a-lib"))
        XCTAssertEqual(list[1].extra["concurrentRate"], JSONValue.string("2/500"))

        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as! [[String: Any]]
        XCTAssertEqual(reencoded[0]["jsLib"] as? String, "a-lib")
        XCTAssertEqual(reencoded[1]["concurrentRate"] as? String, "2/500")
    }

    func testDecodeListWithExtrasReturnsNilForNonArrayPayload() throws {
        let data = json(["bookSourceUrl": "https://a.com"])
        XCTAssertNil(BookSource.decodeListWithExtras(from: data))
        XCTAssertNotNil(BookSource.decodeListWithExtras(from: jsonArray([])))
    }
}

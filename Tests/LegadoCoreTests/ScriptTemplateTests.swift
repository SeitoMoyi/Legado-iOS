import XCTest
@testable import LegadoCore

final class ScriptTemplateTests: XCTestCase {
    private let payload = #"{"introductionZh":"正确的中文简介","introductionJp":"日本語の紹介","toc":[{"createAt":1700000000}],"syncAt":1600000000}"#

    func testIntroductionScriptInterpolatesTemplatesThenExecutes() {
        let rule = """
        <js>
        var value = String(book.getVariable("custom")) || String(source.getVariable());
        var data = JSON.parse(result);
        var intro = data.introductionZh || data.introductionJp;
        var timestamp = '{{$.toc[-1].createAt}}' || '{{$.syncAt}}';
        '📬最近更新：' + java.timeFormat(timestamp * 1000) + '\\n' + intro;
        </js>
        """
        let analyzer = RuleAnalyzer(content: payload)
        let intro = analyzer.getString(rule)
        XCTAssertTrue(intro.hasPrefix("📬最近更新：2023-11-"), intro)
        XCTAssertTrue(intro.hasSuffix("\n正确的中文简介"), intro)
        XCTAssertFalse(intro.contains("var value"))
        XCTAssertFalse(intro.contains("<js>"))
        XCTAssertFalse(intro.contains("{{"))
    }

    func testInlineScriptsAndListsInterpolateWithoutBecomingLiteralCode() {
        let analyzer = RuleAnalyzer(content: payload)
        XCTAssertEqual(analyzer.getString("@js:'{{$.introductionZh}}' + '！'"), "正确的中文简介！")
        XCTAssertEqual(analyzer.getStringList("<js>['{{$.introductionZh}}', '{{$.introductionJp}}']</js>"),
                       ["正确的中文简介", "日本語の紹介"])
        XCTAssertEqual(analyzer.getString("{{$.introductionZh}} / {{$.introductionJp}}"), "正确的中文简介 / 日本語の紹介")
    }

    func testInitCanReturnTransformedJsonTextAsDetailRoot() throws {
        let analyzer = RuleAnalyzer(content: #"{"payload":{"introductionZh":"根节点简介"}}"#)
        let root = try XCTUnwrap(analyzer.getElements("<js>JSON.stringify(JSON.parse(result).payload)</js>").first as? String)
        let detail = RuleAnalyzer(content: root, jsEngine: analyzer.jsEngine)
        XCTAssertEqual(detail.getString("$.introductionZh"), "根节点简介")
        XCTAssertEqual(detail.getString("<js>JSON.parse(result).introductionZh + '{{$.introductionZh}}'</js>"), "根节点简介根节点简介")
    }

    func testScriptErrorsAreNotRenderedAsIntroductionSourceCode() {
        let analyzer = RuleAnalyzer(content: payload)
        let intro = analyzer.getString("<js>throw new Error('{{$.introductionZh}}');</js>")
        XCTAssertEqual(intro, "")
    }
}

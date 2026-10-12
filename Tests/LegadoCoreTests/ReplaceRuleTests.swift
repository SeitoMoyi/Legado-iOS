import XCTest
@testable import LegadoCore

/// P0-5: 替换净化 rule model, scope matching, and the content pipeline.
final class ReplaceRuleTests: XCTestCase {

    private let bookName = "测试书名"
    private var defaults: UserDefaults!
    private let suiteName = "LegadoReplaceRuleTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        ContentProcessor.shared.rules = nil
        ContentProcessor.shared.onRuleAutoDisabled = nil
        super.tearDown()
    }

    private func rule(_ dictionary: [String: Any] = [:]) -> ReplaceRule {
        var base: [String: Any] = ["id": Int64(1), "name": "r", "pattern": "广告", "replacement": ""]
        for (k, v) in dictionary { base[k] = v }
        return ReplaceRule(
            id: base["id"] as? Int64 ?? 1,
            name: base["name"] as? String ?? "r",
            group: base["group"] as? String,
            pattern: base["pattern"] as? String ?? "广告",
            replacement: base["replacement"] as? String ?? "",
            scope: base["scope"] as? String,
            scopeTitle: base["scopeTitle"] as? Bool ?? false,
            scopeContent: base["scopeContent"] as? Bool ?? true,
            excludeScope: base["excludeScope"] as? String,
            isEnabled: base["isEnabled"] as? Bool ?? true,
            isRegex: base["isRegex"] as? Bool ?? true,
            timeoutMillisecond: base["timeoutMillisecond"] as? Int64 ?? 3000,
            order: base["order"] as? Int ?? 0
        )
    }

    // MARK: - Wire format

    func testRuleUsesAndroidJsonKeyNames() throws {
        let data = try JSONEncoder().encode([ReplaceRule(name: "去广告", group: "书源广告",
                                                         pattern: "广告", replacement: "x",
                                                         scope: "某书", excludeScope: "别书")])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let dict = try XCTUnwrap(array.first)
        for key in ["id", "name", "group", "pattern", "replacement", "scope", "scopeTitle",
                    "scopeContent", "excludeScope", "isEnabled", "isRegex",
                    "timeoutMillisecond", "order"] {
            XCTAssertTrue(dict.keys.contains(key), "missing \(key)")
        }
        // The DB column is sortOrder but GSON writes `order`; a rename silently breaks interop.
        XCTAssertFalse(dict.keys.contains("sortOrder"))
        XCTAssertFalse(dict.keys.contains("sortNumber"))

        // GSON omits nulls by default, so nil optionals must be absent here too.
        let sparse = try JSONEncoder().encode([ReplaceRule(name: "n", pattern: "p", replacement: "r")])
        let sparseDict = try XCTUnwrap((JSONSerialization.jsonObject(with: sparse) as? [[String: Any]])?.first)
        XCTAssertFalse(sparseDict.keys.contains("group"))
        XCTAssertFalse(sparseDict.keys.contains("scope"))
        XCTAssertFalse(sparseDict.keys.contains("excludeScope"))
    }

    func testDecodesAndroidPayloadWithMissingKeys() throws {
        let json = """
        [{"name":"净化A","pattern":"广告","replacement":"","isEnabled":true,"isRegex":false},
         {"name":"净化B","pattern":"x","replacement":"y","order":3,"timeoutMillisecond":-1}]
        """
        let rules = try XCTUnwrap(
            TolerantJSON.decodeList(ReplaceRule.self, from: Data(json.utf8), fallback: ReplaceRule()))
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].name, "净化A")
        XCTAssertFalse(rules[0].isRegex)
        XCTAssertEqual(rules[0].scopeContent, true, "Android default is scopeContent=true")
        XCTAssertEqual(rules[1].order, 3)
        XCTAssertEqual(rules[1].effectiveTimeout, 3000, "non-positive timeout normalises to 3000")
    }

    func testEffectiveTimeoutNormalisesZero() {
        XCTAssertEqual(ReplaceRule(timeoutMillisecond: 0).effectiveTimeout, 3000)
        XCTAssertEqual(ReplaceRule(timeoutMillisecond: -5).effectiveTimeout, 3000)
        XCTAssertEqual(ReplaceRule(timeoutMillisecond: 800).effectiveTimeout, 800)
    }

    func testIsValidMatchesAndroid() {
        XCTAssertFalse(ReplaceRule(pattern: "").isValid)
        XCTAssertFalse(ReplaceRule(pattern: "广告|").isValid, "trailing unescaped | is invalid")
        XCTAssertFalse(ReplaceRule(pattern: "([unclosed").isValid)
        XCTAssertTrue(ReplaceRule(pattern: "广告").isValid)
        // literal rules do not need to compile as a regex
        XCTAssertTrue(ReplaceRule(pattern: "([unclosed", isRegex: false).isValid)
    }

    func testStoreRoundTripAndImportMerge() throws {
        let rules = [ReplaceRule(id: 1, name: "a", order: 0), ReplaceRule(id: 2, name: "b", order: 1)]
        ReplaceRuleStore.save(rules, to: defaults)
        XCTAssertEqual(ReplaceRuleStore.load(from: defaults).map { $0.name }, ["a", "b"])

        // Import replaces same-id rules and appends new ones, then re-sorts by order.
        let payload = #"[{"id":2,"name":"b2","pattern":"x","replacement":"y","order":-1}]"#
        let merged = ReplaceRuleStore.importJSON(payload, into: rules)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.name, "b2", "order -1 must sort first")
        XCTAssertTrue(merged.contains { $0.name == "a" })
    }

    // MARK: - Scope matching (Android SQL LIKE semantics)

    private func matching(_ rules: [ReplaceRule], forTitle: Bool = false) -> [ReplaceRule] {
        ContentProcessor.matchingRules(bookName: bookName, bookOrigin: "https://src.test",
                                       from: rules, forTitle: forTitle)
    }

    func testScopeEmptyOrNullAppliesGlobally() {
        XCTAssertEqual(matching([rule()]).count, 1, "nil scope is global")
        XCTAssertEqual(matching([rule(["scope": ""])]).count, 1)
        XCTAssertEqual(matching([rule(["scope": bookName])]).count, 1)
        XCTAssertEqual(matching([rule(["scope": "https://src.test"]) ]).count, 1)
        XCTAssertEqual(matching([rule(["scope": "部分书名"])]).count, 0)
    }

    func testExcludeScopeWins() {
        XCTAssertEqual(matching([rule(["scope": "", "excludeScope": bookName])]).count, 0)
        XCTAssertEqual(matching([rule(["scope": "", "excludeScope": "https://src.test"]) ]).count, 0)
        XCTAssertEqual(matching([rule(["scope": "", "excludeScope": "别的书"]) ]).count, 1)
        // An empty excludeScope behaves like no exclusion (SQL LIKE '%%' against '' is false)
        XCTAssertEqual(matching([rule(["scope": "", "excludeScope": ""])]).count, 1)
    }

    func testDisabledAndWrongScopeTypeAreSkipped() {
        XCTAssertEqual(matching([rule(["isEnabled": false])]).count, 0)
        XCTAssertEqual(matching([rule(["scopeContent": false])]).count, 0)
        XCTAssertEqual(matching([rule(["scopeTitle": true, "scopeContent": false])], forTitle: true).count, 1)
        XCTAssertEqual(matching([rule(["scopeTitle": false])], forTitle: true).count, 0)
    }

    func testRulesSortedByOrder() {
        let sorted = matching([rule(["id": Int64(1), "name": "z", "order": 9]),
                               rule(["id": Int64(2), "name": "a", "order": -3])])
        XCTAssertEqual(sorted.map { $0.name }, ["a", "z"])
    }

    // MARK: - Rule application

    func testRegexRuleWithGroupTemplate() {
        let outcome = ContentProcessor.applyRuleSync(
            ReplaceRule(pattern: "第(\\d+)章", replacement: "Chapter $1"), to: "第12章 开始")
        guard case .changed(let text) = outcome else { return XCTFail("expected change") }
        XCTAssertEqual(text, "Chapter 12 开始")
    }

    func testLiteralRule() {
        let outcome = ContentProcessor.applyRuleSync(
            ReplaceRule(pattern: "本网站", replacement: "", isRegex: false), to: "正文 本网站 结尾")
        guard case .changed(let text) = outcome else { return XCTFail("expected change") }
        XCTAssertEqual(text, "正文  结尾")
    }

    func testUnchangedProducesUnchanged() {
        if case .unchanged = ContentProcessor.applyRuleSync(ReplaceRule(pattern: "不存在", replacement: "x"), to: "abc") {
            return
        }
        XCTFail("expected .unchanged")
    }

    func testInvalidRegexFailsWithoutThrowing() {
        if case .failed = ContentProcessor.applyRuleSync(ReplaceRule(pattern: "([unclosed"), to: "abc") {
            return
        }
        XCTFail("expected .failed")
    }

    func testJsReplacementIsEvaluatedPerMatch() {
        let outcome = ContentProcessor.applyRuleSync(
            ReplaceRule(pattern: "(\\d+)", replacement: "@js:result + '元'"), to: "价格 5 和 12")
        guard case .changed(let text) = outcome else { return XCTFail("expected change, got \(outcome)") }
        XCTAssertTrue(text.contains("5元") && text.contains("12元"), text)
    }

    func testImageStyles() {
        let content = "前\n[image:https://a/1.png]\n中\n[image:https://a/2.png]\n后"
        XCTAssertEqual(ContentProcessor.shared.applyImageStyle(content, .textOnly)
                        .components(separatedBy: "\n").filter { $0.hasPrefix("[image") }.count, 0)
        let single = ContentProcessor.shared.applyImageStyle(content, .singleImage)
        XCTAssertEqual(single.components(separatedBy: "\n").filter { $0.hasPrefix("[image") }.count, 1)
        XCTAssertTrue(ContentProcessor.shared.applyImageStyle(content, .standard).contains("2.png"))
    }

    // MARK: - Full pipeline

    private func context(rules: [ReplaceRule] = [], indent: String = "　　",
                         converter: Int = 0, useReplace: Bool = true) -> ProcessContext {
        ContentProcessor.shared.rules = rules
        var style = ReadStyleConfig()
        style.paragraphIndent = indent
        var prefs = ReaderPrefs()
        prefs.chineseConverterType = converter
        return ProcessContext(bookName: bookName, bookOrigin: "https://src.test",
                              chapterTitle: "第一章 起点", useReplaceRule: useReplace,
                              style: style, prefs: prefs)
    }

    func testRemovesDuplicatedTitleAndReindentsBody() async {
        let raw = "第一章 起点\n　　已有缩进的段落\n新的段落\n\n\n"
        let processed = await ContentProcessor.shared.process(rawContent: raw, context: context())

        XCTAssertEqual(processed.title, "第一章 起点")
        XCTAssertTrue(processed.sameTitleRemoved)
        // Android trims each line then re-adds the configured indent — exactly one, never two.
        XCTAssertEqual(processed.lines.first, "第一章 起点")
        XCTAssertEqual(processed.lines.count, 3)
        XCTAssertEqual(processed.lines[1], "　　已有缩进的段落")
        XCTAssertEqual(processed.lines[2], "　　新的段落")
        XCTAssertEqual(processed.bodyText, "　　已有缩进的段落\n　　新的段落")
    }

    func testTitleWithSpacesMatchesContentWithoutThem() async {
        let ctx = ProcessContext(bookName: bookName, bookOrigin: "https://src.test",
                                 chapterTitle: "第一章   起点", useReplaceRule: true,
                                 style: ReadStyleConfig(), prefs: ReaderPrefs())
        ContentProcessor.shared.rules = []
        let processed = await ContentProcessor.shared.process(
            rawContent: "第一章 起点\n正文一", context: ctx)
        XCTAssertTrue(processed.sameTitleRemoved, "whitespace runs must match loosely")
        XCTAssertEqual(processed.lines.count, 2)
    }

    func testRuleAppliedAndReportedAsEffective() async {
        let ctx = context(rules: [rule(["pattern": "广告.*", "replacement": "", "order": 0])])
        let processed = await ContentProcessor.shared.process(
            rawContent: "正文\n广告来了\n结尾", context: ctx)
        XCTAssertEqual(processed.effectiveRules.count, 1)
        XCTAssertFalse(processed.bodyText.contains("广告"))
    }

    func testRuleThatChangesNothingIsNotEffective() async {
        let ctx = context(rules: [rule(["pattern": "根本不存在", "replacement": "x"])])
        let processed = await ContentProcessor.shared.process(rawContent: "正文", context: ctx)
        XCTAssertTrue(processed.effectiveRules.isEmpty)
    }

    func testUseReplaceOffDisablesRulesButKeepsIndent() async {
        let ctx = context(rules: [rule(["pattern": "广告", "replacement": "X"])], useReplace: false)
        let processed = await ContentProcessor.shared.process(rawContent: "第一章 起点\n广告", context: ctx)
        XCTAssertTrue(processed.bodyText.contains("广告"))
        XCTAssertEqual(processed.lines[1], "　　广告", "indent is a style concern, not a rule one")
    }

    func testBookLevelOverrideWinsOverDefault() async {
        var prefs = ReaderPrefs()
        prefs.replaceEnableDefault = true
        ContentProcessor.shared.rules = [rule(["pattern": "广告", "replacement": "X"])]
        let ctx = ProcessContext(bookName: bookName, bookOrigin: "https://src.test",
                                 chapterTitle: "t", useReplaceRule: false,
                                 style: ReadStyleConfig(), prefs: prefs)
        let processed = await ContentProcessor.shared.process(rawContent: "广告", context: ctx)
        XCTAssertTrue(processed.bodyText.contains("广告"))
    }

    func testNonBreakingSpaceBecomesNormalSpace() async {
        ContentProcessor.shared.rules = []
        let processed = await ContentProcessor.shared.process(
            rawContent: "第一章 起点\n正文\u{00A0}继续", context: context())
        XCTAssertFalse(processed.bodyText.contains("\u{00A0}"))
        XCTAssertTrue(processed.bodyText.contains("正文 继续"))
    }

    func testNoIndentOption() async {
        let ctx = context(indent: "")
        let processed = await ContentProcessor.shared.process(rawContent: "第一章 起点\n段落", context: ctx)
        XCTAssertEqual(processed.lines[1], "段落")
    }

    func testTraditionalToSimpleAppliedInPipeline() async {
        ContentProcessor.shared.rules = []
        let ctx = context(converter: ChineseConverterMode.traditionalToSimple)
        let processed = await ContentProcessor.shared.process(
            rawContent: "第一章 起点\n開源閱讀軟件", context: ctx)
        XCTAssertTrue(processed.bodyText.contains("开源阅读软件"), processed.bodyText)
    }

    func testTimeoutDisablesRuleAndDiscardsItsResult() async {
        let heavy = String(repeating: "a", count: 1_000_000)
        let bomb = ReplaceRule(id: 77, name: "炸弹", pattern: "aa", replacement: "b",
                               isEnabled: true, isRegex: true, timeoutMillisecond: 1)
        ContentProcessor.shared.rules = [bomb]
        var disabled: [ReplaceRule] = []
        ContentProcessor.shared.onRuleAutoDisabled = { disabled.append($0) }

        let ctx = ProcessContext(bookName: bookName, bookOrigin: "https://src.test",
                                 chapterTitle: "t", useReplaceRule: true,
                                 style: ReadStyleConfig(), prefs: ReaderPrefs())
        let processed = await ContentProcessor.shared.process(rawContent: heavy, context: ctx)

        XCTAssertEqual(disabled.map { $0.id }, [77], "timed-out rule must report itself for disabling")
        XCTAssertTrue(processed.effectiveRules.isEmpty, "a timed-out result must not leak into text")
    }

    func testEmptyContentIsHandled() async {
        ContentProcessor.shared.rules = []
        let processed = await ContentProcessor.shared.process(rawContent: "", context: context())
        XCTAssertEqual(processed.text, "第一章 起点")
        XCTAssertTrue(processed.bodyText.isEmpty)
    }

    func testGarbageSentinelIsHandled() async {
        ContentProcessor.shared.rules = []
        let processed = await ContentProcessor.shared.process(rawContent: "null", context: context())
        XCTAssertEqual(processed.bodyText, "")
    }
}

/// P0-5 simplified/traditional conversion via the system transform.
final class ChineseConverterTests: XCTestCase {

    func testModeOffIsIdentity() {
        XCTAssertEqual(ChineseConverter.convert("開源閱讀", mode: 0), "開源閱讀")
    }

    func testTraditionalToSimple() {
        XCTAssertEqual(ChineseConverter.convert("開源閱讀軟件", mode: 1), "开源阅读软件")
    }

    func testSimpleToTraditional() {
        XCTAssertEqual(ChineseConverter.convert("开源阅读软件", mode: 2), "開源閱讀軟件")
    }

    /// Android loads an exclusion list so region-specific words are not "corrected".
    /// Spot-check the words from that list survive the system transform unchanged.
    func testExcludedWordsStayUnchangedInTraditionalToSimple() {
        let traditional = "列印函式硬碟介面"
        XCTAssertEqual(ChineseConverter.convert(traditional, mode: 1), traditional)
    }

    func testAsciiAndEmptyPassThrough() {
        XCTAssertEqual(ChineseConverter.convert("hello 123", mode: 1), "hello 123")
        XCTAssertEqual(ChineseConverter.convert("", mode: 2), "")
    }
}

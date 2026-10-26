import XCTest
@testable import LegadoCore

final class DirectoryRuleTests: XCTestCase {
    func testMetadataAndLinklessVolumesUseAndroidTruthSemantics() throws {
        let content = #"{"chapters":[{"name":"第一卷","volume":"卷","vip":"NO","pay":"0","time":"卷简介"},{"name":"第一章","url":"/one","volume":"false","vip":"VIP","pay":"yes","time":"2026-10-26"}]}"#
        let rule = TocRule(chapterList: "$.chapters[*]", chapterName: "$.name", chapterUrl: "$.url",
                           isVolume: "$.volume", isVip: "$.vip", isPay: "$.pay", updateTime: "$.time")
        let analyzer = RuleAnalyzer(content: content, baseUrl: "https://directory.test/toc")
        let chapters = BookContentService.parseChapters(from: analyzer, tocRule: rule, bookUrl: "book", jsEngine: analyzer.jsEngine)
        XCTAssertEqual(chapters.count, 2)
        let volume = try XCTUnwrap(chapters.first)
        XCTAssertEqual(volume.isVolume, true)
        XCTAssertEqual(volume.isVip, false)
        XCTAssertEqual(volume.isPay, false)
        XCTAssertEqual(volume.tag, "卷简介")
        XCTAssertTrue(volume.url.hasPrefix("legado-volume://"))
        XCTAssertEqual(chapters.last?.url, "https://directory.test/one")
        XCTAssertEqual(chapters.last?.isVolume, false)
        XCTAssertEqual(chapters.last?.isVip, true)
        XCTAssertEqual(chapters.last?.isPay, true)
        XCTAssertEqual(chapters.last?.tag, "2026-10-26")
    }

    func testFlagValuesMatchAndroidStringIsTrue() {
        for value in ["", " \n", "null", "false", "FALSE", " No ", "not", "0"] {
            XCTAssertFalse(BookContentService.ruleIsTrue(value), value)
        }
        for value in ["true", "1", "VIP", "付费", "2"] {
            XCTAssertTrue(BookContentService.ruleIsTrue(value), value)
        }
    }

    func testVolumeIdentifiersAreStableAndDistinctAcrossPages() {
        func volume(_ base: String) -> BookChapter? {
            let analyzer = RuleAnalyzer(content: "<h2>卷</h2>", baseUrl: base)
            return BookContentService.parseChapters(from: analyzer,
                tocRule: TocRule(chapterList: "h2", chapterName: "text", isVolume: "@js:true"),
                bookUrl: "book", jsEngine: analyzer.jsEngine).first
        }
        XCTAssertNotNil(volume("https://directory.test/1"))
        XCTAssertEqual(volume("https://directory.test/1")?.url, volume("https://directory.test/1")?.url)
        XCTAssertNotEqual(volume("https://directory.test/1")?.url, volume("https://directory.test/2")?.url)
    }

    func testFormattingUsesSharedCounterAndChapterMetadata() throws {
        let chapters = [
            BookChapter(bookUrl: "book", url: "one", title: "卷", index: 0, isVolume: true),
            BookChapter(bookUrl: "book", url: "two", title: "章", index: 1, isVip: true, isPay: true, tag: "今天")
        ]
        let formatted = try BookContentService.formatChapters(chapters,
            script: "gInt++; index + ':' + gInt + ':' + chapter.index + ':' + title + ':' + (chapter.isVolume ? '卷' : chapter.tag)")
        XCTAssertEqual(formatted.map(\.title), ["1:1:0:卷:卷", "2:2:1:章:今天"])
        XCTAssertEqual(formatted.map(\.url), chapters.map(\.url))
        XCTAssertEqual(formatted.last?.isPay, true)
        // Each directory refresh starts a new shared counter.
        XCTAssertEqual(try BookContentService.formatChapters(chapters, script: "++gInt").map(\.title), ["1", "2"])
    }

    func testFormattingExceptionPreservesTitleAndContinues() throws {
        let chapters = (0..<3).map { BookChapter(bookUrl: "book", url: "\($0)", title: "原\($0)", index: $0) }
        let formatted = try BookContentService.formatChapters(chapters,
            script: "if(index === 2) throw new Error('bad title'); title + '!'")
        XCTAssertEqual(formatted.map(\.title), ["原0!", "原1", "原2!"])
        XCTAssertEqual(try BookContentService.formatChapters(chapters, script: "null"), chapters)
        XCTAssertEqual(try BookContentService.formatChapters(chapters, script: "undefined"), chapters)
        XCTAssertEqual(try BookContentService.formatChapters(chapters, script: "<js>title + index</js>").first?.title, "原01")
    }

    func testOldDirectoryCachesDecodeWithoutNewFlags() throws {
        let data = Data(#"[{"bookUrl":"b","url":"u","title":"章","index":0}]"#.utf8)
        let chapter = try XCTUnwrap(JSONDecoder().decode([BookChapter].self, from: data).first)
        XCTAssertNil(chapter.isVolume)
        XCTAssertNil(chapter.isPay)
        let updated = BookChapter(bookUrl: "b", url: "u", title: "卷", index: 0, isVip: true, isVolume: true, isPay: true, tag: "时间")
        XCTAssertEqual(try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(updated)), updated)
    }

    func testCancelledFormattingDoesNotExecuteScript() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BookContentService.formatChapters([BookChapter(bookUrl: "b", url: "u", title: "章", index: 0)], script: "title")
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled directory formatting should throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

extension DirectoryRuleTests {
    func testHtmlNodesAreConvertedToHtmlForScalarAndListScripts() throws {
        let analyzer = RuleAnalyzer(content: "<h2>卷一</h2><h2>卷二</h2>", baseUrl: "https://directory.test")
        let item = try XCTUnwrap(analyzer.getElements("h2").first)
        let child = RuleAnalyzer(content: item)
        XCTAssertEqual(child.getString("@js:result.indexOf('卷一') >= 0"), "true")
        let names = analyzer.getElements("h2<js>result.map(function(html) { return {html: html}; })</js>")
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue((names.first as? [String: Any])?["html"] as? String == "<h2>卷一</h2>")
    }

    func testMetadataScriptsCanReadCurrentChapter() throws {
        let analyzer = RuleAnalyzer(content: #"{"items":[{"name":"VIP章","url":"/one"},{"name":"普通章","url":"/two"}]}"#,
                                    baseUrl: "https://directory.test/toc")
        let chapters = BookContentService.parseChapters(from: analyzer, tocRule: TocRule(
            chapterList: "$.items[*]", chapterName: "$.name", chapterUrl: "$.url",
            isVip: "@js:chapter.title.indexOf('VIP') >= 0", isPay: "@js:chapter.isVip",
            updateTime: "@js:chapter.title + ':' + chapter.url"), bookUrl: "book", jsEngine: analyzer.jsEngine)
        XCTAssertEqual(chapters.map(\.isVip), [true, false])
        XCTAssertEqual(chapters.map(\.isPay), [true, false])
        XCTAssertEqual(chapters.first?.tag, "VIP章:/one")
    }
}

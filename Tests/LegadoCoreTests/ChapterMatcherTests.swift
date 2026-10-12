import XCTest
@testable import LegadoCore

/// P0-4: the progress-mapping rule used by 换源. A wrong answer here does not crash, it just
/// silently drops the reader into the wrong chapter, so the branches are pinned explicitly.
final class ChapterMatcherTests: XCTestCase {

    private func titles(_ count: Int, prefix: String = "第", suffix: String = "章") -> [String] {
        (1...count).map { "\(prefix)\($0)\(suffix)" }
    }

    // MARK: - Chinese numerals

    func testChineseNumberParsing() {
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("一"), 1)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("十"), 10)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("十五"), 15)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("二十一"), 21)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("一百零五"), 105)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("一千二百三十四"), 1_234)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("一万二千"), 12_000)
        XCTAssertEqual(ChapterMatcher.chineseNumberToInt("叁"), 3)
        XCTAssertNil(ChapterMatcher.chineseNumberToInt(" abc "))
        XCTAssertNil(ChapterMatcher.chineseNumberToInt(""))
    }

    func testChapterNumberExtraction() {
        XCTAssertEqual(ChapterMatcher.chapterNumber(in: "第123章 开始"), 123)
        XCTAssertEqual(ChapterMatcher.chapterNumber(in: "第 九百九十九 章"), 999)
        XCTAssertEqual(ChapterMatcher.chapterNumber(in: "042 意外的发现"), 42)
        XCTAssertEqual(ChapterMatcher.chapterNumber(in: "第三回 宴桃园"), 3)
        XCTAssertEqual(ChapterMatcher.chapterNumber(in: "楔子"), nil)
        // Full-width digits are folded before matching.
        XCTAssertEqual(ChapterMatcher.chapterNumber(in: "第１２３章"), 123)
    }

    func testPureChapterNameIgnoresPunctuationAndSpaces() {
        XCTAssertEqual(ChapterMatcher.pureChapterName("第 1 章：开始！"), "第1章开始")
        XCTAssertEqual(ChapterMatcher.jaccardSimilarity("第1章开始", "第1章开始"), 1.0)
    }

    // MARK: - mapChapter branches

    func testFirstChapterAlwaysMapsToZero() {
        XCTAssertEqual(ChapterMatcher.mapChapter(oldIndex: 0, oldTitle: "第一章", oldCount: 100,
                                                 newTitles: titles(50)), 0)
    }

    func testEmptyNewTocKeepsOldIndex() {
        XCTAssertEqual(ChapterMatcher.mapChapter(oldIndex: 12, oldTitle: "第十二章", oldCount: 100,
                                                 newTitles: []), 12)
    }

    func testIdenticalTocMapsToTheSameIndex() {
        let list = titles(200)
        XCTAssertEqual(ChapterMatcher.mapChapter(oldIndex: 120, oldTitle: list[120], oldCount: 200,
                                                newTitles: list), 120)
    }

    func testGrewByInsertedChaptersMatchesByTitle() {
        // 200 chapters, the new source has one extra chapter inserted early on.
        var list = titles(200)
        list.insert("序章", at: 3)
        let oldIndex = 150
        let mapped = ChapterMatcher.mapChapter(oldIndex: oldIndex, oldTitle: titles(200)[oldIndex],
                                               oldCount: 200, newTitles: list)
        XCTAssertEqual(mapped, 151, "title match must land one past the insertion")
        XCTAssertEqual(list[mapped], "第151章")
    }

    func testMildlyShrunkTocMatchesByTitle() {
        var dense = titles(200)
        let removed = 5
        for _ in 0..<removed { dense.remove(at: 100) }
        let oldTitle = dense[120]
        let mapped = ChapterMatcher.mapChapter(oldIndex: 120 + removed, oldTitle: oldTitle,
                                              oldCount: 200, newTitles: dense)
        XCTAssertEqual(dense[mapped], oldTitle)
    }

    func testHeavilyShrunkTocFallsBackToTheProportionalWindow() {
        // Only ±10 indices around the proportional guess are searched, so a source that
        // dropped half its chapters cannot be title-matched. Android behaves the same; the
        // result must simply stay in range and near the guess.
        let dense = titles(300)
        let sparse = stride(from: 0, to: 300, by: 2).map { dense[$0] }
        let mapped = ChapterMatcher.mapChapter(oldIndex: 200, oldTitle: dense[200], oldCount: 300,
                                               newTitles: sparse)
        XCTAssertTrue((139...149).contains(mapped), "got \(mapped)")
        XCTAssertEqual(mapped, sparse.count - 1, "clamps to the last chapter of the short list")
    }

    func testChapterNumberRescuesRewrittenTitles() {
        let old = "第88章 风起"
        let newTitles = (1...100).map { "chapter_\($0)" }
        let mapped = ChapterMatcher.mapChapter(oldIndex: 87, oldTitle: old, oldCount: 100,
                                              newTitles: newTitles)
        // "chapter_N" carries no number, so the proportional estimate has to win.
        XCTAssertTrue((80...95).contains(mapped), "got \(mapped)")
    }

    func testChapterNumberMatchesWhenSimilarityIsLow() {
        let oldTitles = (1...100).map { "第\($0)章 老标题" }
        let newTitles = (1...100).map { "第\($0)章完全不同的标题内容啊" }
        let mapped = ChapterMatcher.mapChapter(oldIndex: 60, oldTitle: oldTitles[60], oldCount: 100,
                                              newTitles: newTitles)
        XCTAssertEqual(mapped, 60)
    }

    func testVolumeDividersAreSkippedByTitleMatching() {
        let newTitles = ["第一卷 风起", "第1章 开始", "第2章 转折", "第2卷 云涌", "第3章 结局"]
        let mapped = ChapterMatcher.mapChapter(oldIndex: 2, oldTitle: "第3章 结局", oldCount: 3,
                                              newTitles: newTitles)
        XCTAssertEqual(newTitles[mapped], "第3章 结局")
    }

    func testCompletelyDifferentTocClampsOldIndex() {
        let newTitles = ["无编号甲", "无编号乙", "无编号丙", "无编号丁"]
        let mapped = ChapterMatcher.mapChapter(oldIndex: 500, oldTitle: "第500章", oldCount: 600,
                                              newTitles: newTitles)
        XCTAssertEqual(mapped, 3, "must clamp into range rather than run off the end")
    }

    func testResultIsAlwaysInRange() {
        let cases: [(Int, String, Int, Int)] = [
            (0, "第一章", 1, 5), (9, "第九章", 10, 3), (500, "第500章", 900, 20),
            (3, "第三章", 5, 1), (1, "第一章", 2, 100)
        ]
        for (oldIndex, oldTitle, oldCount, newSize) in cases {
            let mapped = ChapterMatcher.mapChapter(oldIndex: oldIndex, oldTitle: oldTitle,
                                                  oldCount: oldCount, newTitles: titles(newSize))
            XCTAssertTrue((0..<newSize).contains(mapped),
                          "oldIndex=\(oldIndex) newSize=\(newSize) mapped=\(mapped)")
        }
    }
}

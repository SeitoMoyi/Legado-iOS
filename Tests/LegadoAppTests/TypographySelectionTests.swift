import XCTest
#if canImport(LegadoCore)
import LegadoCore
#endif
@testable import LegadoApp

/// Part 4 文本选词联动的几何锁：触点 → 章内字符偏移 → 选中高亮矩形必须与排版行一致。
/// 全部跑在 macOS CoreText 上（与 iOS 同一套 CT API），无需真机。
final class TypographySelectionTests: XCTestCase {

    private let chapter = BookChapter(bookUrl: "https://test.example/b", url: "https://test.example/c/1",
                                      title: "第一话 试探", index: 1)

    private func typeset(paragraphs: [String], charsPerLine: Int = 6) -> ChapterTypography {
        let content = paragraphs.joined(separator: "\n")
        return TypographyEngine.typeset(
            chapter: chapter,
            content: content,
            containerWidth: CGFloat(charsPerLine * 20) + 20,
            containerHeight: 300,
            fontSize: 20,
            lineSpacing: 0,
            letterSpacing: 0,
            paragraphSpacing: 12,
            paddingLeading: 10,
            paddingTrailing: 10,
            paddingTop: 50,
            paddingBottom: 50,
            imageStyle: .textOnly,
            justify: false
        )
    }

    func testCharIndexAtLineMidpointLandsInsideThatLine() {
        let paragraphs = ["一二三四五六七八九十甲乙丙丁", "子丑寅卯辰巳午未申酉戌亥"]
        let typo = typeset(paragraphs: paragraphs)

        guard let firstLine = typo.lines.first else {
            return XCTFail("排版应产生正文行")
        }

        // 行垂直中点、行首 x → 应命中该行 charRange 内（或精确等于行首偏移）。
        let probeY = firstLine.y + firstLine.height / 2
        let offset = typo.charIndex(atX: 2, y: probeY,
                                    fontSize: 20, letterSpacing: 0)
        XCTAssertNotNil(offset)
        XCTAssertTrue(firstLine.charRange.contains(offset!),
                      "触点应命中行 \(firstLine.charRange)，实际 \(offset!)")
    }

    func testCharIndexBelowLastLineClampsToTrailingLine() {
        let typo = typeset(paragraphs: ["一二三四五六七八九十甲乙"])
        guard let last = typo.lines.last else { return XCTFail("应有正文行") }

        let belowY = last.y + last.height * 3
        let offset = typo.charIndex(atX: 2, y: belowY, fontSize: 20, letterSpacing: 0)
        XCTAssertNotNil(offset)
        XCTAssertGreaterThanOrEqual(offset!, last.charRange.lowerBound,
                                    "行下方的触点应收敛到最后一行而不是丢失")
    }

    func testSelectionRectsSpanEveryCoveredLine() {
        let paragraphs = ["一二三四五六七八九十甲乙丙丁戊己庚辛", "壬癸子丑"]
        let typo = typeset(paragraphs: paragraphs)
        // 跨两段的范围：第一段的 3..8 与第二段开头两字。
        guard typo.lines.count >= 2 else { return XCTFail("语料应至少两行") }
        let start = typo.lines[0].charRange.lowerBound + 3
        let end = typo.lines.last!.charRange.lowerBound + 2
        let range = start..<end

        let rects = typo.selectionRects(for: range, paddingLeading: 10,
                                        fontSize: 20, letterSpacing: 0)
        XCTAssertFalse(rects.isEmpty)

        // 每个矩形都应落在某条覆盖行的纵向范围内。
        for rect in rects {
            let covering = typo.lines.contains { line in
                range.overlaps(line.charRange) &&
                abs(rect.minY - line.y) < 0.6 &&
                abs(rect.height - line.height) < 0.6
            }
            XCTAssertTrue(covering, "矩形 \(rect) 不在任何覆盖行上")
        }

        // x 单调：起点矩形不得落后于行首。
        if let firstRect = rects.first {
            XCTAssertGreaterThanOrEqual(firstRect.minX, 10 - 0.6)
            XCTAssertGreaterThan(firstRect.width, 0.5)
        }
    }

    func testWordRangeExpandsLatinAndIsolatesCJK() {
        let latin = "abc def"
        XCTAssertEqual(SelectionGeometry.wordRange(in: latin, index: 0), 0..<3)
        XCTAssertEqual(SelectionGeometry.wordRange(in: latin, index: 2), 0..<3)
        XCTAssertEqual(SelectionGeometry.wordRange(in: latin, index: 5), 4..<7)
        // 空格与 CJK 单字自选
        XCTAssertEqual(SelectionGeometry.wordRange(in: latin, index: 3), 3..<4)
        XCTAssertEqual(SelectionGeometry.wordRange(in: "玄幻小说", index: 2), 2..<3)
    }

    func testParagraphStartOffsetFindsParagraphHead() {
        let typo = typeset(paragraphs: ["一二三四五六七八九十甲乙丙丁", "子丑寅卯"])
        guard typo.lines.count > 1 else { return XCTFail("应有续行") }
        let secondLine = typo.lines[1]
        let start = typo.paragraphStartOffset(of: secondLine)
        // 行 1 与行 0 同段（长段续行），段落起点应为第一行行首偏移 0。
        if secondLine.paragraphText == typo.lines[0].paragraphText {
            XCTAssertEqual(start, typo.lines[0].charRange.lowerBound)
        } else {
            XCTAssertEqual(start, secondLine.charRange.lowerBound)
        }
    }

    func testSelectionRectsRejectEmptyRange() {
        let typo = typeset(paragraphs: ["一二三"])
        XCTAssertTrue(typo.selectionRects(for: 0..<0, paddingLeading: 10,
                                          fontSize: 20, letterSpacing: 0).isEmpty)
    }
}

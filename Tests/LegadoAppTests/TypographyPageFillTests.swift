import XCTest
#if canImport(LegadoCore)
import LegadoCore
#endif
@testable import LegadoApp

/// 翻页模式分页不变量（Plan §13 段距记账修复的回归锁）：
///
/// 除末页外，若某页的下一行是**段内续行**（不是新段首行），则该页的已用高度 + 续行行高
/// 必须超出页容量——即“放得下下一行就绝不允许换页”。旧实现把段距记在段尾行上，段尾行
/// 字形本可容纳却被整行推到下一页，页底留下整行空白（用户报告的“强行提前分割”）。
final class TypographyPageFillTests: XCTestCase {

    private let chapter = BookChapter(bookUrl: "https://test.example/b", url: "https://test.example/c/1",
                                      title: "第一话 试探", index: 1)

    private func typeset(paragraphCharCounts: [Int], charsPerLine: Int = 5) -> ChapterTypography {
        let content = paragraphCharCounts
            .map { String(repeating: "夜", count: $0) }
            .joined(separator: "\n")
        return TypographyEngine.typeset(
            chapter: chapter,
            content: content,
            containerWidth: CGFloat(charsPerLine * 20) + 20, // +2×10 左右边距
            containerHeight: 200,
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

    /// 渲染基准的页内已用高度：行数 × 行高 + 页内（非页末行）段尾之后的段距。
    private func usedHeight(of range: Range<Int>, in typo: ChapterTypography,
                            lineHeight: CGFloat, paragraphGap: CGFloat) -> CGFloat {
        guard range.lowerBound < range.upperBound else { return 0 }
        let slice = typo.lines[range]
        var height = CGFloat(slice.count) * lineHeight
        for line in slice.dropLast() where line.isParagraphEnd {
            height += paragraphGap
        }
        return height
    }

    func testNoPrematureBreakBeforeContinuationLines() {
        // 混合段长命中不同的页内填充位置（3+3+2+6+3=17 行）
        let typo = typeset(paragraphCharCounts: [12, 13, 7, 30, 11])
        let lineHeight = CGFloat(20 * 1.25) // fontSize 20, lineSpacing 0
        let paragraphGap: CGFloat = 12
        let pageCapacity = CGFloat(100) // 200 − 2×50

        XCTAssertGreaterThan(typo.pages.count, 1, "语料应跨多页，否则测试无效")

        // 每页容量：P0 扣除标题（firstPageCapacity 有 max(100) 下限），其余整页 180
        let usablePageHeight: CGFloat = 180
        let firstPageCapacity = max(100, usablePageHeight - typo.titleTotalHeight)

        for pageIndex in 0..<(typo.pages.count - 1) {
            guard let range = typo.lineRange(ofPage: pageIndex) else { continue }
            let nextLine = typo.lines[range.upperBound]
            let cap = pageIndex == 0 ? firstPageCapacity : usablePageHeight

            // 被换开的行若是段内续行：该页必须连行高本身都放不下
            let isParagraphStart = typo.lines[range.upperBound - 1].isParagraphEnd
            if !isParagraphStart {
                let used = usedHeight(of: range, in: typo, lineHeight: lineHeight, paragraphGap: paragraphGap)
                XCTAssertGreaterThan(
                    used + lineHeight, cap,
                    "第 \(pageIndex) 页在仍放得下续行时提前换页（used=\(used)，页底留白 = \(cap - used)）"
                )
            }
        }
    }

    func testLastLineOfParagraphIsNotPushedByTrailingGap() {
        // 单段 60 字（12 行）：任何被换开的行都必须是真放不下，段距不得制造提前分割。
        let typo = typeset(paragraphCharCounts: [60])
        let lineHeight = CGFloat(20 * 1.25)
        let paragraphGap: CGFloat = 12
        let pageCapacity = CGFloat(180)

        let usablePageHeight: CGFloat = 180
        let firstPageCapacity = max(100, usablePageHeight - typo.titleTotalHeight)

        for pageIndex in 0..<(typo.pages.count - 1) {
            guard let range = typo.lineRange(ofPage: pageIndex),
                  let nextRange = typo.lineRange(ofPage: pageIndex + 1) else { continue }
            // 合法性判定：被换开的行若是段内续行，该页连其行高都放不下；
            // 若是段首行，该页连 行高+段距 都放不下（页首行不收段距，跨页后段距重置）。
            let pushedLine = typo.lines[nextRange.lowerBound]
            let isParagraphStart = typo.lines[range.upperBound - 1].isParagraphEnd
            let cap = pageIndex == 0 ? firstPageCapacity : usablePageHeight
            let used = usedHeight(of: range, in: typo, lineHeight: lineHeight, paragraphGap: paragraphGap)
            let required = isParagraphStart ? used + paragraphGap + lineHeight : used + lineHeight
            XCTAssertGreaterThan(
                required, cap,
                "第 \(pageIndex) 页过早换页：used=\(used)，被推行=行\(pushedLine.index)（段首=\(isParagraphStart)）"
            )
        }
    }
}

import XCTest
import CoreText
#if canImport(LegadoCore)
import LegadoCore
#endif
@testable import LegadoApp

final class ChapterTitleRenderingTests: XCTestCase {
    func testChapter63UsesTwoMeasuredAndDrawnTitleLines() throws {
        let chapter = BookChapter(bookUrl: "book", url: "chapter63",
            title: "第63话　现代奇幻吗？　不，是恋爱喜剧", index: 67)
        let typography = TypographyEngine.typeset(
            chapter: chapter, content: "正文", containerWidth: 414, containerHeight: 800,
            fontSize: 17, lineSpacing: 12, letterSpacing: 0, paragraphSpacing: 4,
            paddingLeading: 24, paddingTrailing: 24, paddingTop: 24, paddingBottom: 24,
            imageStyle: .textOnly, justify: true)
        XCTAssertEqual(typography.titleLines.count, 2)
        XCTAssertEqual(typography.titleLines.joined(), chapter.title)
        let width = 366, height = Int(ceil(typography.titleTotalHeight))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        CoreTextPageRenderer.draw(
            ctx: context, lines: typography.titleLines, isParagraphEnd: [true, true],
            fontSize: 21, lineSpacing: 12, textColor: CGColor(gray: 0, alpha: 1),
            containerWidth: CGFloat(width), letterSpacing: 0, paragraphSpacing: 0, justify: false,
            fontName: TypographyEngine.titleFontName, lineHeight: typography.titleLineHeight)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var bands = 0, wasInk = false
        for y in 0..<height {
            let ink = (0..<width).contains { x in pixels[(y * width + x) * 4] < 200 }
            if ink && !wasInk { bands += 1 }
            wasInk = ink
        }
        XCTAssertEqual(bands, 2, "The title must draw two lines without a third line for the final glyph")
    }
}

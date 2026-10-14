import Foundation
import CoreText
#if canImport(LegadoCore)
import LegadoCore
#endif

// MARK: - Unified Typography Models

public struct TypographyLine: Identifiable {
    public var id: Int { index }
    public let index: Int
    public let text: String
    public let isParagraphEnd: Bool
    public let paragraphText: String
    public let charRange: Range<Int>
    public let y: CGFloat
    public let height: CGFloat

    public init(
        index: Int,
        text: String,
        isParagraphEnd: Bool,
        paragraphText: String,
        charRange: Range<Int>,
        y: CGFloat,
        height: CGFloat
    ) {
        self.index = index
        self.text = text
        self.isParagraphEnd = isParagraphEnd
        self.paragraphText = paragraphText
        self.charRange = charRange
        self.y = y
        self.height = height
    }
}

public struct TypographyImage: Identifiable {
    public var id: Int
    public let urlString: String
    public let y: CGFloat
    public let height: CGFloat

    public init(id: Int, urlString: String, y: CGFloat, height: CGFloat) {
        self.id = id
        self.urlString = urlString
        self.y = y
        self.height = height
    }
}

/// A slide-mode page: a slice of consecutive text lines, or a single full-page image.
/// Both renderers read this one definition, so what 滑动 shows and 滚动 shows can
/// never disagree about where a page boundary is.
public enum TypographyPage: Equatable {
    case lines(Range<Int>)
    case image(Int)
}

public final class ChapterTypography: Identifiable {
    public var id: Int { chapter.index }
    public let chapter: BookChapter
    public let rawContent: String

    // Multi-line wrapped title
    public let titleLines: [String]
    public let titleLineHeight: CGFloat
    public let titleTotalHeight: CGFloat

    // Unified lines and images
    public let lines: [TypographyLine]
    public let images: [TypographyImage]

    // Slide mode pages: text-line slices and image pages in reading order
    public let pages: [TypographyPage]

    // Scroll mode metrics
    public let totalHeight: CGFloat
    public var yOffset: CGFloat = 0

    public init(
        chapter: BookChapter,
        rawContent: String,
        titleLines: [String],
        titleLineHeight: CGFloat,
        titleTotalHeight: CGFloat,
        lines: [TypographyLine],
        images: [TypographyImage],
        pages: [TypographyPage],
        totalHeight: CGFloat,
        yOffset: CGFloat = 0
    ) {
        self.chapter = chapter
        self.rawContent = rawContent
        self.titleLines = titleLines
        self.titleLineHeight = titleLineHeight
        self.titleTotalHeight = titleTotalHeight
        self.lines = lines
        self.images = images
        self.pages = pages
        self.totalHeight = totalHeight
        self.yOffset = yOffset
    }

    /// `pageRanges`-compatible view: line slice of a text page (nil for image pages).
    public func lineRange(ofPage pageIndex: Int) -> Range<Int>? {
        guard pageIndex >= 0 && pageIndex < pages.count else { return nil }
        if case let .lines(range) = pages[pageIndex] { return range }
        return nil
    }

    /// First line index rendered on a page; image pages fall back to their inserted id.
    public func firstLineIndex(ofPage pageIndex: Int) -> Int? {
        if let range = lineRange(ofPage: pageIndex) { return range.lowerBound }
        if case let .image(imgId) = pageOrNil(pageIndex) { return imgId }
        return nil
    }

    private func pageOrNil(_ pageIndex: Int) -> TypographyPage? {
        guard pageIndex >= 0 && pageIndex < pages.count else { return nil }
        return pages[pageIndex]
    }

    /// Finds the slide page index containing a specific line index
    public func pageIndex(forLine lineIndex: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        for (pIdx, page) in pages.enumerated() {
            if case let .lines(range) = page, range.contains(lineIndex) { return pIdx }
        }
        for (pIdx, page) in pages.enumerated() {
            if case let .lines(range) = page, lineIndex < range.lowerBound { return pIdx }
        }
        return pages.count - 1
    }

    /// Finds the slide page index corresponding to a character offset
    public func pageIndex(forCharOffset charOffset: Int) -> Int {
        guard !lines.isEmpty, !pages.isEmpty else { return 0 }
        for line in lines {
            if charOffset >= line.charRange.lowerBound && charOffset < line.charRange.upperBound {
                return pageIndex(forLine: line.index)
            }
        }
        if let last = lines.last, charOffset >= last.charRange.upperBound {
            return pages.count - 1
        }
        return 0
    }
}

// MARK: - Unified Typography Engine (Single Source of Layout Truth)

public enum TypographyEngine {
    public static func typeset(
        chapter: BookChapter,
        content: String,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        letterSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        paddingLeading: CGFloat,
        paddingTrailing: CGFloat,
        paddingTop: CGFloat,
        paddingBottom: CGFloat,
        imageStyle: ReadImageStyle,
        justify: Bool
    ) -> ChapterTypography {
        let usableWidth = max(100.0, containerWidth - paddingLeading - paddingTrailing)
        let usablePageHeight = max(180.0, containerHeight - paddingTop - paddingBottom)

        // 1. Wrap Chapter Title into multiple lines if long
        let titleFontSize = fontSize + 4.0
        let titleLineHeight = titleFontSize * 1.35 + lineSpacing
        let titleFont = CTFontCreateWithName("PingFangSC-Semibold" as CFString, titleFontSize, nil)
        var titleAttrs: [CFString: Any] = [kCTFontAttributeName: titleFont]
        if letterSpacing != 0 {
            titleAttrs[kCTKernAttributeName] = letterSpacing
        }

        var titleLines: [String] = []
        let rawTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawTitle.isEmpty,
           let attrStr = CFAttributedStringCreate(nil, rawTitle as CFString, titleAttrs as CFDictionary) {
            let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
            let textLen = CFStringGetLength(rawTitle as CFString)
            var start = 0
            let nsStr = rawTitle as NSString
            while start < textLen {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(usableWidth))
                if count <= 0 { break }
                let sub = nsStr.substring(with: NSRange(location: start, length: count))
                let trimmed = sub.trimmingCharacters(in: .newlines)
                if !trimmed.isEmpty {
                    titleLines.append(trimmed)
                }
                start += count
            }
        }
        if titleLines.isEmpty {
            titleLines = [rawTitle.isEmpty ? "章节" : rawTitle]
        }
        let titleTotalHeight = CGFloat(titleLines.count) * titleLineHeight + 20.0

        // 2. Break Body Paragraphs into Lines
        let bodyLineHeight = fontSize * 1.25 + lineSpacing
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        var bodyAttrs: [CFString: Any] = [kCTFontAttributeName: font]
        if letterSpacing != 0 {
            bodyAttrs[kCTKernAttributeName] = letterSpacing
        }

        var lines: [TypographyLine] = []
        var images: [TypographyImage] = []
        var currentY = titleTotalHeight + 12.0
        var lineIndex = 0
        var charCursor = 0

        let paragraphs = content.components(separatedBy: "\n")

        for pText in paragraphs {
            let trimmed = pText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                charCursor += pText.count + 1
                continue
            }

            // Image placeholder check
            if trimmed.hasPrefix("[image:") && trimmed.hasSuffix("]") {
                if imageStyle != .textOnly {
                    let imgUrl = String(trimmed.dropFirst(7).dropLast(1)).trimmingCharacters(in: .whitespaces)
                    let imgH: CGFloat = 260.0
                    images.append(TypographyImage(id: lineIndex, urlString: imgUrl, y: currentY, height: imgH))
                    currentY += imgH + paragraphSpacing
                    // Reserve the slot so a following text line never reuses this id.
                    lineIndex += 1
                }
                charCursor += pText.count + 1
                continue
            }

            guard let attrString = CFAttributedStringCreate(nil, pText as CFString, bodyAttrs as CFDictionary) else {
                charCursor += pText.count + 1
                continue
            }

            let typesetter = CTTypesetterCreateWithAttributedString(attrString)
            let textLen = CFStringGetLength(pText as CFString)
            var start = 0
            let nsStr = pText as NSString

            while start < textLen {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(usableWidth))
                if count <= 0 { break }

                let subText = nsStr.substring(with: NSRange(location: start, length: count))
                let isEnd = (start + count >= textLen)
                let subRange = (charCursor + start)..<(charCursor + start + count)

                lines.append(TypographyLine(
                    index: lineIndex,
                    text: subText,
                    isParagraphEnd: isEnd,
                    paragraphText: pText,
                    charRange: subRange,
                    y: currentY,
                    height: bodyLineHeight
                ))

                currentY += bodyLineHeight
                if isEnd {
                    currentY += paragraphSpacing
                }
                start += count
                lineIndex += 1
            }

            charCursor += pText.count + 1
        }

        let totalHeight = currentY + 72.0 // includes end banner

        // 3. Slice the same content into Slide Mode Pages.
        //    Images own a page (matching Android's standalone image block); text lines pack by
        //    height, with the chapter title charged to page 0.
        let firstPageCapacity = max(100.0, usablePageHeight - titleTotalHeight)
        var pages: [TypographyPage] = []
        var pageStart = 0
        var usedH: CGFloat = 0
        var currentCap = firstPageCapacity

        func flushTextPage(until endExclusive: Int) {
            if endExclusive > pageStart {
                pages.append(.lines(pageStart..<endExclusive))
            }
        }

        var i = 0
        while i < lines.count {
            let l = lines[i]

            // An image slot sits before this text line → close the running text page and give
            // the image its own page, exactly like the old `paginate()` did with `flushPage()`.
            if images.contains(where: { $0.id == l.index }) {
                flushTextPage(until: i)
                if let img = images.first(where: { $0.id == l.index }) {
                    pages.append(.image(img.id))
                }
                pageStart = i
                usedH = 0
                currentCap = usablePageHeight
                continue
            }

            let lH = l.height + (l.isParagraphEnd ? paragraphSpacing : 0)
            if usedH + lH > currentCap && i > pageStart {
                flushTextPage(until: i)
                pageStart = i
                usedH = 0
                currentCap = usablePageHeight
            }
            usedH += lH
            i += 1
        }
        flushTextPage(until: lines.count)

        // Images after the last text line (chapter ends with an illustration).
        let lastLineId = lines.last.map { $0.index } ?? -1
        for img in images where img.id > lastLineId {
            pages.append(.image(img.id))
        }

        if pages.isEmpty {
            pages.append(.lines(0..<max(0, lines.count)))
        }

        return ChapterTypography(
            chapter: chapter,
            rawContent: content,
            titleLines: titleLines,
            titleLineHeight: titleLineHeight,
            titleTotalHeight: titleTotalHeight,
            lines: lines,
            images: images,
            pages: pages,
            totalHeight: totalHeight,
            yOffset: 0
        )
    }
}

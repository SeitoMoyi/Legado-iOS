import SwiftUI
import CoreText
#if canImport(LegadoCore)
import LegadoCore
#endif

#if os(iOS)
import UIKit

// MARK: - CoreText Line Model for Smooth Scroll Canvas

public struct ContinuousCTLine {
    public let text: String
    public let ctLine: CTLine
    public let isParagraphEnd: Bool
    public let paragraphText: String
    public let charRange: Range<Int>
    public let y: CGFloat
    public let height: CGFloat
}

public struct ContinuousImageItem {
    public let urlString: String
    public let y: CGFloat
    public let height: CGFloat
}

public final class ContinuousChapterLayout {
    public let chapter: BookChapter
    public let lines: [ContinuousCTLine]
    public let images: [ContinuousImageItem]
    public let titleHeight: CGFloat
    public let contentHeight: CGFloat
    public let totalHeight: CGFloat
    public var yOffset: CGFloat = 0

    public init(
        chapter: BookChapter,
        lines: [ContinuousCTLine],
        images: [ContinuousImageItem],
        titleHeight: CGFloat,
        contentHeight: CGFloat,
        totalHeight: CGFloat,
        yOffset: CGFloat = 0
    ) {
        self.chapter = chapter
        self.lines = lines
        self.images = images
        self.titleHeight = titleHeight
        self.contentHeight = contentHeight
        self.totalHeight = totalHeight
        self.yOffset = yOffset
    }
}

// MARK: - Single Chapter Canvas View (Direct CoreText Drawing)

public final class ChapterCanvasLayerView: UIView {
    public var layout: ContinuousChapterLayout?
    public var fontSize: CGFloat = 18
    public var textColor: UIColor = .label
    public var accentColor: UIColor = .systemBlue
    public var paddingLeading: CGFloat = 20
    public var paddingTrailing: CGFloat = 20
    public var aloudParagraph: String = ""
    public var aloudIsActive: Bool = false
    public var isLastChapterInBook: Bool = false
    public var nextChapterTitle: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let layout = layout else { return }

        let usableWidth = max(100, bounds.width - paddingLeading - paddingTrailing)

        // 1. Draw Chapter Title
        let titleFont = CTFontCreateWithName("PingFangSC-Semibold" as CFString, fontSize + 3, nil)
        let titleAttrs: [CFString: Any] = [
            kCTFontAttributeName: titleFont,
            kCTForegroundColorAttributeName: textColor.cgColor
        ]
        if let titleAttrStr = CFAttributedStringCreate(nil, layout.chapter.title as CFString, titleAttrs as CFDictionary) {
            let titleLine = CTLineCreateWithAttributedString(titleAttrStr)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(titleLine, &ascent, &descent, &leading)

            let titleY = 24.0 + ascent
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: paddingLeading, y: titleY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(titleLine, ctx)
            ctx.restoreGState()
        }

        // 2. Draw Text Lines with CoreText
        for lineInfo in layout.lines {
            // Check if this line is in the aloud paragraph
            let isAloud = aloudIsActive && !aloudParagraph.isEmpty && (
                lineInfo.paragraphText == aloudParagraph ||
                lineInfo.paragraphText.trimmingCharacters(in: .whitespacesAndNewlines) == aloudParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            let lineRect = CGRect(
                x: paddingLeading - 4,
                y: lineInfo.y - 2,
                width: usableWidth + 8,
                height: lineInfo.height + 4
            )

            if isAloud {
                ctx.saveGState()
                let path = UIBezierPath(roundedRect: lineRect, cornerRadius: 4)
                ctx.setFillColor(accentColor.withAlphaComponent(0.18).cgColor)
                ctx.addPath(path.cgPath)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // Draw CTLine
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(lineInfo.ctLine, &ascent, &descent, &leading)

            let baselineY = lineInfo.y + ascent

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: paddingLeading, y: baselineY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(lineInfo.ctLine, ctx)
            ctx.restoreGState()
        }

        // 3. Draw Chapter End Transition Banner
        let bannerY = layout.titleHeight + layout.contentHeight + 20
        let bannerWidth = bounds.width - paddingLeading - paddingTrailing

        // Divider line
        ctx.saveGState()
        ctx.setStrokeColor(textColor.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: paddingLeading, y: bannerY + 12))
        ctx.addLine(to: CGPoint(x: paddingLeading + bannerWidth, y: bannerY + 12))
        ctx.strokePath()
        ctx.restoreGState()

        // End text
        let endText = isLastChapterInBook ? "已读到最后一章" : "本章完 · 下一章: \(nextChapterTitle ?? "")"
        let endFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, 12, nil)
        let endAttrs: [CFString: Any] = [
            kCTFontAttributeName: endFont,
            kCTForegroundColorAttributeName: textColor.withAlphaComponent(0.55).cgColor
        ]
        if let endAttrStr = CFAttributedStringCreate(nil, endText as CFString, endAttrs as CFDictionary) {
            let endLine = CTLineCreateWithAttributedString(endAttrStr)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(endLine, &ascent, &descent, &leading))

            let centerX = paddingLeading + max(0, (bannerWidth - lineWidth) / 2.0)
            let endBaseline = bannerY + 28.0 + ascent

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: centerX, y: endBaseline)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(endLine, ctx)
            ctx.restoreGState()
        }
    }
}

// MARK: - Continuous Scroll Reader Native UIView (UIScrollView with Bidirectional Chaining)

public final class ContinuousScrollReaderUIView: UIScrollView, UIScrollViewDelegate {
    public var onChapterChange: ((Int, String) -> Void)?
    public var onCharOffsetChange: ((Int) -> Void)?
    public var onTapZone: ((ClickActionCode) -> Void)?
    public var onRequestChapter: ((Int) async -> LoadedChapter?)?

    private var chapterLayouts: [ContinuousChapterLayout] = []
    private var chapterViews: [Int: ChapterCanvasLayerView] = [:]
    private var activeChapterIndex: Int = 0
    private var totalChaptersCount: Int = 0
    private var chaptersMeta: [BookChapter] = []

    // Styling
    private var fontSize: CGFloat = 18
    private var lineSpacing: CGFloat = 6
    private var letterSpacing: CGFloat = 0
    private var paragraphSpacing: CGFloat = 10
    private var paddingLeading: CGFloat = 20
    private var paddingTrailing: CGFloat = 20
    private var textColor: UIColor = .label
    private var accentColor: UIColor = .systemBlue
    private var justify: Bool = true

    // Audio highlighting
    private var aloudParagraph: String = ""
    private var aloudIsActive: Bool = false

    // Tap actions map (3x3 grid)
    private var tapActionList: [ClickActionCode] = ReaderPrefs.defaultClickActions.map { ClickActionCode.from($0) }

    // Loading locks
    private var isLoadingPrevious: Bool = false
    private var isLoadingNext: Bool = false
    private var isPrependingChapter: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupScrollView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupScrollView() {
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = true
        backgroundColor = .clear

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let bounds = self.bounds
        let width = bounds.width
        let height = bounds.height

        guard width > 0, height > 0 else { return }

        // Local coordinate inside visible viewport:
        let viewX = point.x - contentOffset.x
        let viewY = point.y - contentOffset.y

        let col = min(2, max(0, Int(viewX / (width / 3.0))))
        let row = min(2, max(0, Int(viewY / (height / 3.0))))
        let zoneIndex = row * 3 + col

        if zoneIndex >= 0 && zoneIndex < tapActionList.count {
            onTapZone?(tapActionList[zoneIndex])
        }
    }

    public func updateConfiguration(
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        letterSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        paddingLeading: CGFloat,
        paddingTrailing: CGFloat,
        textColor: UIColor,
        accentColor: UIColor,
        justify: Bool,
        tapActions: [ClickActionCode],
        aloudParagraph: String,
        aloudIsActive: Bool,
        chaptersMeta: [BookChapter]
    ) {
        let needsRelayout = (
            self.fontSize != fontSize ||
            self.lineSpacing != lineSpacing ||
            self.letterSpacing != letterSpacing ||
            self.paragraphSpacing != paragraphSpacing ||
            self.paddingLeading != paddingLeading ||
            self.paddingTrailing != paddingTrailing ||
            self.justify != justify
        )

        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.paragraphSpacing = paragraphSpacing
        self.paddingLeading = paddingLeading
        self.paddingTrailing = paddingTrailing
        self.textColor = textColor
        self.accentColor = accentColor
        self.justify = justify
        self.tapActionList = tapActions
        self.aloudParagraph = aloudParagraph
        self.aloudIsActive = aloudIsActive
        self.chaptersMeta = chaptersMeta
        self.totalChaptersCount = chaptersMeta.count

        if needsRelayout && bounds.width > 0 {
            recalculateAllLayouts()
        } else {
            // Update visual properties on existing views
            for (_, view) in chapterViews {
                view.textColor = textColor
                view.accentColor = accentColor
                view.aloudParagraph = aloudParagraph
                view.aloudIsActive = aloudIsActive
                view.setNeedsDisplay()
            }
        }
    }

    public func resetToChapter(loaded: LoadedChapter, toEnd: Bool = false) {
        // Clear all existing canvas views
        for (_, view) in chapterViews {
            view.removeFromSuperview()
        }
        chapterViews.removeAll()
        chapterLayouts.removeAll()

        activeChapterIndex = loaded.chapter.index

        let layout = buildLayout(for: loaded)
        layout.yOffset = 0
        chapterLayouts = [layout]

        contentSize = CGSize(width: bounds.width, height: layout.totalHeight)

        let chapterView = makeChapterView(for: layout)
        addSubview(chapterView)
        chapterViews[loaded.chapter.index] = chapterView

        if toEnd {
            // Position at end of chapter
            let targetY = max(0, layout.totalHeight - bounds.height)
            contentOffset = CGPoint(x: 0, y: targetY)
        } else {
            contentOffset = .zero
        }

        onChapterChange?(loaded.chapter.index, loaded.chapter.title)

        // Preload next chapter below if available
        if loaded.chapter.index < totalChaptersCount - 1 {
            Task { @MainActor in
                await self.loadNextChapter()
            }
        }
    }

    // MARK: - Layout Calculation Engine

    private func buildLayout(for loaded: LoadedChapter) -> ContinuousChapterLayout {
        let usableWidth = max(100.0, bounds.width - paddingLeading - paddingTrailing)
        let lineHeight = fontSize * 1.25 + lineSpacing
        let titleHeight = (fontSize + 3) * 1.4 + 28.0

        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        var attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: textColor.cgColor
        ]
        if letterSpacing != 0 {
            attrs[kCTKernAttributeName] = letterSpacing
        }

        var lines: [ContinuousCTLine] = []
        var images: [ContinuousImageItem] = []
        var currentY: CGFloat = titleHeight + 10.0
        var charCursor = 0

        let paragraphs = loaded.content.components(separatedBy: "\n")

        for pText in paragraphs {
            let trimmed = pText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                charCursor += pText.count + 1
                continue
            }

            // Check if paragraph is image placeholder
            if trimmed.hasPrefix("[image:") && trimmed.hasSuffix("]") {
                let imgUrl = String(trimmed.dropFirst(7).dropLast(1)).trimmingCharacters(in: .whitespaces)
                let imgHeight: CGFloat = 260.0
                images.append(ContinuousImageItem(urlString: imgUrl, y: currentY, height: imgHeight))
                currentY += imgHeight + paragraphSpacing
                charCursor += pText.count + 1
                continue
            }

            guard let attrString = CFAttributedStringCreate(nil, pText as CFString, attrs as CFDictionary) else {
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
                let subRange = start..<(start + count)

                guard let lineAttrStr = CFAttributedStringCreate(nil, subText as CFString, attrs as CFDictionary) else {
                    start += count
                    continue
                }
                let lineTypesetter = CTTypesetterCreateWithAttributedString(lineAttrStr)
                let rawLine = CTTypesetterCreateLine(lineTypesetter, CFRange(location: 0, length: subText.count))

                let finalLine: CTLine
                if justify && !isEnd && subText.count > 5 {
                    finalLine = CTLineCreateJustifiedLine(rawLine, 1.0, Double(usableWidth)) ?? rawLine
                } else {
                    finalLine = rawLine
                }

                lines.append(ContinuousCTLine(
                    text: subText,
                    ctLine: finalLine,
                    isParagraphEnd: isEnd,
                    paragraphText: pText,
                    charRange: subRange,
                    y: currentY,
                    height: lineHeight
                ))

                currentY += lineHeight
                if isEnd {
                    currentY += paragraphSpacing
                }
                start += count
            }

            charCursor += pText.count + 1
        }

        let contentHeight = currentY - (titleHeight + 10.0)
        let bannerHeight: CGFloat = 72.0
        let totalHeight = currentY + bannerHeight

        return ContinuousChapterLayout(
            chapter: loaded.chapter,
            lines: lines,
            images: images,
            titleHeight: titleHeight,
            contentHeight: contentHeight,
            totalHeight: totalHeight,
            yOffset: 0
        )
    }

    private func makeChapterView(for layout: ContinuousChapterLayout) -> ChapterCanvasLayerView {
        let frame = CGRect(x: 0, y: layout.yOffset, width: bounds.width, height: layout.totalHeight)
        let view = ChapterCanvasLayerView(frame: frame)
        view.layout = layout
        view.fontSize = fontSize
        view.textColor = textColor
        view.accentColor = accentColor
        view.paddingLeading = paddingLeading
        view.paddingTrailing = paddingTrailing
        view.aloudParagraph = aloudParagraph
        view.aloudIsActive = aloudIsActive
        view.isLastChapterInBook = (layout.chapter.index >= totalChaptersCount - 1)
        if layout.chapter.index + 1 < chaptersMeta.count {
            view.nextChapterTitle = chaptersMeta[layout.chapter.index + 1].title
        }
        return view
    }

    private func recalculateAllLayouts() {
        guard !chapterLayouts.isEmpty, bounds.width > 0 else { return }

        var currentY: CGFloat = 0
        var newLayouts: [ContinuousChapterLayout] = []

        for layout in chapterLayouts {
            // Re-build layout with current font size and usable width
            let loaded = LoadedChapter(
                chapter: layout.chapter,
                content: layout.lines.map { $0.text }.joined(separator: ""),
                blocks: []
            )
            let updated = buildLayout(for: loaded)
            updated.yOffset = currentY
            newLayouts.append(updated)

            if let view = chapterViews[layout.chapter.index] {
                view.frame = CGRect(x: 0, y: currentY, width: bounds.width, height: updated.totalHeight)
                view.layout = updated
                view.fontSize = fontSize
                view.textColor = textColor
                view.accentColor = accentColor
                view.paddingLeading = paddingLeading
                view.paddingTrailing = paddingTrailing
                view.setNeedsDisplay()
            }

            currentY += updated.totalHeight
        }

        chapterLayouts = newLayouts
        contentSize = CGSize(width: bounds.width, height: currentY)
    }

    // MARK: - Seamless Bidirectional Chapter Chaining

    private func loadPreviousChapter() async {
        guard !isLoadingPrevious, let first = chapterLayouts.first, first.chapter.index > 0 else { return }
        let prevIndex = first.chapter.index - 1
        isLoadingPrevious = true

        guard let loaded = await onRequestChapter?(prevIndex) else {
            isLoadingPrevious = false
            return
        }

        // Build layout for previous chapter
        let prevLayout = buildLayout(for: loaded)
        let addedHeight = prevLayout.totalHeight

        // Shift existing chapters down by addedHeight
        isPrependingChapter = true
        for layout in chapterLayouts {
            layout.yOffset += addedHeight
            if let view = chapterViews[layout.chapter.index] {
                view.frame.origin.y += addedHeight
            }
        }

        prevLayout.yOffset = 0
        chapterLayouts.insert(prevLayout, at: 0)

        let prevView = makeChapterView(for: prevLayout)
        addSubview(prevView)
        chapterViews[loaded.chapter.index] = prevView

        // Update contentSize and ATOMICALLY shift contentOffset.y so user sees ZERO movement
        contentSize = CGSize(width: bounds.width, height: contentSize.height + addedHeight)
        contentOffset = CGPoint(x: contentOffset.x, y: contentOffset.y + addedHeight)

        isPrependingChapter = false
        isLoadingPrevious = false

        // Prune chapters if too many loaded (keep window <= 5)
        pruneDistantChapters()
    }

    private func loadNextChapter() async {
        guard !isLoadingNext, let last = chapterLayouts.last, last.chapter.index < totalChaptersCount - 1 else { return }
        let nextIndex = last.chapter.index + 1
        isLoadingNext = true

        guard let loaded = await onRequestChapter?(nextIndex) else {
            isLoadingNext = false
            return
        }

        let currentBottom = contentSize.height
        let nextLayout = buildLayout(for: loaded)
        nextLayout.yOffset = currentBottom
        chapterLayouts.append(nextLayout)

        let nextView = makeChapterView(for: nextLayout)
        addSubview(nextView)
        chapterViews[loaded.chapter.index] = nextView

        contentSize = CGSize(width: bounds.width, height: currentBottom + nextLayout.totalHeight)
        isLoadingNext = false

        // Prune chapters if too many loaded
        pruneDistantChapters()
    }

    private func pruneDistantChapters() {
        guard chapterLayouts.count > 5 else { return }
        // Keep active chapter and immediate neighbors
        while chapterLayouts.count > 4 {
            if let first = chapterLayouts.first, first.chapter.index < activeChapterIndex - 1 {
                let removedHeight = first.totalHeight
                chapterViews[first.chapter.index]?.removeFromSuperview()
                chapterViews.removeValue(forKey: first.chapter.index)
                chapterLayouts.removeFirst()

                // Shift remaining chapters up
                for layout in chapterLayouts {
                    layout.yOffset -= removedHeight
                    chapterViews[layout.chapter.index]?.frame.origin.y -= removedHeight
                }
                contentSize = CGSize(width: bounds.width, height: contentSize.height - removedHeight)
                contentOffset = CGPoint(x: contentOffset.x, y: max(0, contentOffset.y - removedHeight))
            } else if let last = chapterLayouts.last, last.chapter.index > activeChapterIndex + 2 {
                chapterViews[last.chapter.index]?.removeFromSuperview()
                chapterViews.removeValue(forKey: last.chapter.index)
                chapterLayouts.removeLast()
                contentSize = CGSize(width: bounds.width, height: last.yOffset)
            } else {
                break
            }
        }
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isPrependingChapter, bounds.height > 0 else { return }

        let offsetY = scrollView.contentOffset.y
        let viewHeight = bounds.height

        // 1. Detect active chapter at reading focus line (30% from top of screen)
        let focusY = offsetY + viewHeight * 0.3
        if let current = chapterLayouts.first(where: { focusY >= $0.yOffset && focusY < ($0.yOffset + $0.totalHeight) }) {
            if activeChapterIndex != current.chapter.index {
                activeChapterIndex = current.chapter.index
                onChapterChange?(current.chapter.index, current.chapter.title)
            }

            // Estimate character offset
            let relY = focusY - current.yOffset - current.titleHeight
            if let line = current.lines.first(where: { relY >= $0.y && relY < ($0.y + $0.height) }) {
                onCharOffsetChange?(line.charRange.lowerBound)
            }
        }

        // 2. Check top boundary for loading previous chapter (within 350pt of top)
        if offsetY < 350, let first = chapterLayouts.first, first.chapter.index > 0 {
            Task { @MainActor in
                await self.loadPreviousChapter()
            }
        }

        // 3. Check bottom boundary for loading next chapter (within 1000pt of bottom)
        let distToBottom = contentSize.height - (offsetY + viewHeight)
        if distToBottom < 1000, let last = chapterLayouts.last, last.chapter.index < totalChaptersCount - 1 {
            Task { @MainActor in
                await self.loadNextChapter()
            }
        }
    }

    public func scrollToChapter(_ index: Int, animated: Bool = true) {
        if let layout = chapterLayouts.first(where: { $0.chapter.index == index }) {
            setContentOffset(CGPoint(x: 0, y: layout.yOffset), animated: animated)
        }
    }
}

// MARK: - SwiftUI Bridge Representable

public struct ReaderScrollCanvasView: UIViewRepresentable {
    public let loadedChapter: LoadedChapter?
    public let chaptersMeta: [BookChapter]
    public let currentChapterIndex: Int
    public let scrollSessionId: UUID
    public let readerConfig: ReaderConfig
    public let aloudParagraph: String
    public let aloudIsActive: Bool

    public let onChapterChange: (Int, String) -> Void
    public let onCharOffsetChange: (Int) -> Void
    public let onTapZone: (ClickActionCode) -> Void
    public let onRequestChapter: (Int) async -> LoadedChapter?

    public init(
        loadedChapter: LoadedChapter?,
        chaptersMeta: [BookChapter],
        currentChapterIndex: Int,
        scrollSessionId: UUID,
        readerConfig: ReaderConfig,
        aloudParagraph: String,
        aloudIsActive: Bool,
        onChapterChange: @escaping (Int, String) -> Void,
        onCharOffsetChange: @escaping (Int) -> Void,
        onTapZone: @escaping (ClickActionCode) -> Void,
        onRequestChapter: @escaping (Int) async -> LoadedChapter?
    ) {
        self.loadedChapter = loadedChapter
        self.chaptersMeta = chaptersMeta
        self.currentChapterIndex = currentChapterIndex
        self.scrollSessionId = scrollSessionId
        self.readerConfig = readerConfig
        self.aloudParagraph = aloudParagraph
        self.aloudIsActive = aloudIsActive
        self.onChapterChange = onChapterChange
        self.onCharOffsetChange = onCharOffsetChange
        self.onTapZone = onTapZone
        self.onRequestChapter = onRequestChapter
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> ContinuousScrollReaderUIView {
        let view = ContinuousScrollReaderUIView(frame: .zero)
        view.onChapterChange = onChapterChange
        view.onCharOffsetChange = onCharOffsetChange
        view.onTapZone = onTapZone
        view.onRequestChapter = onRequestChapter

        context.coordinator.currentSessionId = scrollSessionId
        if let chapter = loadedChapter {
            view.resetToChapter(loaded: chapter)
        }
        return view
    }

    public func updateUIView(_ uiView: ContinuousScrollReaderUIView, context: Context) {
        uiView.onChapterChange = onChapterChange
        uiView.onCharOffsetChange = onCharOffsetChange
        uiView.onTapZone = onTapZone
        uiView.onRequestChapter = onRequestChapter

        uiView.updateConfiguration(
            fontSize: readerConfig.fontSize,
            lineSpacing: readerConfig.lineSpacing,
            letterSpacing: readerConfig.letterSpacing,
            paragraphSpacing: readerConfig.paragraphSpacing,
            paddingLeading: readerConfig.paddingLeading,
            paddingTrailing: readerConfig.paddingTrailing,
            textColor: UIColor(readerConfig.theme.textColor),
            accentColor: .systemBlue,
            justify: readerConfig.prefs.textFullJustify,
            tapActions: readerConfig.clickActionList,
            aloudParagraph: aloudParagraph,
            aloudIsActive: aloudIsActive,
            chaptersMeta: chaptersMeta
        )

        // Session ID changed -> Chapter jump or mode switch: reset cleanly
        if context.coordinator.currentSessionId != scrollSessionId {
            context.coordinator.currentSessionId = scrollSessionId
            if let chapter = loadedChapter {
                uiView.resetToChapter(loaded: chapter)
            }
        }
    }

    public class Coordinator {
        var parent: ReaderScrollCanvasView
        var currentSessionId: UUID?

        init(_ parent: ReaderScrollCanvasView) {
            self.parent = parent
        }
    }
}

#else

// macOS / non-iOS fallback stub so cross-platform tests compile cleanly
public struct ReaderScrollCanvasView: View {
    public init(
        loadedChapter: Any?,
        chaptersMeta: Any,
        currentChapterIndex: Int,
        scrollSessionId: UUID,
        readerConfig: Any,
        aloudParagraph: String,
        aloudIsActive: Bool,
        onChapterChange: @escaping (Int, String) -> Void,
        onCharOffsetChange: @escaping (Int) -> Void,
        onTapZone: @escaping (ClickActionCode) -> Void,
        onRequestChapter: @escaping (Int) async -> Any?
    ) {}

    public var body: some View {
        EmptyView()
    }
}

#endif

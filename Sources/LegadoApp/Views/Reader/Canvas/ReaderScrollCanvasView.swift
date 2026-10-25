import SwiftUI
import CoreText
#if canImport(LegadoCore)
import LegadoCore
#endif

#if os(iOS)
import UIKit

// MARK: - Shared Typography Image Loader

/// Small memory-cached async loader for inline chapter images, shared by every canvas view
/// so scrolling back to an already-seen chapter never re-downloads.
public final class ChapterImageLoader {
    public static let shared = ChapterImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: [UIImageView]] = [:]

    private init() {
        cache.countLimit = 120
    }

    public func load(urlString: String, into imageView: UIImageView) {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            imageView.image = cached
            return
        }
        imageView.image = nil

        guard let url = URL(string: urlString) else { return }
        inFlight[urlString, default: []].append(imageView)

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { self?.inFlight[urlString]?.removeAll() }
                return
            }
            self.cache.setObject(image, forKey: key)
            DispatchQueue.main.async {
                for view in self.inFlight[urlString] ?? [] {
                    view.image = image
                }
                self.inFlight[urlString]?.removeAll()
            }
        }.resume()
    }
}

// MARK: - Single Chapter Canvas View (Direct CoreText Drawing from Unified Typography)

public final class ChapterCanvasLayerView: UIView {
    public var typography: ChapterTypography?
    public var fontSize: CGFloat = 18
    public var lineSpacing: CGFloat = 6
    public var letterSpacing: CGFloat = 0
    public var textColor: UIColor = .label
    public var accentColor: UIColor = .systemBlue
    public var paddingLeading: CGFloat = 20
    public var paddingTrailing: CGFloat = 20
    public var justify: Bool = true
    public var aloudParagraph: String = ""
    public var aloudIsActive: Bool = false
    public var isLastChapterInBook: Bool = false
    public var nextChapterTitle: String?
    /// Chapter-content char range currently selected inside this chapter (Part 4 选词).
    public var selectionRange: Range<Int>? {
        didSet { setNeedsDisplay() }
    }

    /// Typography-image views keyed by `TypographyImage.id`, so redraws reuse them.
    private var imageViews: [Int: UIImageView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Places one `UIImageView` per typography image at its shared `y`, reusing existing views
    /// so scrolling never re-triggers a download.
    private func layoutImageViews(for typo: ChapterTypography) {
        // Remove views whose image no longer exists in this typography.
        for (key, view) in imageViews where !typo.images.contains(where: { $0.id == key }) {
            view.removeFromSuperview()
            imageViews.removeValue(forKey: key)
        }

        for img in typo.images {
            let frame = CGRect(
                x: paddingLeading,
                y: img.y,
                width: max(100, bounds.width - paddingLeading - paddingTrailing),
                height: img.height
            )

            if let existing = imageViews[img.id] {
                existing.frame = frame
                if existing.accessibilityIdentifier != img.urlString {
                    existing.accessibilityIdentifier = img.urlString
                    ChapterImageLoader.shared.load(urlString: img.urlString, into: existing)
                }
            } else {
                let imageView = UIImageView(frame: frame)
                imageView.contentMode = .scaleAspectFit
                imageView.clipsToBounds = true
                imageView.backgroundColor = .clear
                imageView.accessibilityIdentifier = img.urlString
                addSubview(imageView)
                imageViews[img.id] = imageView
                ChapterImageLoader.shared.load(urlString: img.urlString, into: imageView)
            }
        }
    }

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let typo = typography else { return }

        let usableWidth = max(100, bounds.width - paddingLeading - paddingTrailing)

        // 0. Selection highlight under the text (Part 4 选词).
        if let selRange = selectionRange {
            let rects = typo.selectionRects(for: selRange, paddingLeading: paddingLeading,
                                            fontSize: fontSize, letterSpacing: letterSpacing)
            let accent = accentColor.withAlphaComponent(0.28).cgColor
            SelectionRenderer.drawRects(rects, in: ctx, accent: accent)
            SelectionRenderer.drawHandles(rects, in: ctx, accent: accentColor.withAlphaComponent(0.85).cgColor,
                                          atStart: true, atEnd: true)
        }

        // 1. Draw Chapter Title (Multi-line wrapped, unified with Slide mode!)
        let titleFontSize = fontSize + 4.0
        let titleFont = CTFontCreateWithName("PingFangSC-Semibold" as CFString, titleFontSize, nil)
        var titleAttrs: [CFString: Any] = [
            kCTFontAttributeName: titleFont,
            kCTForegroundColorAttributeName: textColor.cgColor
        ]
        if letterSpacing != 0 {
            titleAttrs[kCTKernAttributeName] = letterSpacing
        }

        let titleLineHeight = typo.titleLineHeight

        for (tIdx, tLine) in typo.titleLines.enumerated() {
            guard !tLine.isEmpty,
                  let titleAttrStr = CFAttributedStringCreate(nil, tLine as CFString, titleAttrs as CFDictionary) else {
                continue
            }
            let titleLine = CTLineCreateWithAttributedString(titleAttrStr)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(titleLine, &ascent, &descent, &leading)

            let titleY = 24.0 + CGFloat(tIdx) * titleLineHeight + ascent
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: paddingLeading, y: titleY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(titleLine, ctx)
            ctx.restoreGState()
        }

        // 2. Draw Text Lines with CoreText
        let bodyFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        var bodyAttrs: [CFString: Any] = [
            kCTFontAttributeName: bodyFont,
            kCTForegroundColorAttributeName: textColor.cgColor
        ]
        if letterSpacing != 0 {
            bodyAttrs[kCTKernAttributeName] = letterSpacing
        }

        for lineInfo in typo.lines {
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

            guard let lineAttrStr = CFAttributedStringCreate(nil, lineInfo.text as CFString, bodyAttrs as CFDictionary) else {
                continue
            }
            let lineTypesetter = CTTypesetterCreateWithAttributedString(lineAttrStr)
            let rawLine = CTTypesetterCreateLine(lineTypesetter, CFRange(location: 0, length: lineInfo.text.count))

            let finalLine: CTLine
            if justify && !lineInfo.isParagraphEnd && lineInfo.text.count > 5 {
                finalLine = CTLineCreateJustifiedLine(rawLine, 1.0, Double(usableWidth)) ?? rawLine
            } else {
                finalLine = rawLine
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(finalLine, &ascent, &descent, &leading)

            let baselineY = lineInfo.y + ascent

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: paddingLeading, y: baselineY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(finalLine, ctx)
            ctx.restoreGState()
        }

        // 3. Chapter images are rendered as real subviews (async loading + cache), placed at
        //    the exact `y` the shared typography computed — same slot the text lines use.
        layoutImageViews(for: typo)

        // 4. Draw Chapter End Transition Banner
        let bannerY = typo.totalHeight - 72.0 + 20.0
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
    /// Part 4 选词: chapter index + finalized range, or nil range = "cleared".
    /// The rect is the selection anchor in window coordinates (menu placement).
    public var onSelectionChanged: ((Int, Range<Int>?, CGRect) -> Void)?
    public var isTextSelectionEnabled: Bool = true

    private var chapterTypographies: [ChapterTypography] = []
    private var chapterViews: [Int: ChapterCanvasLayerView] = [:]
    private var activeChapterIndex: Int = 0
    private var totalChaptersCount: Int = 0
    private var chaptersMeta: [BookChapter] = []

    // Viewport dimensions
    private var lastLayoutWidth: CGFloat = 0

    private var effectiveViewportWidth: CGFloat {
        if bounds.width > 50 { return bounds.width }
        #if os(iOS)
        return UIScreen.main.bounds.width
        #else
        return 390
        #endif
    }

    private var effectiveViewportHeight: CGFloat {
        if bounds.height > 50 { return bounds.height }
        #if os(iOS)
        return UIScreen.main.bounds.height
        #else
        return 700
        #endif
    }

    // Styling
    private var fontSize: CGFloat = 18
    private var lineSpacing: CGFloat = 6
    private var letterSpacing: CGFloat = 0
    private var paragraphSpacing: CGFloat = 10
    private var paddingLeading: CGFloat = 20
    private var paddingTrailing: CGFloat = 20
    private var paddingTop: CGFloat = 40
    private var paddingBottom: CGFloat = 40
    private var textColor: UIColor = .label
    private var accentColor: UIColor = .systemBlue
    private var justify: Bool = true
    private var imageStyle: ReadImageStyle = .standard

    // Audio highlighting
    private var aloudParagraph: String = ""
    private var aloudIsActive: Bool = false

    // Tap actions map (3x3 grid)
    private var tapActionList: [ClickActionCode] = ReaderPrefs.defaultClickActions.map { ClickActionCode.from($0) }

    // Text selection state (Part 4)
    private var selectionMachine = SelectionGestureMachine()
    private var selectionChapterIndex: Int = 0
    /// (chapterIndex, range) currently highlighted on screen.
    private var activeSelection: (chapter: Int, range: Range<Int>)? = nil
    /// True between long-press .began and its terminal state; guards `syncSelectionState`
    /// from clobbering a live drag with the parent's last committed range.
    private var isSelectionGestureActive = false

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

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSelectionLongPress(_:)))
        longPress.minimumPressDuration = 0.6
        longPress.allowableMovement = 12
        addGestureRecognizer(longPress)
    }

    // MARK: - Text Selection (Part 4)

    @objc private func handleSelectionLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isTextSelectionEnabled else { return }
        let loc = gesture.location(in: self)
        let contentPoint = CGPoint(x: loc.x, y: loc.y + contentOffset.y)

        switch gesture.state {
        case .began:
            isSelectionGestureActive = true
            let hit = chapterOffset(atContentPoint: contentPoint)
            let localTouch = touchPoint(inChapterCoords: contentPoint)
            selectionMachine.existingRange = activeSelection?.range
            updateSelectionHandlePoints()
            if let range = selectionMachine.began(atChapterOffset: hit, touchPoint: localTouch),
               let chapter = chapterTypographies.first(where: {
                   contentPoint.y >= $0.yOffset && contentPoint.y < $0.yOffset + $0.totalHeight
               }) {
                selectionChapterIndex = chapter.chapter.index
                applySelection(range: range)
            } else {
                selectionMachine.reset()
            }
        case .changed:
            let hit = chapterOffset(atContentPoint: contentPoint)
            if let range = selectionMachine.changed(headChapterOffset: hit) {
                applySelection(range: range)
            }
        case .ended:
            isSelectionGestureActive = false
            selectionMachine.ended()
            if let sel = activeSelection,
               let rects = selectionRectsInChapterView(for: sel) {
                let union = rects.reduce(CGRect.null) { $0.union($1) }
                let anchorInWindow = convert(union, to: nil)
                onSelectionChanged?(sel.chapter, sel.range, anchorInWindow)
            }
        case .cancelled, .failed:
            // Stolen gesture: drop the half-made selection — the parent never hears about
            // it, so leaving it would strand a highlight nothing can clear.
            isSelectionGestureActive = false
            selectionMachine.reset()
            if activeSelection != nil { clearSelection() }
        default:
            break
        }
    }

    /// Chapter-content offset under a scroll-content-space point, or nil off text.
    private func chapterOffset(atContentPoint p: CGPoint) -> Int? {
        guard let typo = chapterTypographies.first(where: {
            p.y >= $0.yOffset && p.y < $0.yOffset + $0.totalHeight
        }) else { return nil }
        let local = CGPoint(x: p.x, y: p.y - typo.yOffset)
        return typo.charIndex(atX: local.x - paddingLeading, y: local.y,
                              fontSize: fontSize, letterSpacing: letterSpacing)
    }

    /// The same point expressed relative to the chapter typography's own origin, used for
    /// handle hit-testing distances.
    private func touchPoint(inChapterCoords contentPoint: CGPoint) -> CGPoint {
        guard let typo = chapterTypographies.first(where: {
            contentPoint.y >= $0.yOffset && contentPoint.y < $0.yOffset + $0.totalHeight
        }) else { return contentPoint }
        return CGPoint(x: contentPoint.x, y: contentPoint.y - typo.yOffset)
    }

    private func applySelection(range: Range<Int>) {
        guard !range.isEmpty else { return }
        activeSelection = (selectionChapterIndex, range)
        if let view = chapterViews[selectionChapterIndex] {
            view.selectionRange = range
        }
    }

    private func selectionRectsInChapterView(for sel: (chapter: Int, range: Range<Int>)) -> [CGRect]? {
        guard let typo = chapterTypographies.first(where: { $0.chapter.index == sel.chapter }) else { return nil }
        return typo.selectionRects(for: sel.range, paddingLeading: paddingLeading,
                                   fontSize: fontSize, letterSpacing: letterSpacing)
    }

    private func updateSelectionHandlePoints() {
        guard let sel = activeSelection,
              let rects = selectionRectsInChapterView(for: sel),
              let chapterView = chapterViews[sel.chapter] else { return }
        let start = SelectionRenderer.handleCenter(forRects: rects, atStart: true) ?? .zero
        let end = SelectionRenderer.handleCenter(forRects: rects, atStart: false) ?? .zero
        selectionMachine.existingStartHandle = chapterView.convert(start, to: self)
        selectionMachine.existingEndHandle = chapterView.convert(end, to: self)
    }

    /// Mirrors the reader-level selection state onto the canvas. The canvas is the source of
    /// truth while a gesture is running; this is how the reader clears it after an action
    /// (copy, bookmark, page turn) without another callback round trip.
    public func syncSelectionState(chapterIndex: Int, range: Range<Int>?) {
        // Mid-gesture the canvas owns the range; applying the parent's last committed
        // value here would snap the live drag back.
        guard !isSelectionGestureActive else { return }
        if let range = range, !range.isEmpty {
            selectionChapterIndex = chapterIndex
            applySelection(range: range)
        } else if activeSelection != nil {
            if let sel = activeSelection {
                chapterViews[sel.chapter]?.selectionRange = nil
            }
            activeSelection = nil
            selectionMachine.reset()
        }
    }

    /// Drops any live selection; scrolling with an active selection would leave the
    /// highlight floating over the wrong text.
    private func clearSelection() {
        guard let sel = activeSelection else { return }
        chapterViews[sel.chapter]?.selectionRange = nil
        activeSelection = nil
        selectionMachine.reset()
        onSelectionChanged?(sel.chapter, nil, .zero)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 50 && abs(bounds.width - lastLayoutWidth) > 1 {
            lastLayoutWidth = bounds.width
            recalculateAllLayouts()
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // A tap with a live selection dismisses it before doing anything else.
        if activeSelection != nil {
            clearSelection()
            return
        }
        let point = gesture.location(in: self)
        let bounds = self.bounds
        let width = bounds.width
        let height = bounds.height

        guard width > 0, height > 0 else { return }

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
        paddingTop: CGFloat,
        paddingBottom: CGFloat,
        textColor: UIColor,
        accentColor: UIColor,
        justify: Bool,
        imageStyle: ReadImageStyle,
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
            self.paddingTop != paddingTop ||
            self.paddingBottom != paddingBottom ||
            self.justify != justify ||
            self.imageStyle != imageStyle
        )

        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.paragraphSpacing = paragraphSpacing
        self.paddingLeading = paddingLeading
        self.paddingTrailing = paddingTrailing
        self.paddingTop = paddingTop
        self.paddingBottom = paddingBottom
        self.textColor = textColor
        self.accentColor = accentColor
        self.justify = justify
        self.imageStyle = imageStyle
        self.tapActionList = tapActions
        self.aloudParagraph = aloudParagraph
        self.aloudIsActive = aloudIsActive
        self.chaptersMeta = chaptersMeta
        self.totalChaptersCount = chaptersMeta.count

        if needsRelayout && effectiveViewportWidth > 0 {
            recalculateAllLayouts()
        } else {
            for (_, view) in chapterViews {
                view.textColor = textColor
                view.accentColor = accentColor
                view.aloudParagraph = aloudParagraph
                view.aloudIsActive = aloudIsActive
                view.setNeedsDisplay()
            }
        }
    }

    public func resetToChapter(loaded: LoadedChapter, toEnd: Bool = false, targetCharPos: Int? = nil) {
        clearSelection()
        for (_, view) in chapterViews {
            view.removeFromSuperview()
        }
        chapterViews.removeAll()
        chapterTypographies.removeAll()

        activeChapterIndex = loaded.chapter.index

        let typography = typeset(loaded.chapter, rawContent: loaded.content, cached: loaded.typography)
        typography.yOffset = 0
        chapterTypographies = [typography]

        let viewWidth = effectiveViewportWidth
        let viewHeight = effectiveViewportHeight

        contentSize = CGSize(width: viewWidth, height: typography.totalHeight)

        let chapterView = makeChapterView(for: typography)
        addSubview(chapterView)
        chapterViews[loaded.chapter.index] = chapterView

        if let charPos = targetCharPos, charPos > 0 {
            // Find line corresponding to charPos with 100% precision
            if let line = typography.lines.first(where: { line in
                charPos >= line.charRange.lowerBound && charPos < line.charRange.upperBound
            }) ?? typography.lines.first(where: { line in
                line.charRange.lowerBound >= charPos
            }) {
                let targetY = max(0, min(typography.totalHeight - viewHeight, line.y - paddingTop))
                contentOffset = CGPoint(x: 0, y: targetY)
            } else {
                contentOffset = .zero
            }
        } else if toEnd {
            let targetY = max(0, typography.totalHeight - viewHeight)
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

    // MARK: - Typography Generation & Layout

    /// Typesets with the current style/viewport. `cached` lets callers reuse an existing
    /// typography when the content has not changed.
    private func typeset(_ chapter: BookChapter, rawContent: String,
                         cached: ChapterTypography? = nil) -> ChapterTypography {
        if let cached = cached,
           abs(cached.totalHeight) > 0.1,
           cached.rawContent == rawContent {
            return cached
        }

        return TypographyEngine.typeset(
            chapter: chapter,
            content: rawContent,
            containerWidth: effectiveViewportWidth,
            containerHeight: effectiveViewportHeight,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paddingLeading: paddingLeading,
            paddingTrailing: paddingTrailing,
            paddingTop: paddingTop,
            paddingBottom: paddingBottom,
            imageStyle: imageStyle,
            justify: justify
        )
    }

    private func makeChapterView(for typography: ChapterTypography) -> ChapterCanvasLayerView {
        let frame = CGRect(x: 0, y: typography.yOffset, width: effectiveViewportWidth, height: typography.totalHeight)
        let view = ChapterCanvasLayerView(frame: frame)
        view.typography = typography
        view.fontSize = fontSize
        view.lineSpacing = lineSpacing
        view.letterSpacing = letterSpacing
        view.textColor = textColor
        view.accentColor = accentColor
        view.paddingLeading = paddingLeading
        view.paddingTrailing = paddingTrailing
        view.justify = justify
        view.aloudParagraph = aloudParagraph
        view.aloudIsActive = aloudIsActive
        view.isLastChapterInBook = (typography.chapter.index >= totalChaptersCount - 1)
        if typography.chapter.index + 1 < chaptersMeta.count {
            view.nextChapterTitle = chaptersMeta[typography.chapter.index + 1].title
        }
        return view
    }

    private func recalculateAllLayouts() {
        guard !chapterTypographies.isEmpty, effectiveViewportWidth > 0 else { return }

        var currentY: CGFloat = 0
        var newTypographies: [ChapterTypography] = []

        for typo in chapterTypographies {
            let updated = typeset(typo.chapter, rawContent: typo.rawContent)
            updated.yOffset = currentY
            newTypographies.append(updated)

            if let view = chapterViews[typo.chapter.index] {
                view.frame = CGRect(x: 0, y: currentY, width: effectiveViewportWidth, height: updated.totalHeight)
                view.typography = updated
                view.fontSize = fontSize
                view.lineSpacing = lineSpacing
                view.letterSpacing = letterSpacing
                view.textColor = textColor
                view.accentColor = accentColor
                view.paddingLeading = paddingLeading
                view.paddingTrailing = paddingTrailing
                view.justify = justify
                view.aloudParagraph = aloudParagraph
                view.aloudIsActive = aloudIsActive
                view.setNeedsDisplay()
            }

            currentY += updated.totalHeight
        }

        chapterTypographies = newTypographies
        contentSize = CGSize(width: effectiveViewportWidth, height: currentY)
    }

    // MARK: - Seamless Bidirectional Chapter Chaining

    private func loadPreviousChapter() async {
        guard !isLoadingPrevious, let first = chapterTypographies.first, first.chapter.index > 0 else { return }
        let prevIndex = first.chapter.index - 1
        isLoadingPrevious = true

        guard let loaded = await onRequestChapter?(prevIndex) else {
            isLoadingPrevious = false
            return
        }

        let viewWidth = effectiveViewportWidth
        let prevTypo = typeset(loaded.chapter, rawContent: loaded.content, cached: loaded.typography)
        let addedHeight = prevTypo.totalHeight

        isPrependingChapter = true
        for typo in chapterTypographies {
            typo.yOffset += addedHeight
            if let view = chapterViews[typo.chapter.index] {
                view.frame.origin.y += addedHeight
            }
        }

        prevTypo.yOffset = 0
        chapterTypographies.insert(prevTypo, at: 0)

        let prevView = makeChapterView(for: prevTypo)
        addSubview(prevView)
        chapterViews[loaded.chapter.index] = prevView

        contentSize = CGSize(width: viewWidth, height: contentSize.height + addedHeight)
        contentOffset = CGPoint(x: contentOffset.x, y: contentOffset.y + addedHeight)

        isPrependingChapter = false
        isLoadingPrevious = false

        pruneDistantChapters()
    }

    private func loadNextChapter() async {
        guard !isLoadingNext, let last = chapterTypographies.last, last.chapter.index < totalChaptersCount - 1 else { return }
        let nextIndex = last.chapter.index + 1
        isLoadingNext = true

        guard let loaded = await onRequestChapter?(nextIndex) else {
            isLoadingNext = false
            return
        }

        let viewWidth = effectiveViewportWidth
        let currentBottom = contentSize.height
        let nextTypo = typeset(loaded.chapter, rawContent: loaded.content, cached: loaded.typography)
        nextTypo.yOffset = currentBottom
        chapterTypographies.append(nextTypo)

        let nextView = makeChapterView(for: nextTypo)
        addSubview(nextView)
        chapterViews[loaded.chapter.index] = nextView

        contentSize = CGSize(width: viewWidth, height: currentBottom + nextTypo.totalHeight)
        isLoadingNext = false

        pruneDistantChapters()
    }

    private func pruneDistantChapters() {
        guard chapterTypographies.count > 5 else { return }
        while chapterTypographies.count > 4 {
            if let first = chapterTypographies.first, first.chapter.index < activeChapterIndex - 1 {
                let removedHeight = first.totalHeight
                chapterViews[first.chapter.index]?.removeFromSuperview()
                chapterViews.removeValue(forKey: first.chapter.index)
                chapterTypographies.removeFirst()

                for typo in chapterTypographies {
                    typo.yOffset -= removedHeight
                    chapterViews[typo.chapter.index]?.frame.origin.y -= removedHeight
                }
                contentSize = CGSize(width: effectiveViewportWidth, height: contentSize.height - removedHeight)
                contentOffset = CGPoint(x: contentOffset.x, y: max(0, contentOffset.y - removedHeight))
            } else if let last = chapterTypographies.last, last.chapter.index > activeChapterIndex + 2 {
                chapterViews[last.chapter.index]?.removeFromSuperview()
                chapterViews.removeValue(forKey: last.chapter.index)
                chapterTypographies.removeLast()
                contentSize = CGSize(width: effectiveViewportWidth, height: last.yOffset)
            } else {
                break
            }
        }
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // The selection highlight is anchored to chapter coordinates; scrolling away would
        // leave it over the wrong glyphs, so any user scroll dismisses it. The machine is
        // idle between presses, so this only fires after a finalized selection.
        if activeSelection != nil, !isPrependingChapter {
            clearSelection()
        }
        guard !isPrependingChapter, bounds.height > 0 else { return }

        let offsetY = scrollView.contentOffset.y
        let viewHeight = bounds.height

        // 1. Detect active chapter at reading focus line (top of viewport reading line)
        let readingY = offsetY + paddingTop
        if let current = chapterTypographies.first(where: { readingY >= $0.yOffset && readingY < ($0.yOffset + $0.totalHeight) }) {
            if activeChapterIndex != current.chapter.index {
                activeChapterIndex = current.chapter.index
                onChapterChange?(current.chapter.index, current.chapter.title)
            }

            let relY = readingY - current.yOffset
            if relY <= current.titleTotalHeight {
                onCharOffsetChange?(0)
            } else if let line = current.lines.first(where: { ($0.y + $0.height) >= relY }) {
                onCharOffsetChange?(line.charRange.lowerBound)
            }
        }

        // 2. Check top boundary: only load previous chapter when user actually scrolls UP past the top boundary!
        if offsetY < -15, let first = chapterTypographies.first, first.chapter.index > 0 {
            Task { @MainActor in
                await self.loadPreviousChapter()
            }
        }

        // 3. Check bottom boundary for loading next chapter (within 1000pt of bottom)
        let distToBottom = contentSize.height - (offsetY + viewHeight)
        if distToBottom < 1000, let last = chapterTypographies.last, last.chapter.index < totalChaptersCount - 1 {
            Task { @MainActor in
                await self.loadNextChapter()
            }
        }
    }

}

// MARK: - SwiftUI Bridge Representable

public struct ReaderScrollCanvasView: UIViewRepresentable {
    public let loadedChapter: LoadedChapter?
    public let chaptersMeta: [BookChapter]
    public let currentChapterIndex: Int
    public let scrollSessionId: UUID
    public let targetCharPos: Int?
    public let readerConfig: ReaderConfig
    public let aloudParagraph: String
    public let aloudIsActive: Bool

    public let onChapterChange: (Int, String) -> Void
    public let onCharOffsetChange: (Int) -> Void
    public let onTapZone: (ClickActionCode) -> Void
    public let onRequestChapter: (Int) async -> LoadedChapter?
    public var isTextSelectionEnabled: Bool = true
    public var onSelectionChanged: ((Int, Range<Int>?, CGRect) -> Void)? = nil
    var selectionChapterIndex: Int = 0
    var selectionRange: Range<Int>? = nil

    public init(
        loadedChapter: LoadedChapter?,
        chaptersMeta: [BookChapter],
        currentChapterIndex: Int,
        scrollSessionId: UUID,
        targetCharPos: Int? = nil,
        readerConfig: ReaderConfig,
        aloudParagraph: String,
        aloudIsActive: Bool,
        onChapterChange: @escaping (Int, String) -> Void,
        onCharOffsetChange: @escaping (Int) -> Void,
        onTapZone: @escaping (ClickActionCode) -> Void,
        onRequestChapter: @escaping (Int) async -> LoadedChapter?,
        isTextSelectionEnabled: Bool = true,
        onSelectionChanged: ((Int, Range<Int>?, CGRect) -> Void)? = nil,
        selectionChapterIndex: Int = 0,
        selectionRange: Range<Int>? = nil
    ) {
        self.loadedChapter = loadedChapter
        self.chaptersMeta = chaptersMeta
        self.currentChapterIndex = currentChapterIndex
        self.scrollSessionId = scrollSessionId
        self.targetCharPos = targetCharPos
        self.readerConfig = readerConfig
        self.aloudParagraph = aloudParagraph
        self.aloudIsActive = aloudIsActive
        self.onChapterChange = onChapterChange
        self.onCharOffsetChange = onCharOffsetChange
        self.onTapZone = onTapZone
        self.onRequestChapter = onRequestChapter
        self.isTextSelectionEnabled = isTextSelectionEnabled
        self.onSelectionChanged = onSelectionChanged
        self.selectionChapterIndex = selectionChapterIndex
        self.selectionRange = selectionRange
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
        view.isTextSelectionEnabled = isTextSelectionEnabled
        view.onSelectionChanged = onSelectionChanged

        context.coordinator.currentSessionId = scrollSessionId
        context.coordinator.renderedChapterIndex = loadedChapter?.chapter.index
        if let chapter = loadedChapter {
            view.resetToChapter(loaded: chapter, targetCharPos: targetCharPos)
        }
        return view
    }

    public func updateUIView(_ uiView: ContinuousScrollReaderUIView, context: Context) {
        uiView.onChapterChange = onChapterChange
        uiView.onCharOffsetChange = onCharOffsetChange
        uiView.onTapZone = onTapZone
        uiView.onRequestChapter = onRequestChapter
        uiView.isTextSelectionEnabled = isTextSelectionEnabled
        uiView.onSelectionChanged = onSelectionChanged
        uiView.syncSelectionState(chapterIndex: selectionChapterIndex, range: selectionRange)

        uiView.updateConfiguration(
            fontSize: readerConfig.fontSize,
            lineSpacing: readerConfig.lineSpacing,
            letterSpacing: readerConfig.letterSpacing,
            paragraphSpacing: readerConfig.paragraphSpacing,
            paddingLeading: readerConfig.paddingLeading,
            paddingTrailing: readerConfig.paddingTrailing,
            paddingTop: readerConfig.paddingTop,
            paddingBottom: readerConfig.paddingBottom,
            textColor: UIColor(readerConfig.effectiveTextColor),
            accentColor: .systemBlue,
            justify: readerConfig.prefs.textFullJustify,
            imageStyle: readerConfig.prefs.imageStyle,
            tapActions: readerConfig.clickActionList,
            aloudParagraph: aloudParagraph,
            aloudIsActive: aloudIsActive,
            chaptersMeta: chaptersMeta
        )

        // SwiftUI diffs a representable structurally, so a new `scrollSessionId` reaches
        // `updateUIView` only when some other field also changed in that render pass. A chapter
        // jump lands while `loadedChapter` is still the chapter being read (the parent moves
        // `currentChapterIndex` first and rebuilds `loadedChapters` a network round trip
        // later), so a session-id-only check would reset the canvas onto that stale chapter
        // here, then find the id unchanged once the target arrives and never render it.
        //
        // Reset when the parent points at a chapter the canvas has not been asked to show
        // yet, rather than when the canvas merely sits ahead of it: scrolling inside the
        // canvas advances it without the parent reloading, and that must never be yanked back.
        if let chapter = loadedChapter, chapter.chapter.index == currentChapterIndex {
            if context.coordinator.currentSessionId != scrollSessionId
                || context.coordinator.renderedChapterIndex != chapter.chapter.index {
                context.coordinator.currentSessionId = scrollSessionId
                context.coordinator.renderedChapterIndex = chapter.chapter.index
                uiView.resetToChapter(loaded: chapter, targetCharPos: targetCharPos)
            }
        } else if context.coordinator.currentSessionId != scrollSessionId {
            // Chapter is still in flight; consume the id so its arrival is not mistaken for a
            // second jump, and leave the canvas on what it already shows.
            context.coordinator.currentSessionId = scrollSessionId
        }
    }

    public class Coordinator {
        var parent: ReaderScrollCanvasView
        var currentSessionId: UUID?
        /// Chapter the canvas was last told to render, so a jump whose session-id diff was
        /// dropped can still be detected here.
        var renderedChapterIndex: Int?

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
        targetCharPos: Int? = nil,
        readerConfig: Any,
        aloudParagraph: String,
        aloudIsActive: Bool,
        onChapterChange: @escaping (Int, String) -> Void,
        onCharOffsetChange: @escaping (Int) -> Void,
        onTapZone: @escaping (ClickActionCode) -> Void,
        onRequestChapter: @escaping (Int) async -> Any?,
        isTextSelectionEnabled: Bool = true,
        onSelectionChanged: ((Int, Range<Int>?, CGRect) -> Void)? = nil,
        selectionChapterIndex: Int = 0,
        selectionRange: Range<Int>? = nil
    ) {}

    public var body: some View {
        EmptyView()
    }
}

#endif

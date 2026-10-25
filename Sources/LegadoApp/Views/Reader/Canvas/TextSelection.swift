import Foundation
import CoreText
#if canImport(LegadoCore)
import LegadoCore
#endif

// MARK: - Selection Geometry (Plan 第一批 Part 4: 文本选词联动)
//
// Pure CoreText math shared by the paged `CoreTextUIView` and the scroll
// `ChapterCanvasLayerView`, kept platform-neutral so `TypographySelectionTests` can run it
// through `swift test` on macOS. All index arithmetic uses the chapter-content Character
// offset basis — the same basis as `TypographyLine.charRange`, 全书搜索 jumps and
// `Bookmark.chapterPos`.

public enum SelectionGeometry {

    /// Builds the CTLine used for index/x measurement. Must carry the exact attributes the
    /// canvases draw with (font + kern), otherwise offsets drift.
    static func measuringLine(for text: String, fontSize: CGFloat, letterSpacing: CGFloat) -> CTLine? {
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        var attrs: [CFString: Any] = [kCTFontAttributeName: font]
        if letterSpacing != 0 {
            attrs[kCTKernAttributeName] = letterSpacing
        }
        guard let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else {
            return nil
        }
        return CTLineCreateWithAttributedString(attrStr)
    }

    /// UTF-16 index inside `text` for a point `x` measured from the line draw origin.
    /// Taps left of the first glyph and right of the last glyph clamp to 0 / length.
    public static func utf16Index(in text: String, atX x: CGFloat, fontSize: CGFloat, letterSpacing: CGFloat) -> Int {
        guard !text.isEmpty, let line = measuringLine(for: text, fontSize: fontSize, letterSpacing: letterSpacing) else {
            return 0
        }
        let length = (text as NSString).length
        let idx = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
        return min(max(0, idx), length)
    }

    /// Character-basis index inside `text` for `x`. The chapter-content offset basis is
    /// Character-based, so UTF-16 hits from CoreText get converted before leaving this method.
    public static func charIndex(in text: String, atX x: CGFloat, fontSize: CGFloat, letterSpacing: CGFloat) -> Int {
        let u16 = utf16Index(in: text, atX: x, fontSize: fontSize, letterSpacing: letterSpacing)
        return characterIndex(fromUTF16: u16, in: text)
    }

    /// Converts a UTF-16 offset into a Character-count offset (falls back to the clamped
    /// character count when the offset lands inside a surrogate pair).
    public static func characterIndex(fromUTF16 u16: Int, in text: String) -> Int {
        let clamped = min(max(0, u16), (text as NSString).length)
        let u16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clamped, limitedBy: text.utf16.endIndex)
            ?? text.utf16.endIndex
        guard let charIdx = String.Index(u16Index, within: text) else {
            return text.count
        }
        return text.distance(from: text.startIndex, to: charIdx)
    }

    /// Leading-edge x of the character at `charIndex`, measured from the line draw origin.
    /// `isTrailingEdge` returns the position after the glyph instead (the selection end).
    public static func xOffset(in text: String, atCharacterIndex index: Int,
                               fontSize: CGFloat, letterSpacing: CGFloat, isTrailingEdge: Bool = false) -> CGFloat {
        guard !text.isEmpty, let line = measuringLine(for: text, fontSize: fontSize, letterSpacing: letterSpacing) else {
            return 0
        }
        let clamped = min(max(0, index), text.count)
        // Character-basis index → UTF-16 offset for CoreText.
        let charIdx = text.index(text.startIndex, offsetBy: min(clamped, text.count))
        let u16 = text[text.startIndex..<charIdx].utf16.count
        let resolved = CTLineGetOffsetForStringIndex(line, u16, nil)
        if isTrailingEdge {
            // For the trailing edge walk one UTF-16 unit further so the caret sits after the glyph.
            let nsLen = (text as NSString).length
            if u16 < nsLen {
                return CTLineGetOffsetForStringIndex(line, u16 + 1, nil)
            }
        }
        return resolved
    }

    /// Word range around `index` inside `paragraph`: latin/digit runs expand to the whole
    /// token, CJK characters and punctuation select themselves. Chapter offset basis comes
    /// from the callers adding the paragraph start offset.
    public static func wordRange(in paragraph: String, index: Int) -> Range<Int> {
        let chars = Array(paragraph)
        guard chars.indices.contains(index) else {
            return index..<(index + 1)
        }
        // CJK ideographs/kana/hangul count as `isLetter` but read one glyph at a time —
        // expanding 「玄幻小说」 to the whole phrase is wrong for 选词.
        func isExpandable(_ c: Character) -> Bool {
            guard let scalar = c.unicodeScalars.first else { return false }
            let v = scalar.value
            let isCJK = (0x2E80...0x9FFF).contains(v)      // CJK radicals, blocks, unified
                || (0x3040...0x30FF).contains(v)           // kana
                || (0xAC00...0xD7AF).contains(v)           // hangul syllables
                || (0xF900...0xFAFF).contains(v)           // CJK compatibility ideographs
            return !isCJK && (c.isLetter || c.isNumber)
        }
        if isExpandable(chars[index]) {
            var lo = index
            var hi = index
            while lo > 0 && isExpandable(chars[lo - 1]) { lo -= 1 }
            while hi + 1 < chars.count && isExpandable(chars[hi + 1]) { hi += 1 }
            return lo..<(hi + 1)
        }
        return index..<(index + 1)
    }
}

// MARK: - ChapterTypography selection queries

extension ChapterTypography {

    /// The line whose vertical span contains chapter-coordinate `y` (top-based, like
    /// `TypographyLine.y`). Falls back to the last line above `y` so taps just under a line
    /// still select it.
    public func line(atY y: CGFloat) -> TypographyLine? {
        if let exact = lines.first(where: { y >= $0.y && y < $0.y + $0.height }) {
            return exact
        }
        return lines.last { $0.y <= y }
    }

    /// Chapter-start offset of the paragraph `line` belongs to (Character basis). Word
    /// expansion needs paragraph-local indices; the paragraph's first line owns the offset.
    public func paragraphStartOffset(of line: TypographyLine) -> Int {
        var start = line.charRange.lowerBound
        for candidate in lines.reversed() where candidate.index < line.index {
            if candidate.paragraphText == line.paragraphText {
                start = candidate.charRange.lowerBound
            } else if candidate.charRange.upperBound <= start {
                break
            }
        }
        return start
    }

    /// Chapter-content char offset at a point in chapter coordinates. `x` is measured from
    /// the leading text edge — the same origin the canvases draw lines at minus
    /// `paddingLeading` (callers on the scroll canvas subtract it themselves).
    public func charIndex(atX x: CGFloat, y: CGFloat,
                          fontSize: CGFloat, letterSpacing: CGFloat) -> Int? {
        guard let line = line(atY: y) else { return nil }
        let localIdx = SelectionGeometry.charIndex(in: line.text, atX: x,
                                                   fontSize: fontSize, letterSpacing: letterSpacing)
        return line.charRange.lowerBound + localIdx
    }

    /// Highlight rectangles for `range` in chapter coordinates (x includes
    /// `paddingLeading`, y is absolute chapter space). One rect per covered line, which is
    /// how Android `DynamicLayout`-style selection draws too.
    public func selectionRects(for range: Range<Int>, paddingLeading: CGFloat,
                               fontSize: CGFloat, letterSpacing: CGFloat) -> [CGRect] {
        guard !range.isEmpty else { return [] }
        var rects: [CGRect] = []
        for line in lines {
            let overlap = range.clamped(to: line.charRange)
            guard !overlap.isEmpty else { continue }
            let localLo = overlap.lowerBound - line.charRange.lowerBound
            let localHi = overlap.upperBound - line.charRange.lowerBound
            let x0 = paddingLeading + SelectionGeometry.xOffset(
                in: line.text, atCharacterIndex: localLo,
                fontSize: fontSize, letterSpacing: letterSpacing)
            let x1 = paddingLeading + SelectionGeometry.xOffset(
                in: line.text, atCharacterIndex: localHi,
                fontSize: fontSize, letterSpacing: letterSpacing, isTrailingEdge: true)
            guard x1 > x0 else { continue }
            rects.append(CGRect(x: x0, y: line.y, width: x1 - x0, height: line.height))
        }
        return rects
    }
}

// MARK: - Selection render helpers shared by both canvases

public enum SelectionRenderer {
    /// Hit radius (points) around a selection handle inside which a new long press counts as
    /// "adjust this boundary" instead of a fresh word selection.
    public static let handleHitRadius: CGFloat = 30

    /// The rect a handle dot should be drawn at: the line-end edge of the boundary char.
    public static func handleCenter(forRects rects: [CGRect], atStart: Bool) -> CGPoint? {
        guard let first = rects.first, let last = rects.last else { return nil }
        if atStart {
            return CGPoint(x: first.minX, y: first.midY)
        }
        return CGPoint(x: last.maxX, y: last.midY)
    }

    static func drawRects(_ rects: [CGRect], in ctx: CGContext, accent: CGColor) {
        ctx.saveGState()
        ctx.setFillColor(accent)
        for rect in rects {
            let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    static func drawHandles(_ rects: [CGRect], in ctx: CGContext, accent: CGColor,
                            atStart: Bool, atEnd: Bool) {
        guard rects.count > 0 else { return }
        ctx.saveGState()
        ctx.setFillColor(accent)
        if atStart, let c = handleCenter(forRects: rects, atStart: true) {
            ctx.fillEllipse(in: CGRect(x: c.x - 5, y: c.y + 2, width: 10, height: 10))
        }
        if atEnd, let c = handleCenter(forRects: rects, atStart: false) {
            ctx.fillEllipse(in: CGRect(x: c.x - 5, y: c.y - 12, width: 10, height: 10))
        }
        ctx.restoreGState()
    }
}

#if os(iOS)
import UIKit

/// Gesture state machine shared by both canvases: long-press picks the word under the
/// finger, dragging while held extends the selection, and a long press landing on one of the
/// existing handles adjusts that boundary instead. The canvases own hit-testing; the reader
/// only receives finalized ranges.
final class SelectionGestureMachine {
    enum Mode {
        case idle
        case selecting(anchor: Int, head: Int)     // chapter offsets, anchor = press origin
        case adjusting(boundary: AdjustedBoundary, fixed: Int)
    }

    enum AdjustedBoundary { case start, end }

    /// Set by the owning canvas when a selection already exists on screen.
    var existingRange: Range<Int>?
    var existingStartHandle: CGPoint = .zero
    var existingEndHandle: CGPoint = .zero

    private(set) var mode: Mode = .idle

    func reset() { mode = .idle }

    /// - Returns: the new chapter-content range, or nil when the press did not land on text.
    func began(atChapterOffset offset: Int?, touchPoint: CGPoint) -> Range<Int>? {
        // 1. Handle grab: adjust the nearest boundary of the existing selection.
        if let existing = existingRange {
            let startDist = hypot(touchPoint.x - existingStartHandle.x, touchPoint.y - existingStartHandle.y)
            let endDist = hypot(touchPoint.x - existingEndHandle.x, touchPoint.y - existingEndHandle.y)
            if startDist <= SelectionRenderer.handleHitRadius, startDist <= endDist {
                mode = .adjusting(boundary: .start, fixed: existing.upperBound)
                return existing
            }
            if endDist <= SelectionRenderer.handleHitRadius {
                mode = .adjusting(boundary: .end, fixed: existing.lowerBound)
                return existing
            }
        }
        // 2. Fresh word selection.
        guard let offset = offset else {
            mode = .idle
            return nil
        }
        mode = .selecting(anchor: offset, head: offset)
        return offset..<(offset + 1)
    }

    func changed(headChapterOffset head: Int?) -> Range<Int>? {
        switch mode {
        case .selecting(let anchor, _):
            guard let head = head else { return selectionRange(anchor: anchor, head: anchor) }
            mode = .selecting(anchor: anchor, head: head)
            return selectionRange(anchor: anchor, head: head)
        case .adjusting(let boundary, let fixed):
            guard let head = head else { return nil }
            switch boundary {
            case .start:
                guard head < fixed else { return nil }
                return head..<fixed
            case .end:
                guard head > fixed else { return nil }
                return fixed..<head
            }
        case .idle:
            return nil
        }
    }

    func ended() {
        // Keep `mode` for the canvas to read the final range; the next press calls began().
    }

    private func selectionRange(anchor: Int, head: Int) -> Range<Int> {
        anchor <= head ? anchor..<(head + 1) : head..<(anchor + 1)
    }
}
#endif

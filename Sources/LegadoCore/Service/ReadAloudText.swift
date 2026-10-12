import Foundation

/// Pure text handling for read-aloud, extracted so the offset contract is testable without
/// an audio session.
///
/// Android splits speech by **paragraph** (`BaseReadAloudService.newReadAloud` splits the
/// chapter on newlines) and tracks progress as a chapter-relative character offset. That
/// offset is the same quantity as `Book.durChapterPos`, `Bookmark.chapterPos` and the
/// WebDAV progress files, so a change here silently breaks all three.
public enum ReadAloudText {

    /// One entry per paragraph, in document order, with blank and whitespace-only lines
    /// dropped.
    public static func paragraphs(in chapterText: String) -> [String] {
        chapterText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Character offset of paragraph `index`, counting the newlines between paragraphs.
    public static func offset(of paragraphs: [String], at index: Int) -> Int {
        guard index > 0, !paragraphs.isEmpty else { return 0 }
        let clamped = min(index, paragraphs.count)
        return paragraphs.prefix(clamped).reduce(0) { $0 + $1.count + 1 }
    }

    /// Index of the paragraph containing `position`.
    public static func paragraphIndex(containing position: Int, in paragraphs: [String]) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        guard position > 0 else { return 0 }
        var offset = 0
        for (index, paragraph) in paragraphs.enumerated() {
            if offset + paragraph.count >= position { return index }
            offset += paragraph.count + 1
        }
        return paragraphs.count - 1
    }

    /// Android's `AppPattern.notReadAloudRegex` — a line of nothing but whitespace,
    /// punctuation, symbols or control characters has nothing worth speaking.
    public static func isSpeakable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "^(\\s|\\p{P}|\\p{C}|\\p{Z}|\\p{S})+$")
        else { return true }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) == nil
    }

    /// Walks away from `index` until a speakable paragraph is found, so stepping never stops
    /// on a line of decorations. Returns `nil` when the whole remainder is unspeakable,
    /// which is the caller's cue to move to another chapter.
    public static func nextSpeakableIndex(_ paragraphs: [String], from index: Int, forward: Bool) -> Int? {
        guard !paragraphs.isEmpty else { return nil }
        var candidate = index
        for _ in 0..<paragraphs.count {
            guard candidate >= 0, candidate < paragraphs.count else { return nil }
            if isSpeakable(paragraphs[candidate]) { return candidate }
            candidate += forward ? 1 : -1
        }
        return nil
    }
}

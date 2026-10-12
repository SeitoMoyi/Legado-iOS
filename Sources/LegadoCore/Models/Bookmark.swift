import Foundation

/// Persistence for bookmarks. The stored array uses Android's `bookmark.json` key names.
public enum BookmarkStore {
    public static let key = "legado_bookmarks_v1"

    public static func load(from defaults: UserDefaults = .standard) -> [Bookmark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let loaded = TolerantJSON.decodeList(Bookmark.self, from: data, fallback: Bookmark()) ?? []
        return sorted(loaded)
    }

    public static func save(_ bookmarks: [Bookmark], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: key)
    }

    /// Android's DAO orders by book, then chapter, then position, using `collate localized`.
    /// Plain `<` sorts Chinese titles by code point instead, so use localized comparison to
    /// keep the grouping the same on both platforms.
    public static func sorted(_ bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.sorted { lhs, rhs in
            let byName = lhs.bookName.localizedStandardCompare(rhs.bookName)
            if byName != .orderedSame { return byName == .orderedAscending }
            let byAuthor = lhs.bookAuthor.localizedStandardCompare(rhs.bookAuthor)
            if byAuthor != .orderedSame { return byAuthor == .orderedAscending }
            if lhs.chapterIndex != rhs.chapterIndex { return lhs.chapterIndex < rhs.chapterIndex }
            return lhs.chapterPos < rhs.chapterPos
        }
    }

    public static func importJSON(_ text: String, into existing: [Bookmark]) -> [Bookmark] {
        guard let data = text.data(using: .utf8),
              let imported = TolerantJSON.decodeList(Bookmark.self, from: data, fallback: Bookmark())
        else { return existing }
        var result = existing
        for bookmark in imported {
            if let index = result.firstIndex(where: { $0.time == bookmark.time }) {
                result[index] = bookmark
            } else {
                result.append(bookmark)
            }
        }
        return sorted(result)
    }

    public static func exportJSON(_ bookmarks: [Bookmark]) -> String? {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Markdown export, matching Android's `BookmarkFragment` "导出(MD)" layout:
    /// `## 书名 作者` / `#### 章节` / `###### 原文` / `###### 摘要`.
    public static func exportMarkdown(_ bookmarks: [Bookmark]) -> String {
        var lines: [String] = []
        var currentKey = ""
        for bookmark in sorted(bookmarks) {
            if bookmark.bookKey != currentKey {
                currentKey = bookmark.bookKey
                lines.append("## \(bookmark.bookName) \(bookmark.bookAuthor)")
                lines.append("")
            }
            lines.append("#### \(bookmark.chapterName)")
            lines.append("")
            lines.append("###### \(bookmark.bookText)")
            lines.append("")
            if !bookmark.content.isEmpty {
                lines.append("###### \(bookmark.content)")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// A reading bookmark. Field names are the exact GSON keys Android writes to
/// `bookmark.json` (`data/entities/Bookmark.kt`).
///
/// Bookmarks are tied to a book by **name + author**, not by `bookUrl`. That is
/// deliberate: it is what makes a bookmark survive 换源, when the url changes but the
/// book does not.
public struct Bookmark: Codable, Identifiable, Equatable {
    /// Milliseconds since epoch; also Android's primary key, so it doubles as the id.
    public var time: Int64
    public var bookName: String
    public var bookAuthor: String
    public var chapterIndex: Int
    /// Character offset inside the chapter, counting from the title line. Same unit as
    /// `Book.durChapterPos` and the WebDAV progress files.
    public var chapterPos: Int
    public var chapterName: String
    /// The page/paragraph text captured when the bookmark was made.
    public var bookText: String
    /// User note.
    public var content: String

    public var id: Int64 { time }

    public init(
        time: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        bookName: String = "",
        bookAuthor: String = "",
        chapterIndex: Int = 0,
        chapterPos: Int = 0,
        chapterName: String = "",
        bookText: String = "",
        content: String = ""
    ) {
        self.time = time
        self.bookName = bookName
        self.bookAuthor = bookAuthor
        self.chapterIndex = chapterIndex
        self.chapterPos = chapterPos
        self.chapterName = chapterName
        self.bookText = bookText
        self.content = content
    }

    public static func key(bookName: String, bookAuthor: String) -> String {
        "\(bookName)\u{1}\(bookAuthor)"
    }

    public var bookKey: String { Self.key(bookName: bookName, bookAuthor: bookAuthor) }
}

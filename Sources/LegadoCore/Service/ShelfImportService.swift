import Foundation

/// Android's exported book list contains name/author/intro. It is a search list, not a
/// bookshelf backup: URLs, device file paths and reading progress are resolved separately.
public struct ShelfBookInfo: Codable, Equatable, Identifiable {
    public var id: String { name + "\u{1}" + author }
    public var name: String
    public var author: String
    public var intro: String?
    public init(name: String, author: String = "", intro: String? = nil) { self.name = name; self.author = author; self.intro = intro }
}

public enum ShelfImportService {
    public static let maximumBytes = 16 * 1024 * 1024
    public static let maximumBooks = 1000

    public static func parse(_ data: Data) throws -> [ShelfBookInfo] {
        guard data.count <= maximumBytes else { throw RuleSubscriptionError.tooLarge }
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw RuleSubscriptionError.invalidData }
        guard array.count <= maximumBooks else { throw WebDAVError.custom("书单最多支持一次导入 1000 本") }
        var seen = Set<String>()
        let books = array.compactMap { object -> ShelfBookInfo? in
            guard let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let book = ShelfBookInfo(name: name.trimmingCharacters(in: .whitespacesAndNewlines), author: (object["author"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines), intro: object["intro"] as? String)
            return seen.insert(book.id).inserted ? book : nil
        }
        guard !books.isEmpty else { throw RuleSubscriptionError.invalidData }
        return books
    }

    public static func load(_ input: String, session: URLSession = .shared) async throws -> [ShelfBookInfo] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = RuleSubscriptionService.validURL(text) else { return try parse(Data(text.utf8)) }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WebDAVError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, "书单下载失败")
        }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= maximumBytes else { throw RuleSubscriptionError.tooLarge }
        return try parse(Data(contentsOf: file))
    }

    /// Exact title and author match Android WebBook.preciseSearchAwait's filter. Batches
    /// bound fan-out and the winning match cancels remaining requests in that batch.
    public static func find(_ info: ShelfBookInfo, sources: [BookSource]) async throws -> Book? {
        let enabled = sources.filter { $0.enabled != false && !($0.searchUrl ?? "").isEmpty }
        for offset in stride(from: 0, to: enabled.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(enabled[offset..<min(offset + 4, enabled.count)])
            let found = await withTaskGroup(of: Book?.self) { group -> Book? in
                for source in batch {
                    group.addTask {
                        guard !Task.isCancelled,
                              let results = try? await BookSearchService.shared.search(source: source, key: info.name),
                              !Task.isCancelled,
                              let hit = results.first(where: { $0.name == info.name && $0.author == info.author }) else { return nil }
                        return Book(bookUrl: hit.bookUrl, name: hit.name, author: hit.author, kind: hit.kind,
                            coverUrl: hit.coverUrl, intro: hit.intro ?? info.intro, origin: source.bookSourceUrl,
                            originName: source.bookSourceName, tocUrl: hit.bookUrl, wordCount: hit.wordCount,
                            latestChapterTitle: hit.latestChapterTitle)
                    }
                }
                for await value in group {
                    if let book = value { group.cancelAll(); return book }
                }
                return nil
            }
            try Task.checkCancellation()
            if let found = found { return found }
        }
        return nil
    }
}

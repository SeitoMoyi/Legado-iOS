import Foundation

/// A book found on another source that can replace the current one.
public struct ChangeSourceCandidate: Identifiable, Equatable {
    public let source: BookSource
    public let found: SearchBook
    /// Filled in only when the caller asked for the optional TOC / word-count checks.
    public var chapterCount: Int?
    public var mappedChapterIndex: Int?
    public var chapterWordCount: Int?
    public var respondTime: Int64?

    public var id: String { source.bookSourceUrl }

    public init(source: BookSource, found: SearchBook, chapterCount: Int? = nil,
                mappedChapterIndex: Int? = nil, chapterWordCount: Int? = nil, respondTime: Int64? = nil) {
        self.source = source
        self.found = found
        self.chapterCount = chapterCount
        self.mappedChapterIndex = mappedChapterIndex
        self.chapterWordCount = chapterWordCount
        self.respondTime = respondTime
    }
}

/// Finds alternative sources for a book, the engine behind 换源.
///
/// Two modes, matching Android:
/// - `candidates` is the interactive list. The **title must match exactly**; the author is
///   only checked when `checkAuthor` is on, and then as a substring, because sources disagree
///   about translators and annotations far more often than about titles.
/// - `verifiedCandidates` additionally pulls the TOC and the current chapter body before
///   returning a hit. That is the expensive mode 自动换源 uses, where a title that leads to an
///   unreadable book is worse than no match at all.
public final class ChangeSourceService {
    public static let shared = ChangeSourceService()

    /// Android caps this at `AppConst.MAX_THREAD`; 8 keeps a slow source from starving the
    /// reader's own prefetching.
    public static let maxConcurrent = 8
    static let perSourceTimeout: UInt64 = 60_000_000_000

    public init() {}

    // MARK: - Author normalisation

    /// Strips "作者：", "作 者:" and a trailing "著", which is how Android compares authors
    /// across sources (`AppPattern.authorRegex`).
    public static func normalizeAuthor(_ raw: String) -> String {
        var text = raw
        for prefix in ["作者:", "作者：", "作 者:", "作 者："] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("著") { text = String(text.dropLast()) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when `found` may stand in for `book`.
    public static func matches(book: Book, found: SearchBook, checkAuthor: Bool) -> Bool {
        let titleWanted = book.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleWanted.isEmpty, found.name.trimmingCharacters(in: .whitespacesAndNewlines) == titleWanted
        else { return false }
        guard checkAuthor else { return true }
        let wanted = normalizeAuthor(book.author)
        guard !wanted.isEmpty, wanted != "未知作者" else { return true }
        return normalizeAuthor(found.author).contains(wanted)
    }

    // MARK: - Search

    public func candidates(book: Book, sources: [BookSource], checkAuthor: Bool,
                           page: Int = 1) -> AsyncStream<ChangeSourceCandidate> {
        stream(book: book, sources: sources, checkAuthor: checkAuthor, page: page,
               requireReadable: false)
    }

    /// Confirms each hit can actually produce a TOC and the current chapter's text.
    public func verifiedCandidates(book: Book, sources: [BookSource],
                                   page: Int = 1) -> AsyncStream<ChangeSourceCandidate> {
        stream(book: book, sources: sources, checkAuthor: true, page: page,
               requireReadable: true)
    }

    private func stream(book: Book, sources: [BookSource], checkAuthor: Bool,
                        page: Int, requireReadable: Bool) -> AsyncStream<ChangeSourceCandidate> {
        let usable = sources.filter { $0.enabled != false && !($0.searchUrl ?? "").isEmpty }
        return AsyncStream { continuation in
            Task {
                // Bounded fan-out in chunks: `numberOfChildren` is not available, and a
                // single unbounded group would let one slow source stall the whole search.
                var index = 0
                while index < usable.count {
                    let chunk = Array(usable[index..<min(index + Self.maxConcurrent, usable.count)])
                    index += chunk.count
                    let found = await withTaskGroup(of: [ChangeSourceCandidate].self) { group in
                        for source in chunk {
                            group.addTask {
                                await self.search(source: source, book: book, checkAuthor: checkAuthor,
                                                  page: page, requireReadable: requireReadable)
                            }
                        }
                        var all: [ChangeSourceCandidate] = []
                        for await batch in group { all.append(contentsOf: batch) }
                        return all
                    }
                    for candidate in found {
                        if Task.isCancelled { break }
                        continuation.yield(candidate)
                    }
                }
                continuation.finish()
            }
        }
    }

    private func search(source: BookSource, book: Book, checkAuthor: Bool, page: Int,
                        requireReadable: Bool) async -> [ChangeSourceCandidate] {
        let started = Date()
        let results = await withTaskGroup(of: [SearchBook].self) { group in
            group.addTask {
                (try? await BookSearchService.shared.search(source: source, key: book.name, page: page)) ?? []
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.perSourceTimeout)
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }

        let responded = Int64(Date().timeIntervalSince(started) * 1000)
        var found = results.filter { Self.matches(book: book, found: $0, checkAuthor: checkAuthor) }
        if requireReadable {
            found = await filterReadable(found, book: book, source: source)
        }
        return found.map { hit in
            ChangeSourceCandidate(source: source, found: hit, respondTime: responded)
        }
    }

    /// Drops hits whose TOC cannot be fetched or whose current chapter has no text.
    private func filterReadable(_ hits: [SearchBook], book: Book, source: BookSource) async -> [SearchBook] {
        var kept: [SearchBook] = []
        for hit in hits {
            let probe = Book(bookUrl: hit.bookUrl, name: hit.name, author: hit.author,
                             origin: source.bookSourceUrl, originName: source.bookSourceName,
                             tocUrl: hit.bookUrl)
            guard let chapters = try? await BookContentService.shared.fetchChapterList(book: probe,
                                                                                       source: source),
                  !chapters.isEmpty else { continue }
            let index = ChapterMatcher.mapChapter(oldIndex: book.durChapterIndex,
                                                  oldTitle: book.durChapterTitle ?? "",
                                                  oldCount: max(book.totalChapterNum, book.durChapterIndex + 1),
                                                  newTitles: chapters.map { $0.title })
            guard index < chapters.count else { continue }
            if let text = try? await BookContentService.shared.fetchChapterContent(chapter: chapters[index],
                                                                                  source: source),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                kept.append(hit)
            }
        }
        return kept
    }

    // MARK: - Enrichment

    /// Loads a candidate's TOC and reports the chapter index the reader would land on.
    public func enrich(_ candidate: ChangeSourceCandidate, book: Book) async -> ChangeSourceCandidate {
        var enriched = candidate
        let probe = Book(bookUrl: candidate.found.bookUrl, name: candidate.found.name,
                         author: candidate.found.author, origin: candidate.source.bookSourceUrl,
                         originName: candidate.source.bookSourceName, tocUrl: candidate.found.bookUrl)
        guard let chapters = try? await BookContentService.shared.fetchChapterList(book: probe,
                                                                                  source: candidate.source),
              !chapters.isEmpty else { return enriched }

        enriched.chapterCount = chapters.count
        enriched.mappedChapterIndex = ChapterMatcher.mapChapter(
            oldIndex: book.durChapterIndex,
            oldTitle: book.durChapterTitle ?? "",
            oldCount: max(book.totalChapterNum, book.durChapterIndex + 1),
            newTitles: chapters.map { $0.title })
        return enriched
    }
}

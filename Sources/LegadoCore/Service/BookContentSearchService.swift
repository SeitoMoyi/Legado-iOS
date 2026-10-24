import Foundation

/// In-book full-text search across every chapter — the iOS counterpart of Android's
/// `SearchContentActivity`/`SearchBookContent` (Plan Phase 1 Part 5).
///
/// Design notes:
/// - **Cache first**: a chapter already on disk is searched offline; only misses go to the
///   network, bounded to `searchConcurrency` parallel fetches (`withTaskGroup`).
/// - **Progressive**: results stream out as an `AsyncStream` in chapter order so the sheet can
///   render hits while later chapters are still being fetched.
/// - **Cancellation-safe**: the consumer cancels the task that drives the stream; in-flight
///   group children observe `Task.isCancelled` between chapters.
/// - Matches run on the **processed** cached text when available (what the reader shows) and on
///   the raw fetched body otherwise; per chapter only the first `maxHitsPerChapter` hits are
///   reported, each carrying a context snippet and the character offset for jump-to-position.
public final class BookContentSearchService {

    public static let shared = BookContentSearchService()

    /// Parallel network fetches while searching. Chapter sources are third-party sites; a wide
    /// fan-out trips rate limits (Android uses a similar small pool).
    public var searchConcurrency: Int = 6
    /// First N hits reported per chapter — a chapter that repeats the keyword hundreds of times
    /// (e.g. a name list) would otherwise drown the result list.
    public var maxHitsPerChapter: Int = 3

    public init() {}

    // MARK: - Result model

    public struct Hit: Identifiable, Equatable {
        public var id: String { "\(chapterIndex)_\(charPosition)" }
        public let chapterIndex: Int
        public let chapterTitle: String
        /// UTF-16 offset of the match inside the chapter text the reader paginates — feeds
        /// `jumpToChapter(_:charPos:)` for 精准跳转.
        public let charPosition: Int
        public let matchedText: String
        /// Context around the hit, newline-flattened for one-line display.
        public let snippet: String
    }

    public struct Progress {
        public let chaptersSearched: Int
        public let totalChapters: Int
        public var isDone: Bool { chaptersSearched >= totalChapters }
    }

    public enum SearchEvent {
        case progress(Progress)
        case hit(Hit)
        case finished(chaptersSearched: Int, hits: Int, cancelled: Bool)
    }

    // MARK: - Query compilation

    public enum SearchQuery {
        case plain(String)
        case regex(NSRegularExpression)

        /// Builds a query; plain queries match case-insensitively (Android `contains` is
        /// case-insensitive for Latin text via `indexOf`-style folding in its adapter).
        public static func compile(_ raw: String, isRegex: Bool) -> SearchQuery? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if isRegex {
                guard let re = try? NSRegularExpression(pattern: trimmed, options: [.dotMatchesLineSeparators]) else {
                    return nil
                }
                return .regex(re)
            }
            return .plain(trimmed)
        }
    }

    // MARK: - Search

    /// Searches `chapters` of `book`, streaming events in chapter order.
    ///
    /// Network misses are fetched with `source`; pass `nil` to restrict the search to cached
    /// chapters (offline behaviour mirrors the caller's choice).
    public func search(
        book: Book,
        source: BookSource?,
        chapters: [BookChapter],
        query rawQuery: String,
        isRegex: Bool,
        includeUncached: Bool,
        context: ((BookChapter) -> ProcessContext)? = nil
    ) -> AsyncStream<SearchEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard let query = SearchQuery.compile(rawQuery, isRegex: isRegex) else {
                    continuation.yield(.finished(chaptersSearched: 0, hits: 0, cancelled: false))
                    continuation.finish()
                    return
                }

                var searched = 0
                var totalHits = 0
                let total = chapters.count

                func yieldProgress() {
                    continuation.yield(.progress(Progress(chaptersSearched: searched, totalChapters: total)))
                }

                // Chunked fan-out keeps chapter order in the output while bounding concurrency:
                // hits inside a chunk are re-sorted by index before yielding.
                let chunkSize = max(1, searchConcurrency)
                var index = 0
                while index < chapters.count {
                    if Task.isCancelled { break }
                    let chunk = Array(chapters[index..<min(index + chunkSize, chapters.count)])
                    let baseIndex = index

                    let chunkHits: [(Int, [Hit])] = await withTaskGroup(of: (Int, [Hit]).self) { group in
                        for (offset, chapter) in chunk.enumerated() {
                            let chapterIndex = baseIndex + offset
                            let processContext = context?(chapter)
                            group.addTask {
                                let hits = await self.searchChapter(
                                    book: book, source: source, chapter: chapter,
                                    chapterIndex: chapterIndex, query: query,
                                    includeUncached: includeUncached,
                                    context: processContext
                                )
                                return (chapterIndex, hits)
                            }
                        }
                        var collected: [(Int, [Hit])] = []
                        for await pair in group {
                            collected.append(pair)
                        }
                        return collected.sorted { $0.0 < $1.0 }
                    }

                    for (_, hits) in chunkHits {
                        for hit in hits {
                            continuation.yield(.hit(hit))
                            totalHits += 1
                        }
                        searched += 1
                        yieldProgress()
                    }
                    index += chunk.count
                }

                continuation.yield(.finished(chaptersSearched: searched, hits: totalHits, cancelled: Task.isCancelled))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Per-chapter

    /// Searches one chapter on the **display-basis text** — the same `finalize` pipeline
    /// (cache → 净化/替换) the reader paginates. Raw-basis offsets would land jumps at shifted
    /// positions because 净化 trims/indents the text.
    private func searchChapter(
        book: Book,
        source: BookSource?,
        chapter: BookChapter,
        chapterIndex: Int,
        query: SearchQuery,
        includeUncached: Bool,
        context: ProcessContext?
    ) async -> [Hit] {
        if Task.isCancelled { return [] }

        // `source: nil` restricts fetchChapterContent to cache/local — exactly the
        // includeUncached=false behaviour. Network failure degrades to "no hits".
        let effectiveSource = includeUncached ? source : nil
        guard !chapter.url.isEmpty || chapter.url.hasPrefix("txt://")
                || chapter.url.hasPrefix("epub://") || chapter.url.hasPrefix("file://") else {
            return []
        }

        let text: String
        do {
            text = try await BookContentService.shared.fetchChapterContent(
                chapter: chapter, source: effectiveSource, context: context)
        } catch {
            return []
        }
        if Task.isCancelled { return [] }
        guard !text.isEmpty else { return [] }

        return match(query: query, in: text, chapterIndex: chapterIndex, chapterTitle: chapter.title)
            .prefix(maxHitsPerChapter).map { $0 }
    }

    private func match(query: SearchQuery, in text: String, chapterIndex: Int, chapterTitle: String) -> [Hit] {
        switch query {
        case .plain(let keyword):
            let lowered = text
            var hits: [Hit] = []
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: keyword, range: searchStart..<lowered.endIndex) {
                hits.append(makeHit(text: text, range: range, chapterIndex: chapterIndex, chapterTitle: chapterTitle))
                if hits.count >= maxHitsPerChapter { break }
                searchStart = range.upperBound
            }
            return hits

        case .regex(let regex):
            let ns = text as NSString
            let matches = regex.matches(
                in: text, options: [],
                range: NSRange(location: 0, length: ns.length)
            ).prefix(maxHitsPerChapter)
            return matches.compactMap { m in
                guard let swiftRange = Range(m.range, in: text) else { return nil }
                return makeHit(text: text, range: swiftRange, chapterIndex: chapterIndex, chapterTitle: chapterTitle)
            }
        }
    }

    private func makeHit(text: String, range: Range<String.Index>, chapterIndex: Int, chapterTitle: String) -> Hit {
        let matched = String(text[range])
        // ±20 chars of context, snapped to non-empty content and newline-flattened.
        let contextStart = text.index(range.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let contextEnd = text.index(range.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
        let rawSnippet = String(text[contextStart..<contextEnd])
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let charPos = text.distance(from: text.startIndex, to: range.lowerBound)
        return Hit(
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            charPosition: charPos,
            matchedText: matched,
            snippet: rawSnippet
        )
    }
}

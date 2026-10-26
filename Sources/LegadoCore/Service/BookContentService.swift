import Foundation

public class BookContentService {
    public static let shared = BookContentService()

    public init() {}

    /// Fetches detailed book information (author, intro, tags, word count) and TOC chapters in a unified request
    /// A fetched table of contents plus whether it is the whole thing.
    ///
    /// `complete == false` means the crawl stopped at the page cap or the time budget. Callers
    /// must not cache such a list: a half-book TOC would later be compared against as if the
    /// book had shrunk, and 追更 would silently lose chapters.
    public struct TocResult {
        public let book: Book
        public let chapters: [BookChapter]
        public let complete: Bool

        public init(book: Book, chapters: [BookChapter], complete: Bool) {
            self.book = book
            self.chapters = chapters
            self.complete = complete
        }
    }

    public func fetchBookDetail(book: Book, source: BookSource, runPreUpdateJs: Bool = false) async throws -> (book: Book, chapters: [BookChapter]) {
        let result = try await fetchBookDetailResult(book: book, source: source, runPreUpdateJs: runPreUpdateJs)
        guard result.complete else {
            throw NSError(domain: "Legado.TOC", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "目录抓取未完成，请重试"])
        }
        return (result.book, result.chapters)
    }

    public func fetchBookDetailResult(book: Book, source: BookSource, runPreUpdateJs: Bool = false) async throws -> TocResult {
        try Task.checkCancellation()
        guard let tocRule = source.ruleToc else {
            return TocResult(book: book, chapters: [], complete: false)
        }

        let hasHook = runPreUpdateJs && !(tocRule.preUpdateJs?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let requestBook = hasHook ? try await SourcePreUpdateService().run(book: book, source: source) : book
        let headerEngine = JSEngine(bookSource: source, book: requestBook, baseUrl: source.bookSourceUrl)
        try headerEngine.checkReady()
        let headerToUse = JSEngine.resolvedSourceHeader(source, engine: headerEngine)
        // A pre-update bridge may have just refreshed details or relocated an expired URL.
        // Use its directory directly; fetching old details first would defeat reGetBook.
        let detailUrl = (hasHook || source.ruleBookInfo == nil) && !requestBook.tocUrl.isEmpty
            ? requestBook.tocUrl : requestBook.bookUrl
        guard let detailRequest = NetworkClient.parseLegadoUrl(detailUrl, defaultHeader: headerToUse,
                                                               baseUrl: hasHook ? requestBook.bookUrl : source.bookSourceUrl) else {
            throw URLError(.badURL)
        }
        let detailAnalyzer = try await makeAnalyzer(for: detailRequest, source: source, book: requestBook)
        let info = hasHook ? (book: requestBook, latestFromRule: "")
            : analyzeBookInfo(book: requestBook, source: source, analyzer: detailAnalyzer,
                              baseUrl: detailRequest.url.absoluteString)
        var updatedBook = info.book
        let latestFromRule = info.latestFromRule
        if updatedBook.tocUrl.isEmpty { updatedBook.tocUrl = detailRequest.url.absoluteString }
        guard let tocRequest = NetworkClient.parseLegadoUrl(updatedBook.tocUrl, defaultHeader: headerToUse,
                                                            baseUrl: detailRequest.url.absoluteString) else {
            throw URLError(.badURL)
        }
        let analyzer = pageKey(tocRequest) == pageKey(detailRequest)
            ? detailAnalyzer
            : try await makeAnalyzer(for: tocRequest, source: source, book: updatedBook)
        let jsEngine = analyzer.jsEngine

        // 1. Parse Chapters, following `nextTocUrl` when the source paginates its TOC
        var chapters = BookContentService.parseChapters(from: analyzer, tocRule: tocRule,
                                                        bookUrl: updatedBook.bookUrl, jsEngine: jsEngine)
        var complete = true

        if let nextTocRule = tocRule.nextTocUrl, !nextTocRule.isEmpty {
            let extra = try await collectTocPages(
                firstAnalyzer: analyzer, firstRequest: tocRequest, nextTocRule: nextTocRule, tocRule: tocRule,
                bookUrl: updatedBook.bookUrl, source: source, header: headerToUse)
            chapters.append(contentsOf: extra.chapters)
            complete = extra.complete
        }

        chapters = BookContentService.normalizeToc(chapters, listRule: tocRule.chapterList)
        chapters = try Self.formatChapters(chapters, script: tocRule.formatJs)

        updatedBook.totalChapterNum = chapters.count
        if !latestFromRule.isEmpty {
            updatedBook.latestChapterTitle = latestFromRule
        } else if let last = chapters.last {
            updatedBook.latestChapterTitle = last.title
        }
        return TocResult(book: updatedBook, chapters: chapters, complete: complete)
    }

    /// Details-only refresh for the preUpdateJs bridge; never invokes the hook recursively.
    public func fetchBookInfo(book: Book, source: BookSource) async throws -> Book {
        let engine = JSEngine(bookSource: source, book: book, baseUrl: source.bookSourceUrl)
        try engine.checkReady()
        let header = JSEngine.resolvedSourceHeader(source, engine: engine)
        guard let request = NetworkClient.parseLegadoUrl(book.bookUrl, defaultHeader: header,
                                                        baseUrl: source.bookSourceUrl) else { throw URLError(.badURL) }
        let analyzer = try await makeAnalyzer(for: request, source: source, book: book)
        return analyzeBookInfo(book: book, source: source, analyzer: analyzer, baseUrl: request.url.absoluteString).book
    }

    private func analyzeBookInfo(book: Book, source: BookSource, analyzer: RuleAnalyzer, baseUrl: String) -> (book: Book, latestFromRule: String) {
        var updatedBook = book
        var latestFromRule = ""
        if let infoRule = source.ruleBookInfo {
            let infoAnalyzer: RuleAnalyzer
            if let rule = infoRule.initRule, !rule.isEmpty,
               let root = analyzer.getElements(rule).first {
                infoAnalyzer = RuleAnalyzer(content: root, baseUrl: baseUrl,
                                            bookSource: source, jsEngine: analyzer.jsEngine)
            } else {
                infoAnalyzer = analyzer
            }
            let name = infoAnalyzer.getString(infoRule.name)
            if !name.isEmpty { updatedBook.name = name }
            let author = infoAnalyzer.getString(infoRule.author)
            if !author.isEmpty { updatedBook.author = author }
            let intro = infoAnalyzer.getString(infoRule.intro)
            if !intro.isEmpty { updatedBook.intro = Self.cleanHtml(intro) }
            let kinds = infoAnalyzer.getStringList(infoRule.kind)
            if !kinds.isEmpty { updatedBook.kind = kinds.joined(separator: ",") }
            let wordCount = infoAnalyzer.getString(infoRule.wordCount)
            if !wordCount.isEmpty { updatedBook.wordCount = wordCount }
            let cover = infoAnalyzer.getString(infoRule.coverUrl, isUrl: true)
            if !cover.isEmpty { updatedBook.coverUrl = cover }
            latestFromRule = infoAnalyzer.getString(infoRule.lastChapter)
            if !latestFromRule.isEmpty { updatedBook.latestChapterTitle = latestFromRule }
            let tocUrl = infoAnalyzer.getString(infoRule.tocUrl, isUrl: true)
            if !tocUrl.isEmpty { updatedBook.tocUrl = tocUrl }
        }
        if updatedBook.tocUrl.isEmpty { updatedBook.tocUrl = baseUrl }
        if let snapshot = analyzer.jsEngine.bookSnapshot() { updatedBook.variable = snapshot.variable }
        return (updatedBook, latestFromRule)
    }

    /// Fetches and parses the chapter list (Table of Contents)
    public func fetchChapterList(book: Book, source: BookSource) async throws -> [BookChapter] {
        let result = try await fetchBookDetail(book: book, source: source)
        return result.chapters
    }

    /// Fetches and cleans chapter text content.
    ///
    /// `nextChapterUrl` is the URL of the following chapter: the `nextContentUrl` loop stops
    /// as soon as it would leave the current chapter, mirroring Android `BookContent.kt`.
    ///
    /// `context` selects the 净化 pipeline. The disk cache deliberately stores text that has
    /// *not* been through `ContentProcessor`, so toggling 净化 or editing a rule takes effect
    /// immediately instead of requiring a cache wipe — Android caches the processed text and
    /// has that problem. Passing `nil` returns the raw text, which is what a source preview
    /// wants.
    public func fetchChapterContent(chapter: BookChapter, source: BookSource? = nil,
                                    nextChapterUrl: String? = nil,
                                    context: ProcessContext? = nil) async throws -> String {
        try Task.checkCancellation()
        // An edited local chapter is an explicit cache override, just like a network chapter.
        if let cached = getCachedChapterContent(bookUrl: chapter.bookUrl, chapterIndex: chapter.index), !cached.isEmpty {
            return await finalize(cached, context: context, chapter: chapter)
        }
        // Linkless volume headings have no HTTP resource. Formatting may change their title,
        // so identify them by a stable synthetic URL rather than a title prefix.
        if chapter.isVolume == true, chapter.url.hasPrefix("legado-volume://") {
            return await finalize(chapter.tag ?? "", context: context, chapter: chapter)
        }
        // File extensions alone do not make an HTTP chapter a local file.
        let localSchemes = ["file", "epub", "txt"]
        if localSchemes.contains(URL(string: chapter.url)?.scheme?.lowercased() ?? "")
            || localSchemes.contains(URL(string: chapter.bookUrl)?.scheme?.lowercased() ?? "") {
            if chapter.url.contains(".txt") {
                var localPath = ""
                if let u = URL(string: chapter.url), u.isFileURL {
                    localPath = u.path
                } else {
                    localPath = chapter.url.replacingOccurrences(of: "file://", with: "")
                }
                var targetFile = URL(fileURLWithPath: localPath)
                if !FileManager.default.fileExists(atPath: targetFile.path) {
                    let fileName = targetFile.lastPathComponent
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    targetFile = docs.appendingPathComponent("Books/TXT/\(CryptoUtils.md5(chapter.bookUrl))/\(fileName)")
                }
                if let raw = try? Data(contentsOf: targetFile) {
                    return await finalize(CharsetDetector.decode(raw), context: context, chapter: chapter)
                }
            }

            let text = EpubParser.extractChapterContent(fromUrlString: chapter.url, bookUrl: chapter.bookUrl)
            if !text.isEmpty {
                return await finalize(text, context: context, chapter: chapter)
            }
        }

        guard let source = source, let contentRule = source.ruleContent else {
            return ""
        }

        let headerEngine = JSEngine(bookSource: source, baseUrl: source.bookSourceUrl)
        try headerEngine.checkReady()
        let headerToUse = JSEngine.resolvedSourceHeader(source, engine: headerEngine)

        print("[Content] 🚀 [\(source.bookSourceName)] Fetching chapter '\(chapter.title)' from: \(chapter.url)")
        let collected = try await collectContentFragments(
            startUrl: chapter.url, source: source, contentRule: contentRule,
            header: headerToUse, nextChapterUrl: nextChapterUrl)
        try Task.checkCancellation()

        guard let firstPageUrl = collected.firstPageUrl else {
            print("[Content] ❌ [\(source.bookSourceName)] Failed to parse chapter URL: \(chapter.url)")
            return ""
        }

        var contentText = collected.fragments.joined(separator: "\n")

        // Source-level 全文替换. Android evaluates `replaceRegex` as a full rule (so it can
        // contain <js>); we support the common chainable `pattern##replacement##…` form.
        if let replaceRegex = contentRule.replaceRegex, !replaceRegex.isEmpty {
            contentText = BookContentService.applyReplacePairs(contentText, spec: replaceRegex)
        }

        // Clean up common web garbage and sanitize HTML tags
        contentText = BookContentService.cleanHtml(contentText, baseUrl: firstPageUrl)
        try Task.checkCancellation()

        // A truncated chapter must not be cached: the reader would keep showing the cut-off
        // version forever, because the cache is consulted before the network.
        if !contentText.isEmpty, collected.complete {
            saveCachedChapterContent(bookUrl: chapter.bookUrl, chapterIndex: chapter.index, content: contentText)
        }

        return await finalize(contentText, context: context, chapter: chapter)
    }

    /// Runs the 净化 pipeline when a context was supplied. The title is not included: the
    /// reader renders it from `BookChapter.title`.
    private func finalize(_ text: String, context: ProcessContext?, chapter: BookChapter) async -> String {
        guard var scoped = context else { return text }
        // The chapter, not the caller, owns the cache key so 「起效的替换」 can find this run.
        scoped.cacheKey = "\(chapter.bookUrl)|\(chapter.index)"
        let processed = await ContentProcessor.shared.process(rawContent: text, context: scoped)
        return processed.bodyText
    }

    // MARK: - Paginated sources (`nextTocUrl` / `nextContentUrl`)

    /// Android has no page ceiling and relies on the visited set plus a next-chapter
    /// comparison to terminate. iOS adds a hard cap because a runaway loop here would hang
    /// the reader with no way out.
    static let maxTocPages = 200
    static let maxContentPages = 50
    /// Wall-clock budgets that sit alongside the page caps. A page cap alone still allows 200
    /// sequential requests on a slow source; the budget bounds the wait the reader actually
    /// sees. Truncation is reported to the caller so nothing partial gets cached.
    static let tocTimeBudget: TimeInterval = 120
    static let contentTimeBudget: TimeInterval = 30
    /// Bounded fan-out for the multi-URL branch, mirroring Android's `threadCount`.
    static let maxConcurrentPages = 8

    private func makeAnalyzer(for parsed: NetworkClient.ParsedRequest, source: BookSource,
                              book: Book? = nil) async throws -> RuleAnalyzer {
        let fetched = try await NetworkClient.shared.request(parsed: parsed)
        try Task.checkCancellation()
        let engine = JSEngine(bookSource: source, book: book, baseUrl: fetched.url?.absoluteString ?? parsed.url.absoluteString)
        try engine.checkReady()
        let response = try engine.checkedResponse(fetched, requestedURL: parsed.url)
        guard (200..<400).contains(response.statusCode) else {
            throw NSError(domain: "Legado.HTTP", code: response.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(response.statusCode)"])
        }
        let absolute = response.url?.absoluteString ?? parsed.url.absoluteString
        return RuleAnalyzer(
            content: response.bodyString,
            baseUrl: absolute,
            bookSource: source,
            jsEngine: engine
        )
    }

    /// Reads the chapter list out of one already-fetched TOC page.
    static func parseChapters(from analyzer: RuleAnalyzer, tocRule: TocRule,
                              bookUrl: String, jsEngine: JSEngine) -> [BookChapter] {
        let pageUrl = analyzer.baseUrl ?? ""
        var chapters: [BookChapter] = []
        var listRule = tocRule.chapterList?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if listRule.hasPrefix("-") || listRule.hasPrefix("+") { listRule.removeFirst() }
        for (itemIndex, item) in analyzer.getElements(listRule).enumerated() {
            let itemAnalyzer = RuleAnalyzer(content: item, baseUrl: pageUrl,
                                            bookSource: nil, jsEngine: jsEngine)
            var chapter = BookChapter(bookUrl: bookUrl, url: "", title: "", index: 0)
            jsEngine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            chapter.title = itemAnalyzer.getString(tocRule.chapterName)
            guard !chapter.title.isEmpty else { continue }
            jsEngine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            let rawUrl = itemAnalyzer.getString(tocRule.chapterUrl).trimmingCharacters(in: .whitespacesAndNewlines)
            chapter.url = rawUrl
            jsEngine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            chapter.tag = itemAnalyzer.getString(tocRule.updateTime)
            jsEngine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            let isVolume = ruleIsTrue(itemAnalyzer.getString(tocRule.isVolume))
            let url: String
            if rawUrl.isEmpty, isVolume {
                url = "legado-volume://\(CryptoUtils.md5(pageUrl))/\(itemIndex)"
            } else {
                url = rawUrl.isEmpty ? pageUrl : itemAnalyzer.resolveUrl(rawUrl)
            }
            guard !url.isEmpty else { continue }
            chapter.url = url
            chapter.isVolume = isVolume
            jsEngine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            chapter.isVip = ruleIsTrue(itemAnalyzer.getString(tocRule.isVip))
            jsEngine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            chapter.isPay = ruleIsTrue(itemAnalyzer.getString(tocRule.isPay))
            chapter.index = chapters.count
            chapters.append(chapter)
        }
        return chapters
    }

    /// Android String.isTrue: any nonblank value except null / false / no / not / 0.
    static func ruleIsTrue(_ value: String) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value != "null" else { return false }
        return !["false", "no", "not", "0"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func chapterBindings(_ chapter: BookChapter) -> [String: Any] {
        ["bookUrl": chapter.bookUrl, "url": chapter.url, "title": chapter.title,
         "index": chapter.index, "isVolume": chapter.isVolume ?? false,
         "isVip": chapter.isVip ?? false, "isPay": chapter.isPay ?? false,
         "tag": chapter.tag ?? ""]
    }

    /// Android formats the final deduplicated, ordered list, sharing gInt across chapters.
    /// Script errors preserve the original title and do not prevent later titles formatting.
    static func formatChapters(_ chapters: [BookChapter], script: String?) throws -> [BookChapter] {
        guard let script = script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return chapters }
        let engine = JSEngine()
        engine.setGlobal(0, for: "gInt")
        let body = JSEngine.extractJSScript(from: script) ?? script
        return try chapters.map { chapter in
            try Task.checkCancellation()
            var formatted = chapter
            engine.setGlobal(Self.chapterBindings(chapter), for: "chapter")
            engine.setGlobal(chapter.index + 1, for: "index")
            engine.setGlobal(chapter.title, for: "title")
            if let title = engine.evalString(body) {
                formatted.title = title
            }
            if engine.didTimeOut { throw SourceRuntimeError.script(stage: "formatJs", message: "Script execution timed out") }
            return formatted
        }
    }

    /// Follows `nextTocUrl` past the first TOC page. A single next URL is crawled serially;
    /// several URLs mean the source exposes them all at once, so they are fetched with
    /// bounded concurrency and not recursed into — same split as Android.
    private func collectTocPages(firstAnalyzer: RuleAnalyzer, firstRequest: NetworkClient.ParsedRequest,
                                 nextTocRule: String, tocRule: TocRule, bookUrl: String,
                                 source: BookSource, header: String?) async throws
        -> (chapters: [BookChapter], complete: Bool) {
        var collected: [BookChapter] = []
        var visited: Set<String> = [pageKey(firstRequest)]
        var pages = 0
        let deadline = Date().addingTimeInterval(Self.tocTimeBudget)
        var candidates = firstAnalyzer.getStringList(nextTocRule, isUrl: true).map(trimmed).filter { !$0.isEmpty }

        while let pageUrl = candidates.first {
            try Task.checkCancellation()
            if candidates.count > 1 {
                let batch = try await fetchPagesConcurrently(
                    urls: candidates, source: source, header: header, visited: &visited,
                    limit: Self.maxTocPages - pages, deadline: deadline) { analyzer in
                        Self.parseChapters(from: analyzer, tocRule: tocRule, bookUrl: bookUrl,
                                           jsEngine: analyzer.jsEngine)
                    }
                collected.append(contentsOf: batch.values.flatMap { $0 })
                return (collected, batch.complete)
            }
            guard let parsed = NetworkClient.parseLegadoUrl(pageUrl, defaultHeader: header,
                                                            baseUrl: source.bookSourceUrl) else {
                return (collected, false)
            }
            if visited.contains(pageKey(parsed)) { break }
            guard pages < Self.maxTocPages, Date() < deadline else { return (collected, false) }
            visited.insert(pageKey(parsed))
            pages += 1
            let analyzer = try await makeAnalyzer(for: parsed, source: source)
            collected.append(contentsOf: Self.parseChapters(
                from: analyzer, tocRule: tocRule, bookUrl: bookUrl, jsEngine: analyzer.jsEngine))
            candidates = analyzer.getStringList(nextTocRule, isUrl: true).map(trimmed).filter { !$0.isEmpty }
        }
        return (collected, true)
    }

    /// Include POST bodies: a paginated API may use the same URL for every page.
    private func pageKey(_ request: NetworkClient.ParsedRequest) -> String {
        request.method + " " + request.url.absoluteString + " " + (request.body?.base64EncodedString() ?? "")
    }

    /// Shared bounded fan-out. Preserve document order and propagate failed / omitted pages
    /// instead of silently turning a partial result into a complete cache entry.
    private func fetchPagesConcurrently<Value>(urls: [String], source: BookSource, header: String?,
                                               visited: inout Set<String>, limit: Int, deadline: Date,
                                               parse: @escaping (RuleAnalyzer) -> Value?) async throws
        -> (values: [Value], complete: Bool) {
        var requests: [NetworkClient.ParsedRequest] = []
        var complete = true
        for url in urls {
            guard let request = NetworkClient.parseLegadoUrl(url, defaultHeader: header,
                                                             baseUrl: source.bookSourceUrl) else {
                complete = false
                continue
            }
            let key = pageKey(request)
            guard !visited.contains(key) else { continue }
            guard requests.count < limit else { complete = false; break }
            visited.insert(key)
            requests.append(request)
        }
        var values: [Value] = []
        var index = 0
        while index < requests.count {
            try Task.checkCancellation()
            guard Date() < deadline else { return (values, false) }
            let chunk = Array(requests[index..<min(index + Self.maxConcurrentPages, requests.count)])
            let batch = await withTaskGroup(of: (Int, Value?).self) { group in
                for (position, request) in chunk.enumerated() {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let analyzer = try await self.makeAnalyzer(for: request, source: source)
                            return (position, parse(analyzer))
                        } catch {
                            return (position, nil)
                        }
                    }
                }
                var results = Array<Value?>(repeating: nil, count: chunk.count)
                for await (position, value) in group { results[position] = value }
                return results
            }
            try Task.checkCancellation()
            if batch.contains(where: { $0 == nil }) { complete = false }
            values.append(contentsOf: batch.compactMap { $0 })
            index += chunk.count
        }
        return (values, complete)
    }

    /// Deduplicates by chapter URL keeping first-seen order, then re-indexes.
    ///
    /// A `-` prefix on `chapterList` means the source lists chapters newest-first and wants
    /// the result flipped. The double `reverse()` inside Android `BookChapterList` cancels
    /// out, so document order is the default and no flip is needed here.
    static func normalizeToc(_ chapters: [BookChapter], listRule: String?) -> [BookChapter] {
        var seen = Set<String>()
        var unique: [BookChapter] = []
        for chapter in chapters where !seen.contains(chapter.url) {
            seen.insert(chapter.url)
            unique.append(chapter)
        }
        if let rule = listRule, rule.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
            unique.reverse()
        }
        return unique.enumerated().map { position, chapter in
            var rebuilt = chapter
            rebuilt.index = position
            return rebuilt
        }
    }

    /// Follows `nextContentUrl` to assemble a chapter split over several pages.
    private func collectContentFragments(startUrl: String, source: BookSource, contentRule: ContentRule,
                                         header: String?, nextChapterUrl: String?) async throws
        -> (fragments: [String], firstPageUrl: String?, complete: Bool) {
        var fragments: [String] = []
        var visited: Set<String> = []
        var pageUrl = startUrl
        var pages = 0
        var firstPageUrl: String?
        var complete = true
        let deadline = Date().addingTimeInterval(Self.contentTimeBudget)

        while !pageUrl.isEmpty {
            try Task.checkCancellation()
            guard let parsed = NetworkClient.parseLegadoUrl(pageUrl, defaultHeader: header,
                                                             baseUrl: source.bookSourceUrl) else {
                return (fragments, firstPageUrl, false)
            }
            let key = pageKey(parsed)
            if visited.contains(key) { break }
            guard pages < Self.maxContentPages, Date() < deadline else {
                return (fragments, firstPageUrl, false)
            }
            visited.insert(key)
            pages += 1
            if firstPageUrl == nil { firstPageUrl = parsed.url.absoluteString }
            let analyzer = try await makeAnalyzer(for: parsed, source: source)
            let text = analyzer.getString(contentRule.content)
            if text.isEmpty { complete = false } else { fragments.append(text) }

            guard let nextRule = contentRule.nextContentUrl, !nextRule.isEmpty else { break }
            // Stop before the next chapter even when a rule returns an array of page links.
            let candidates = Array(analyzer.getStringList(nextRule, isUrl: true)
                .map(trimmed).filter { !$0.isEmpty }.prefix { $0 != nextChapterUrl })
            guard let first = candidates.first else { break }
            if candidates.count > 1 {
                let batch = try await fetchPagesConcurrently(
                    urls: candidates, source: source, header: header, visited: &visited,
                    limit: Self.maxContentPages - pages, deadline: deadline) { analyzer -> String? in
                        let text = analyzer.getString(contentRule.content)
                        return text.isEmpty ? nil : text
                    }
                fragments.append(contentsOf: batch.values)
                return (fragments, firstPageUrl, complete && batch.complete)
            }
            pageUrl = first
        }
        return (fragments, firstPageUrl, complete)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies the source-level `replaceRegex` written as `pattern##replacement##pattern2##…`
    /// as a chain, so several replacements compose instead of only the first pair winning.
    static func applyReplacePairs(_ text: String, spec: String) -> String {
        let segments = spec.components(separatedBy: "##")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = text
        var index = 0
        // Android prefixes an optional rule name; skip past anything that is not a pair.
        while index < segments.count - 1 {
            let pattern = segments[index]
            let replacement = segments[index + 1]
            if pattern.isEmpty {
                index += 1
                continue
            }
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = result as NSString
                result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length),
                                                       withTemplate: replacement)
            }
            index += 2
        }
        return result
    }

    // MARK: - Chapter Content Cache
    private func chapterCacheDirectory(bookUrl: String) -> URL {
        let hash = CryptoUtils.md5(bookUrl)
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = cacheBase.appendingPathComponent("ChapterCache/\(hash)")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func chapterCacheFile(bookUrl: String, chapterIndex: Int) -> URL {
        return chapterCacheDirectory(bookUrl: bookUrl).appendingPathComponent("\(chapterIndex).txt")
    }

    public func clearCachedChapter(bookUrl: String, chapterIndex: Int) {
        let file = chapterCacheFile(bookUrl: bookUrl, chapterIndex: chapterIndex)
        try? FileManager.default.removeItem(at: file)
    }

    public func getCachedChapterContent(bookUrl: String, chapterIndex: Int) -> String? {
        let file = chapterCacheFile(bookUrl: bookUrl, chapterIndex: chapterIndex)
        return try? String(contentsOf: file, encoding: .utf8)
    }

    public func saveCachedChapterContent(bookUrl: String, chapterIndex: Int, content: String) {
        guard !content.isEmpty else { return }
        let file = chapterCacheFile(bookUrl: bookUrl, chapterIndex: chapterIndex)
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    public func clearCache(for bookUrl: String) {
        let dir = chapterCacheDirectory(bookUrl: bookUrl)
        try? FileManager.default.removeItem(at: dir)
    }

    public func hasCachedChapter(bookUrl: String, chapterIndex: Int) -> Bool {
        let file = chapterCacheFile(bookUrl: bookUrl, chapterIndex: chapterIndex)
        return FileManager.default.fileExists(atPath: file.path)
    }

    private func nextChapterUrl(after index: Int, in chapters: [BookChapter]) -> String? {
        guard index + 1 < chapters.count else { return nil }
        return chapters[index + 1].url
    }

    /// Prefetches on the caller's task so leaving the reader cancels the active request
    /// and the remaining queue together. The reader owns this work, not the singleton.
    public func preDownloadChapters(around currentIndex: Int, chapters: [BookChapter], source: BookSource?, count: Int = 10) async {
        guard !Task.isCancelled, !chapters.isEmpty, currentIndex >= 0,
              currentIndex < chapters.count, count > 0 else { return }

        // 1. 优先预下载后续章节 (currentIndex + 1 到 currentIndex + count)
        let maxIndex = min(currentIndex + count, chapters.count - 1)
        if currentIndex + 1 <= maxIndex {
            for i in (currentIndex + 1)...maxIndex {
                if Task.isCancelled { return }
                let ch = chapters[i]
                if self.hasCachedChapter(bookUrl: ch.bookUrl, chapterIndex: ch.index) {
                    continue
                }
                _ = try? await self.fetchChapterContent(
                    chapter: ch, source: source,
                    nextChapterUrl: self.nextChapterUrl(after: i, in: chapters))
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms 节奏间隔，避免被防爬虫限流
            }
        }

        // 2. 预下载前面的章节 (currentIndex - 1 倒序到 currentIndex - count)
        let minIndex = max(0, currentIndex - count)
        if currentIndex - 1 >= minIndex {
            for i in stride(from: currentIndex - 1, through: minIndex, by: -1) {
                if Task.isCancelled { return }
                let ch = chapters[i]
                if self.hasCachedChapter(bookUrl: ch.bookUrl, chapterIndex: ch.index) {
                    continue
                }
                _ = try? await self.fetchChapterContent(
                    chapter: ch, source: source,
                    nextChapterUrl: self.nextChapterUrl(after: i, in: chapters))
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    public func getCacheCount(for bookUrl: String) -> Int {
        let dir = chapterCacheDirectory(bookUrl: bookUrl)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        return files.filter { $0.hasSuffix(".txt") }.count
    }

    /// Total bytes of cached chapter files for one book — the 缓存管理 size column.
    public func cacheSize(for bookUrl: String) -> Int64 {
        let dir = chapterCacheDirectory(bookUrl: bookUrl)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var total: Int64 = 0
        for file in files where file.hasSuffix(".txt") {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(file).path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Downloads chapter text for a specified range [startIndex...endIndex] with cancellation and progress reporting.
    /// Matches Android Legado `CacheBook.kt` / `CacheBookService.kt`.
    public func downloadChaptersRange(
        book: Book,
        chapters: [BookChapter],
        source: BookSource?,
        startIndex: Int,
        endIndex: Int,
        onProgress: @escaping (Int, Int) -> Void
    ) async -> (successCount: Int, skippedCount: Int, failedCount: Int) {
        guard !chapters.isEmpty, startIndex <= endIndex else { return (0, 0, 0) }
        let start = max(0, min(startIndex, chapters.count - 1))
        let end = max(start, min(endIndex, chapters.count - 1))
        let total = end - start + 1

        var success = 0
        var skipped = 0
        var failed = 0

        for (offset, i) in (start...end).enumerated() {
            if Task.isCancelled { break }
            let ch = chapters[i]
            if hasCachedChapter(bookUrl: ch.bookUrl, chapterIndex: ch.index) {
                skipped += 1
                onProgress(offset + 1, total)
                continue
            }

            do {
                let nextUrl = nextChapterUrl(after: i, in: chapters)
                _ = try await fetchChapterContent(chapter: ch, source: source, nextChapterUrl: nextUrl)
                success += 1
            } catch {
                failed += 1
            }
            onProgress(offset + 1, total)
            try? await Task.sleep(nanoseconds: 60_000_000) // 60ms friendly cadence
        }

        return (success, skipped, failed)
    }

    /// Sanitizes HTML text, converting <img> to [image:url], <p> and <br> to paragraphs, and stripping other tags
    public static func cleanHtml(_ raw: String, baseUrl: String? = nil) -> String {
        var text = raw

        // Convert <img> tags to \n\n[image:url]\n\n before stripping HTML tags
        let imgPattern = "(?i)<img\\s+[^>]*?>"
        if let imgRegex = try? NSRegularExpression(pattern: imgPattern) {
            let nsText = text as NSString
            let matches = imgRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let imgTag = nsText.substring(with: match.range)
                if let src = extractImageSrc(from: imgTag, baseUrl: baseUrl), !src.isEmpty {
                    text = (text as NSString).replacingCharacters(in: match.range, with: "\n\n[image:\(src)]\n\n")
                }
            }
        }

        // Convert <br> and <br/> to newlines
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        // Convert </p> to double newlines
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n\n", options: .regularExpression)
        // Strip <p ...> tags
        text = text.replacingOccurrences(of: "(?i)<p[^>]*>", with: "", options: .regularExpression)
        // Strip all other HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lrm;", with: "")
        text = text.replacingOccurrences(of: "&rlm;", with: "")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        // Collapse 3+ consecutive newlines to 2
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractImageSrc(from imgTag: String, baseUrl: String?) -> String? {
        let patterns = [
            "(?i)data-original\\s*=\\s*[\"']([^\"']+)[\"']",
            "(?i)data-src\\s*=\\s*[\"']([^\"']+)[\"']",
            "(?i)src\\s*=\\s*[\"']([^\"']+)[\"']"
        ]

        var rawSrc: String? = nil
        for pattern in patterns {
            if let rx = try? NSRegularExpression(pattern: pattern),
               let match = rx.firstMatch(in: imgTag, range: NSRange(location: 0, length: (imgTag as NSString).length)),
               match.numberOfRanges > 1 {
                let found = (imgTag as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !found.isEmpty && !found.hasPrefix("data:image") {
                    rawSrc = found
                    break
                }
            }
        }

        guard let src = rawSrc else { return nil }

        // Filter out decorative avatars/logos
        if src.contains("discord_logo") || src.contains("nophoto.png") {
            return nil
        }

        // Resolve relative URL
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            return src
        } else if src.hasPrefix("//") {
            return "https:" + src
        } else if let base = baseUrl, let baseObj = URL(string: base) {
            if src.hasPrefix("/") {
                let origin = "\(baseObj.scheme ?? "https")://\(baseObj.host ?? "")"
                return origin + src
            } else {
                return baseObj.deletingLastPathComponent().appendingPathComponent(src).absoluteString
            }
        }
        return src
    }
}

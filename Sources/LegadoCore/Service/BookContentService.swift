import Foundation

public class BookContentService {
    public static let shared = BookContentService()

    public init() {}

    /// Fetches detailed book information (author, intro, tags, word count) and TOC chapters in a unified request
    public func fetchBookDetail(book: Book, source: BookSource) async throws -> (book: Book, chapters: [BookChapter]) {
        guard let tocRule = source.ruleToc else {
            return (book, [])
        }

        let targetUrl = !book.tocUrl.isEmpty ? book.tocUrl : book.bookUrl
        var headerToUse = source.loginHeader ?? source.header
        if let h = headerToUse, (h.contains("<js>") || h.hasPrefix("@js:")) {
            let js = JSEngine(bookSource: source, baseUrl: source.bookSourceUrl)
            let script = h.contains("<js>") ? String(h[h.range(of: "<js>")!.upperBound..<h.range(of: "</js>")!.lowerBound]) : String(h.dropFirst(4))
            if let evaluated = js.context.evaluateScript(script)?.toString(), !evaluated.isEmpty && evaluated != "undefined" {
                headerToUse = evaluated
            }
        }

        print("[BookDetail] 🚀 [\(source.bookSourceName)] Fetching details and TOC from: \(targetUrl)")
        guard let parsedReq = NetworkClient.parseLegadoUrl(targetUrl, defaultHeader: headerToUse, baseUrl: source.bookSourceUrl) else {
            print("[BookDetail] ❌ [\(source.bookSourceName)] Failed to parse URL: \(targetUrl)")
            return (book, [])
        }

        let analyzer = try await makeAnalyzer(for: parsedReq, source: source)
        let jsEngine = analyzer.jsEngine

        // 1. Parse Chapters, following `nextTocUrl` when the source paginates its TOC
        var chapters = BookContentService.parseChapters(from: analyzer, tocRule: tocRule,
                                                        bookUrl: book.bookUrl, jsEngine: jsEngine)

        if let nextTocRule = tocRule.nextTocUrl, !nextTocRule.isEmpty {
            let extra = try await collectTocPages(
                firstAnalyzer: analyzer, nextTocRule: nextTocRule, tocRule: tocRule,
                bookUrl: book.bookUrl, source: source, header: headerToUse)
            chapters.append(contentsOf: extra)
        }

        chapters = BookContentService.normalizeToc(chapters, listRule: tocRule.chapterList)

        // 2. Parse Book Metadata (Author, Intro, Kind, WordCount)
        var updatedBook = book
        updatedBook.totalChapterNum = chapters.count
        if let lastCh = chapters.last, updatedBook.latestChapterTitle == nil || updatedBook.latestChapterTitle?.isEmpty == true {
            updatedBook.latestChapterTitle = lastCh.title
        }

        // Apply ruleBookInfo if configured
        if let infoRule = source.ruleBookInfo {
            let authorVal = analyzer.getString(infoRule.author)
            if !authorVal.isEmpty { updatedBook.author = authorVal }

            let introVal = analyzer.getString(infoRule.intro)
            if !introVal.isEmpty { updatedBook.intro = BookContentService.cleanHtml(introVal) }

            let kindVal = analyzer.getString(infoRule.kind)
            if !kindVal.isEmpty { updatedBook.kind = kindVal }

            let wordCountVal = analyzer.getString(infoRule.wordCount)
            if !wordCountVal.isEmpty { updatedBook.wordCount = wordCountVal }

            let coverVal = analyzer.getString(infoRule.coverUrl, isUrl: true)
            if !coverVal.isEmpty { updatedBook.coverUrl = coverVal }
        }

        // Apply intelligent JSON metadata extraction (e.g. for Novelia and generic novel REST APIs)
        if let body = analyzer.content as? String,
           let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Author extraction from JSON
            if updatedBook.author.isEmpty || updatedBook.author == "未知作者" {
                if let authorsArr = json["authors"] as? [[String: Any]] {
                    let names = authorsArr.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
                    if !names.isEmpty {
                        updatedBook.author = names.joined(separator: ", ")
                    }
                } else if let authorStr = json["author"] as? String, !authorStr.isEmpty {
                    updatedBook.author = authorStr
                }
            }

            // Real Introduction extraction from JSON
            if let introZh = json["introductionZh"] as? String, !introZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedBook.intro = introZh
            } else if let introJp = json["introductionJp"] as? String, !introJp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedBook.intro = introJp
            } else if let desc = json["description"] as? String, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedBook.intro = desc
            } else if let intro = json["intro"] as? String, !intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedBook.intro = intro
            }

            // Word Count
            if updatedBook.wordCount == nil || updatedBook.wordCount?.isEmpty == true {
                if let totalChars = json["totalCharacters"] as? Int {
                    if totalChars > 10000 {
                        updatedBook.wordCount = String(format: "%.1f万字", Double(totalChars) / 10000.0)
                    } else {
                        updatedBook.wordCount = "\(totalChars)字"
                    }
                }
            }

            // Kind / Tags
            if updatedBook.kind == nil || updatedBook.kind?.isEmpty == true {
                var tags: [String] = []
                if let t = json["type"] as? String, !t.isEmpty { tags.append(t) }
                if let kws = json["keywords"] as? [String] { tags.append(contentsOf: kws) }
                if !tags.isEmpty {
                    updatedBook.kind = tags.joined(separator: ",")
                }
            }
        }

        print("[BookDetail] ✅ [\(source.bookSourceName)] Parsed book '\(updatedBook.name)' by '\(updatedBook.author)', intro length: \(updatedBook.intro?.count ?? 0), chapters: \(chapters.count)")
        return (updatedBook, chapters)
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
        // If chapter points to a local file, extract directly from disk
        if chapter.url.hasPrefix("file://") || chapter.url.hasPrefix("epub://") || chapter.url.hasPrefix("txt://") || chapter.bookUrl.hasPrefix("file://") || chapter.bookUrl.hasPrefix("txt://") || chapter.url.contains(".xhtml") || chapter.url.contains(".html") || chapter.url.contains(".txt") {
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

        // Check local chapter cache first
        if let cached = getCachedChapterContent(bookUrl: chapter.bookUrl, chapterIndex: chapter.index), !cached.isEmpty {
            return await finalize(cached, context: context, chapter: chapter)
        }

        guard let source = source, let contentRule = source.ruleContent else {
            return ""
        }

        var chapterUrl = chapter.url
        if chapterUrl.contains("/chapter/"), !chapterUrl.contains("/api/novel/"), chapter.bookUrl.contains("/api/novel/") {
            if let chapterId = chapterUrl.components(separatedBy: "/chapter/").last?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines), !chapterId.isEmpty {
                let trimmedBookUrl = chapter.bookUrl.hasSuffix("/") ? String(chapter.bookUrl.dropLast()) : chapter.bookUrl
                chapterUrl = "\(trimmedBookUrl)/chapter/\(chapterId)"
            }
        }

        var headerToUse = source.loginHeader ?? source.header
        if let h = headerToUse, (h.contains("<js>") || h.hasPrefix("@js:")) {
            let js = JSEngine(bookSource: source, baseUrl: source.bookSourceUrl)
            let script = h.contains("<js>") ? String(h[h.range(of: "<js>")!.upperBound..<h.range(of: "</js>")!.lowerBound]) : String(h.dropFirst(4))
            if let evaluated = js.context.evaluateScript(script)?.toString(), !evaluated.isEmpty && evaluated != "undefined" {
                headerToUse = evaluated
            }
        }

        print("[Content] 🚀 [\(source.bookSourceName)] Fetching chapter '\(chapter.title)' from: \(chapterUrl)")
        let collected = try await collectContentFragments(
            startUrl: chapterUrl, source: source, contentRule: contentRule,
            header: headerToUse, nextChapterUrl: nextChapterUrl)

        guard let firstPageUrl = collected.firstPageUrl else {
            print("[Content] ❌ [\(source.bookSourceName)] Failed to parse chapter URL: \(chapterUrl)")
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

        if !contentText.isEmpty {
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
        return processed.bodyText.isEmpty ? processed.text : processed.bodyText
    }

    // MARK: - Paginated sources (`nextTocUrl` / `nextContentUrl`)

    /// Android has no page ceiling and relies on the visited set plus a next-chapter
    /// comparison to terminate. iOS adds a hard cap because a runaway loop here would hang
    /// the reader with no way out.
    static let maxTocPages = 200
    static let maxContentPages = 50
    /// Bounded fan-out for the multi-URL branch, mirroring Android's `threadCount`.
    static let maxConcurrentPages = 8

    private func makeAnalyzer(for parsed: NetworkClient.ParsedRequest, source: BookSource) async throws -> RuleAnalyzer {
        let response = try await NetworkClient.shared.request(parsed: parsed)
        let absolute = parsed.url.absoluteString
        return RuleAnalyzer(
            content: response.bodyString,
            baseUrl: absolute,
            bookSource: source,
            jsEngine: JSEngine(bookSource: source, baseUrl: absolute)
        )
    }

    /// Reads the chapter list out of one already-fetched TOC page.
    static func parseChapters(from analyzer: RuleAnalyzer, tocRule: TocRule,
                              bookUrl: String, jsEngine: JSEngine) -> [BookChapter] {
        let pageUrl = analyzer.baseUrl ?? ""
        var chapters: [BookChapter] = []
        for (_, item) in analyzer.getElements(tocRule.chapterList).enumerated() {
            let itemAnalyzer = RuleAnalyzer(content: item, baseUrl: pageUrl,
                                            bookSource: nil, jsEngine: jsEngine)
            let title = itemAnalyzer.getString(tocRule.chapterName)
            let url = itemAnalyzer.getString(tocRule.chapterUrl, isUrl: true)
            guard !title.isEmpty, !url.isEmpty else { continue }
            chapters.append(BookChapter(bookUrl: bookUrl, url: url, title: title, index: chapters.count))
        }
        return chapters
    }

    /// Follows `nextTocUrl` past the first TOC page. A single next URL is crawled serially;
    /// several URLs mean the source exposes them all at once, so they are fetched with
    /// bounded concurrency and not recursed into — same split as Android.
    private func collectTocPages(firstAnalyzer: RuleAnalyzer, nextTocRule: String, tocRule: TocRule,
                                 bookUrl: String, source: BookSource,
                                 header: String?) async throws -> [BookChapter] {
        var collected: [BookChapter] = []
        var visited: Set<String> = [firstAnalyzer.baseUrl ?? ""]
        var pages = 0

        let candidates = firstAnalyzer.getStringList(nextTocRule, isUrl: true).map(trimmed).filter { !$0.isEmpty }
        guard let first = candidates.first else { return [] }

        if candidates.count > 1 {
            collected.append(contentsOf: await fetchChaptersConcurrently(
                urls: candidates, tocRule: tocRule, bookUrl: bookUrl, source: source, header: header))
            return collected
        }
        var pageUrl = first

        while !pageUrl.isEmpty, pages < Self.maxTocPages {
            guard let parsed = NetworkClient.parseLegadoUrl(pageUrl, defaultHeader: header,
                                                            baseUrl: source.bookSourceUrl) else { break }
            let absolute = parsed.url.absoluteString
            if visited.contains(absolute) { break }
            visited.insert(absolute)
            pages += 1

            let analyzer = try await makeAnalyzer(for: parsed, source: source)
            collected.append(contentsOf: BookContentService.parseChapters(
                from: analyzer, tocRule: tocRule, bookUrl: bookUrl, jsEngine: analyzer.jsEngine))

            let nexts = analyzer.getStringList(nextTocRule, isUrl: true).map(trimmed).filter { !$0.isEmpty }
            if nexts.count > 1 {
                collected.append(contentsOf: await fetchChaptersConcurrently(
                    urls: nexts, tocRule: tocRule, bookUrl: bookUrl, source: source, header: header))
                break
            }
            pageUrl = nexts.first ?? ""
        }
        return collected
    }

    private func fetchChaptersConcurrently(urls: [String], tocRule: TocRule, bookUrl: String,
                                           source: BookSource, header: String?) async -> [BookChapter] {
        var results = Array<[BookChapter]>(repeating: [], count: urls.count)
        var index = 0
        while index < urls.count {
            let chunk = Array(urls[index..<min(index + Self.maxConcurrentPages, urls.count)])
            let offset = index
            await withTaskGroup(of: (Int, [BookChapter]).self) { group in
                for (i, url) in chunk.enumerated() {
                    group.addTask {
                        guard let parsed = NetworkClient.parseLegadoUrl(url, defaultHeader: header,
                                                                        baseUrl: source.bookSourceUrl),
                              let analyzer = try? await self.makeAnalyzer(for: parsed, source: source)
                        else { return (offset + i, []) }
                        return (offset + i, BookContentService.parseChapters(
                            from: analyzer, tocRule: tocRule, bookUrl: bookUrl, jsEngine: analyzer.jsEngine))
                    }
                }
                for await (position, chapters) in group {
                    results[position] = chapters
                }
            }
            index += chunk.count
        }
        return results.flatMap { $0 }
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
        -> (fragments: [String], firstPageUrl: String?) {
        var fragments: [String] = []
        var visited: Set<String> = []
        var pageUrl = startUrl
        var firstPageUrl: String? = nil

        while !pageUrl.isEmpty, fragments.count < Self.maxContentPages {
            guard let parsed = NetworkClient.parseLegadoUrl(pageUrl, defaultHeader: header,
                                                             baseUrl: source.bookSourceUrl) else { break }
            let absolute = parsed.url.absoluteString
            if visited.contains(absolute) { break }
            visited.insert(absolute)
            if firstPageUrl == nil { firstPageUrl = absolute }

            let analyzer = try await makeAnalyzer(for: parsed, source: source)
            let text = analyzer.getString(contentRule.content)
            if !text.isEmpty { fragments.append(text) }

            guard let nextRule = contentRule.nextContentUrl, !nextRule.isEmpty else { break }
            let candidates = analyzer.getStringList(nextRule, isUrl: true).map(trimmed).filter { !$0.isEmpty }
            guard let first = candidates.first else { break }

            if candidates.count > 1 {
                fragments.append(contentsOf: await fetchContentsConcurrently(
                    urls: candidates, contentRule: contentRule, source: source, header: header))
                break
            }

            // Stop when the "next page" is really the next chapter.
            if let stop = nextChapterUrl, stop == first { break }
            pageUrl = first
        }
        return (fragments, firstPageUrl)
    }

    private func fetchContentsConcurrently(urls: [String], contentRule: ContentRule,
                                           source: BookSource, header: String?) async -> [String] {
        var results = Array<String>(repeating: "", count: urls.count)
        var index = 0
        while index < urls.count {
            let chunk = Array(urls[index..<min(index + Self.maxConcurrentPages, urls.count)])
            let offset = index
            await withTaskGroup(of: (Int, String).self) { group in
                for (i, url) in chunk.enumerated() {
                    group.addTask {
                        guard let parsed = NetworkClient.parseLegadoUrl(url, defaultHeader: header,
                                                                        baseUrl: source.bookSourceUrl),
                              let analyzer = try? await self.makeAnalyzer(for: parsed, source: source)
                        else { return (offset + i, "") }
                        return (offset + i, analyzer.getString(contentRule.content))
                    }
                }
                for await (position, text) in group {
                    results[position] = text
                }
            }
            index += chunk.count
        }
        return results.filter { !$0.isEmpty }
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

    private func chapterCacheFile(bookUrl: String, chapterIndex: Int) -> URL {
        return chapterCacheDirectory(bookUrl: bookUrl).appendingPathComponent("\(chapterIndex).txt")
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

    private var preDownloadTask: Task<Void, Never>? = nil

    private func nextChapterUrl(after index: Int, in chapters: [BookChapter]) -> String? {
        guard index + 1 < chapters.count else { return nil }
        return chapters[index + 1].url
    }

    /// 仿照 Android Legado preDownload()：在后台自动预缓存当前章节前后各 10 章
    public func preDownloadChapters(around currentIndex: Int, chapters: [BookChapter], source: BookSource?, count: Int = 10) {
        preDownloadTask?.cancel()
        guard !chapters.isEmpty else { return }

        preDownloadTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

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
    }

    public func getCacheCount(for bookUrl: String) -> Int {
        let dir = chapterCacheDirectory(bookUrl: bookUrl)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        return files.filter { $0.hasSuffix(".txt") }.count
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

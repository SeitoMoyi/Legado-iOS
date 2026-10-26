import Foundation
import SwiftSoup

/// Service for fetching RSS feeds, parsing XML/JSON articles, and evaluating subscription rules.
public class RssService {
    public static let shared = RssService()

    public init() {}

    public struct RssCategory: Identifiable, Equatable {
        public var id: String { "\(title)_\(url)" }
        public let title: String
        public let url: String
    }

    /// One fetched page of articles plus the follow-up link extracted from `ruleNextPage`,
    /// so the article flow can stitch pages together on touch-bottom (Plan Phase 1 Part 1.4).
    public struct ArticlePage {
        public var articles: [RssArticle]
        public var nextPageUrl: String?
    }

    public func parseCategories(source: RssSource) -> [RssCategory] {
        (try? categoriesChecked(source: source)) ?? [RssCategory(title: "默认", url: source.sourceUrl)]
    }

    public func loadCategories(source: RssSource) async throws -> [RssCategory] {
        try Task.checkCancellation()
        let result = try categoriesChecked(source: source)
        try Task.checkCancellation()
        return result
    }

    private func categoriesChecked(source: RssSource) throws -> [RssCategory] {
        var text = source.sortUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let script = JSEngine.extractJSScript(from: text) {
            let engine = JSEngine(bookSource: source.scriptSource)
            let result = try engine.evalChecked(script: script, stage: "sortUrl")
            if let array = result as? [[String: Any]], let data = try? JSONSerialization.data(withJSONObject: array) {
                text = String(decoding: data, as: UTF8.self)
            } else { text = result.map(JSEngine.stringValue) ?? "" }
        }
        var pairs: [(String, String)] = []
        if let data = text.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            pairs = array.compactMap { item in
                guard let title = (item["title"] ?? item["name"]) as? String, let url = item["url"] as? String else { return nil }
                return (title, url)
            }
        } else {
            for line in text.replacingOccurrences(of: "&&", with: "\n").components(separatedBy: .newlines) {
                if let separator = line.range(of: "::") { pairs.append((String(line[..<separator.lowerBound]), String(line[separator.upperBound...]))) }
                else if !line.trimmingCharacters(in: .whitespaces).isEmpty { pairs.append(("默认", line)) }
            }
        }
        let categories = pairs.compactMap { title, raw -> RssCategory? in
            let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let resolved = url.contains("{{") ? url : URL(string: url, relativeTo: URL(string: source.sourceUrl))?.absoluteString ?? url
            return RssCategory(title: title.trimmingCharacters(in: .whitespaces), url: resolved)
        }
        return categories.isEmpty ? [RssCategory(title: "默认", url: source.sourceUrl)] : categories
    }

    /// Fetches one page of articles and resolves the `ruleNextPage` follow-up link.
    public func fetchArticlePage(source: RssSource, pageUrl: String, page: Int = 1) async throws -> ArticlePage {
        let engine = JSEngine(bookSource: source.scriptSource, baseUrl: source.sourceUrl)
        try engine.checkReady()
        let renderedUrl = resolveUrl(source: source, url: pageUrl, page: page, engine: engine)

        guard let parsed = NetworkClient.parseLegadoUrl(renderedUrl, defaultHeader: JSEngine.resolvedSourceHeader(source.scriptSource, engine: engine)) else {
            throw NSError(domain: "RssService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的订阅源地址"])
        }

        let fetched = try await NetworkClient.shared.request(parsed: parsed)
        try Task.checkCancellation()
        let response = try engine.checkedResponse(fetched, requestedURL: parsed.url)
        guard (200..<400).contains(response.statusCode) else { throw WebDAVError.serverError(response.statusCode, "订阅请求失败") }
        let rawBody = response.bodyString
        guard !rawBody.isEmpty else { return ArticlePage(articles: [], nextPageUrl: nil) }

        let articles = try parseArticlesFromContent(rawBody, source: source, categoryUrl: response.url?.absoluteString ?? parsed.url.absoluteString, engine: engine)
        let nextPage = resolveNextPageUrl(pageBody: rawBody, source: source, currentPageUrl: response.url?.absoluteString ?? parsed.url.absoluteString, engine: engine)
        return ArticlePage(articles: articles, nextPageUrl: nextPage)
    }

    /// Resolves `ruleNextPage` against the fetched page body; `nil` when absent or when the
    /// rule loops back to a URL already visited this flow.
    public func resolveNextPageUrl(pageBody: String, source: RssSource, currentPageUrl: String, engine: JSEngine? = nil) -> String? {
        guard let rule = source.ruleNextPage?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else {
            return nil
        }
        if rule.uppercased() == "PAGE" { return currentPageUrl }
        let analyzer = RuleAnalyzer(content: pageBody, baseUrl: currentPageUrl, bookSource: source.scriptSource, jsEngine: engine)
        let next = analyzer.getString(rule, isUrl: true).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty, next != currentPageUrl, next != source.sourceUrl else { return nil }
        return next
    }

    /// Expands `{{page}}` / relative paths against the source base URL.
    private func resolveUrl(source: RssSource, url: String, page: Int = 1, engine: JSEngine) -> String {
        var renderedUrl = url
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "<page>", with: "\(page)")
        renderedUrl = engine.renderTemplate(renderedUrl, variables: ["page": page, "baseUrl": source.sourceUrl])
        if let base = URL(string: source.sourceUrl), !renderedUrl.hasPrefix("http") {
            renderedUrl = URL(string: renderedUrl, relativeTo: base)?.absoluteString ?? renderedUrl
        }
        return renderedUrl
    }

    /// Parses articles from raw XML/HTML/JSON content using ruleArticles, ruleTitle, etc.
    public func parseArticlesFromContent(_ content: String, source: RssSource, categoryUrl: String, engine suppliedEngine: JSEngine? = nil) throws -> [RssArticle] {
        let engine = suppliedEngine ?? JSEngine(bookSource: source.scriptSource, baseUrl: categoryUrl)
        try engine.checkReady()
        let analyzer = RuleAnalyzer(content: content, baseUrl: categoryUrl, jsEngine: engine)

        // Rule for article item list: defaults to standard RSS `//item` or Atom `//entry` if not configured
        let articleRule = source.ruleArticles?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedArticleRule: String
        if let r = articleRule, !r.isEmpty {
            resolvedArticleRule = r
        } else {
            if content.contains("<item") {
                resolvedArticleRule = "//item"
            } else if content.contains("<entry") {
                resolvedArticleRule = "//entry"
            } else {
                resolvedArticleRule = "//item || //entry || class.article-item || tag.article"
            }
        }

        let reverse = resolvedArticleRule.hasPrefix("-")
        let rawItems = analyzer.getElements(reverse ? String(resolvedArticleRule.dropFirst()) : resolvedArticleRule)
        var articles: [RssArticle] = []

        for (index, item) in rawItems.enumerated() {
            let itemAnalyzer = RuleAnalyzer(content: item, baseUrl: categoryUrl, jsEngine: engine)

            let titleRule = source.ruleTitle ?? "//title/text() || title@text || a@text"
            let linkRule = source.ruleLink ?? "//link/text() || //link/@href || a@href"
            let descRule = source.ruleDescription ?? "//description/text() || //content/text() || //summary/text()"
            let pubDateRule = source.rulePubDate ?? "//pubDate/text() || //published/text() || //updated/text()"
            let imgRule = source.ruleImage ?? "//image/url/text() || img@src"

            let title = itemAnalyzer.getString(titleRule).trimmingCharacters(in: .whitespacesAndNewlines)
            var link = itemAnalyzer.getString(linkRule, isUrl: true).trimmingCharacters(in: .whitespacesAndNewlines)
            if link.isEmpty {
                link = itemAnalyzer.getString("//guid/text() || id@text")
            }

            guard !title.isEmpty, !link.isEmpty else { continue }

            let rawDesc = itemAnalyzer.getString(descRule)
            let cleanedDesc = BookContentService.cleanHtml(rawDesc)
            let pubDate = itemAnalyzer.getString(pubDateRule).trimmingCharacters(in: .whitespacesAndNewlines)
            let image = itemAnalyzer.getString(imgRule, isUrl: true).trimmingCharacters(in: .whitespacesAndNewlines)

            let article = RssArticle(
                origin: source.sourceUrl,
                sort: source.sourceName,
                title: title,
                order: Int64(index),
                link: link,
                pubDate: pubDate.isEmpty ? nil : pubDate,
                description: cleanedDesc.isEmpty ? nil : cleanedDesc,
                content: rawDesc.isEmpty ? nil : rawDesc,
                image: image.isEmpty ? nil : image,
                group: source.sourceGroup ?? "默认分组",
                read: false
            )
            articles.append(article)
        }

        if let message = engine.lastScriptError { throw SourceRuntimeError.script(stage: "rss", message: message) }
        return reverse ? Array(articles.reversed()) : articles
    }

    /// Native RSS displays an existing description first; otherwise evaluate ruleContent or
    /// load the linked document. Never convert network errors into a misleading empty page.
    public func fetchArticleContent(article: RssArticle, source: RssSource) async throws -> String {
        if let cached = article.content ?? article.description, !cached.isEmpty { return cached }
        let engine = JSEngine(bookSource: source.scriptSource, baseUrl: article.link)
        try engine.checkReady()
        let rendered = engine.renderTemplate(article.link, variables: ["page": 1])
        guard let parsed = NetworkClient.parseLegadoUrl(rendered,
            defaultHeader: JSEngine.resolvedSourceHeader(source.scriptSource, engine: engine), baseUrl: source.sourceUrl) else {
            throw WebDAVError.invalidURL
        }
        let fetched = try await NetworkClient.shared.request(parsed: parsed)
        try Task.checkCancellation()
        let response = try engine.checkedResponse(fetched, requestedURL: parsed.url)
        guard (200..<400).contains(response.statusCode) else { throw WebDAVError.serverError(response.statusCode, "文章加载失败") }
        guard let rule = source.ruleContent?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else { return response.bodyString }
        let analyzer = RuleAnalyzer(content: response.bodyString, baseUrl: response.url?.absoluteString ?? parsed.url.absoluteString, jsEngine: engine)
        let result = analyzer.getString(rule)
        if let message = engine.lastScriptError { throw SourceRuntimeError.script(stage: "ruleContent", message: message) }
        return result
    }
}

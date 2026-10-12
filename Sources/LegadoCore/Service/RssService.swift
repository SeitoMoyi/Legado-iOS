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

    /// Parses categories from `sortUrl` (format: `分类名::URL` separated by newlines, or a plain single URL)
    public func parseCategories(source: RssSource) -> [RssCategory] {
        guard let sortUrl = source.sortUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !sortUrl.isEmpty else {
            return [RssCategory(title: "默认", url: source.sourceUrl)]
        }

        var categories: [RssCategory] = []
        let lines = sortUrl.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.contains("::") {
                let parts = trimmed.components(separatedBy: "::")
                if parts.count >= 2 {
                    let title = parts[0].trimmingCharacters(in: .whitespaces)
                    let url = parts[1].trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty && !url.isEmpty {
                        categories.append(RssCategory(title: title, url: url))
                    }
                }
            } else if trimmed.starts(with: "http://") || trimmed.starts(with: "https://") || trimmed.starts(with: "/") {
                categories.append(RssCategory(title: "精选", url: trimmed))
            }
        }

        return categories.isEmpty ? [RssCategory(title: "全部", url: source.sourceUrl)] : categories
    }

    /// Fetches and parses articles for a given category URL
    public func fetchArticles(source: RssSource, categoryUrl: String, page: Int = 1) async throws -> [RssArticle] {
        var renderedUrl = categoryUrl
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "<page>", with: "\(page)")

        // If categoryUrl is relative, resolve with source.sourceUrl
        if let base = URL(string: source.sourceUrl), !renderedUrl.hasPrefix("http") {
            renderedUrl = URL(string: renderedUrl, relativeTo: base)?.absoluteString ?? renderedUrl
        }

        guard let parsed = NetworkClient.parseLegadoUrl(renderedUrl, defaultHeader: source.header) else {
            throw NSError(domain: "RssService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的订阅源地址"])
        }

        let response = try await NetworkClient.shared.request(parsed: parsed)
        let rawBody = response.bodyString
        guard !rawBody.isEmpty else { return [] }

        return try parseArticlesFromContent(rawBody, source: source, categoryUrl: renderedUrl)
    }

    /// Parses articles from raw XML/HTML/JSON content using ruleArticles, ruleTitle, etc.
    public func parseArticlesFromContent(_ content: String, source: RssSource, categoryUrl: String) throws -> [RssArticle] {
        let analyzer = RuleAnalyzer(content: content, baseUrl: categoryUrl)

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

        let rawItems = analyzer.getElements(resolvedArticleRule)
        var articles: [RssArticle] = []

        for (index, item) in rawItems.enumerated() {
            let itemAnalyzer = RuleAnalyzer(content: item, baseUrl: categoryUrl)

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

        return articles
    }

    /// Fetches full content of an article if ruleContent is set, otherwise returns cached description or HTML
    public func fetchArticleContent(article: RssArticle, source: RssSource) async throws -> String {
        if let rule = source.ruleContent?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty {
            guard let parsed = NetworkClient.parseLegadoUrl(article.link, defaultHeader: source.header) else {
                return article.content ?? article.description ?? ""
            }
            let response = try await NetworkClient.shared.request(parsed: parsed)
            let body = response.bodyString
            let analyzer = RuleAnalyzer(content: body, baseUrl: article.link)
            let extracted = analyzer.getString(rule)
            if !extracted.isEmpty {
                return extracted
            }
        }
        return article.content ?? article.description ?? ""
    }
}

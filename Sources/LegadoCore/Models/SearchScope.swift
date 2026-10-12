import Foundation

/// Which sources a search runs against.
///
/// The single `raw` string is deliberate: it is the exact format Android persists under the
/// `searchScope` preference, so a restored config keeps working —
///   ""          → every enabled source
///   "分组A,分组B" → those groups (comma joined, multi-select)
///   "源名::URL"   → one source
public struct SearchScope: Equatable, Codable {
    public var raw: String

    public init(raw: String = "") {
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let all = SearchScope()

    public var isAll: Bool { raw.isEmpty }
    public var isSource: Bool { raw.contains("::") }

    public var groups: [String] {
        guard !isAll, !isSource else { return [] }
        return raw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Splits on the *first* separator: a source name never contains "::" but a url may carry
    /// it in a path segment.
    public var sourceUrl: String? {
        guard isSource, let range = raw.range(of: "::") else { return nil }
        return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// Android also stores `searchGroup`, but only when exactly one group is selected.
    public var singleGroup: String {
        groups.count == 1 ? raw : ""
    }

    /// Resolves to the sources to search. Empty groups are dropped and the scope is rewritten
    /// to match, which is what Android does so a deleted group cannot pin future searches.
    public func resolve(in sources: [BookSource]) -> (scope: SearchScope, sources: [BookSource]) {
        let enabled = sources.filter { $0.enabled != false }
        if isAll { return (self, enabled) }

        if isSource, let url = sourceUrl {
            if let one = enabled.first(where: { $0.bookSourceUrl == url }) {
                return (self, [one])
            }
            return (.all, enabled)
        }

        let alive = groups.filter { group in
            enabled.contains { $0.groups.contains(group) }
        }
        guard !alive.isEmpty else { return (.all, enabled) }
        let list = enabled.filter { source in source.groups.contains(where: { alive.contains($0) }) }
        return (SearchScope(raw: alive.joined(separator: ",")), list)
    }

    /// Short label for the range button.
    public func summary(sourceName: String? = nil) -> String {
        if isAll { return "全部书源" }
        if let name = sourceName, !name.isEmpty { return name }
        if isSource { return "单个书源" }
        return groups.count == 1 ? "分组：\(groups[0])" : "\(groups.count) 个分组"
    }
}

/// Ordering and cross-source aggregation of search results.
///
/// Android merges hits by (name, author) into one row carrying an `origins` set, then sorts
/// into three buckets. Reproducing both matters: without merging, the same book appears once
/// per source and the user cannot see which copy is best supported.
public enum SearchMerger {

    /// Folds `incoming` into `existing`, union-ing `origins` and filling in empty metadata.
    public static func merge(_ existing: [SearchBook], _ incoming: [SearchBook]) -> [SearchBook] {
        var result = existing
        var indexByKey: [String: Int] = [:]
        for (position, book) in result.enumerated() {
            indexByKey[book.mergeKey] = position
        }

        for book in incoming {
            guard let position = indexByKey[book.mergeKey] else {
                indexByKey[book.mergeKey] = result.count
                result.append(book)
                continue
            }
            result[position] = combined(result[position], book)
        }
        return result
    }

    private static func combined(_ base: SearchBook, _ addition: SearchBook) -> SearchBook {
        var merged = base
        var origins = base.origins ?? [base.origin]
        let additions = addition.origins ?? [addition.origin]
        for origin in additions where !origins.contains(origin) {
            origins.append(origin)
        }
        merged.origins = origins
        if merged.coverUrl?.isEmpty != false { merged.coverUrl = addition.coverUrl }
        if merged.intro?.isEmpty != false { merged.intro = addition.intro }
        if merged.kind?.isEmpty != false { merged.kind = addition.kind }
        if merged.latestChapterTitle?.isEmpty != false { merged.latestChapterTitle = addition.latestChapterTitle }
        if merged.wordCount?.isEmpty != false { merged.wordCount = addition.wordCount }
        return merged
    }

    /// 精准 / 包含 / 其余, each of the first two ordered by how many sources carry the book.
    public static func rank(_ books: [SearchBook], key: String, precision: Bool) -> [SearchBook] {
        let needle = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return books }

        var exact: [SearchBook] = []
        var contains: [SearchBook] = []
        var other: [SearchBook] = []

        for book in books {
            if book.name == needle || book.author == needle {
                exact.append(book)
            } else if book.name.localizedCaseInsensitiveContains(needle)
                        || book.author.localizedCaseInsensitiveContains(needle) {
                contains.append(book)
            } else {
                other.append(book)
            }
        }

        var ranked = exact.sorted { $0.originCount > $1.originCount }
        ranked.append(contentsOf: contains.sorted { $0.originCount > $1.originCount })
        // 精准搜索 means "nothing that merely fuzzy-matched"; Android drops the bucket entirely.
        if !precision { ranked.append(contentsOf: other) }
        return ranked
    }
}

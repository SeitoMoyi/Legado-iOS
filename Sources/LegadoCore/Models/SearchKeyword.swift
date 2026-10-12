import Foundation

/// A search term the user has submitted. Field names are Android's `searchHistory.json`
/// keys (`data/entities/SearchKeyword.kt`).
public struct SearchKeyword: Codable, Identifiable, Equatable {
    public var word: String
    public var usage: Int
    public var lastUseTime: Int64

    public var id: String { word }

    public init(word: String, usage: Int = 1,
                lastUseTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.word = word
        self.usage = usage
        self.lastUseTime = lastUseTime
    }
}

/// Persistence + ordering for search history.
public enum SearchHistoryStore {
    public static let key = "legado_search_history_v1"

    public static func load(from defaults: UserDefaults = .standard) -> [SearchKeyword] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return TolerantJSON.decodeList(SearchKeyword.self, from: data, fallback: SearchKeyword(word: "")) ?? []
    }

    public static func save(_ items: [SearchKeyword], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }

    /// Android bumps `usage` and `lastUseTime` on a repeat instead of adding a row.
    public static func record(_ word: String, in items: [SearchKeyword]) -> [SearchKeyword] {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        var result = items
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let index = result.firstIndex(where: { $0.word == trimmed }) {
            result[index].usage += 1
            result[index].lastUseTime = now
        } else {
            result.append(SearchKeyword(word: trimmed, usage: 1, lastUseTime: now))
        }
        return result
    }

    /// Recency order, used while the search field is empty.
    public static func byTime(_ items: [SearchKeyword], limit: Int = 30) -> [SearchKeyword] {
        Array(items.sorted { $0.lastUseTime > $1.lastUseTime }.prefix(limit))
    }

    /// Contains-match ordered by how often it was used, while the user is typing.
    public static func matching(_ items: [SearchKeyword], _ needle: String) -> [SearchKeyword] {
        let key = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return byTime(items) }
        return items
            .filter { $0.word.localizedCaseInsensitiveContains(key) }
            .sorted { $0.usage > $1.usage }
    }
}

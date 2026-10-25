import Foundation

// MARK: - Book URL → Source Matcher (Plan 第一批 书架二级菜单 ③: 添加网址)
//
// Android `BookHelp` / `BookInfoViewModel` resolve a pasted chapter URL to a source in two
// steps, and the same order applies here:
// 1. `bookUrlPattern` — the source's own regex declaring which book URLs it owns.
// 2. host/prefix match — the URL starts with (or shares a host with) `bookSourceUrl`.
//
// When several sources match, the one with the longest `bookSourceUrl` prefix wins, which is
// the most specific site match.

public enum BookUrlMatcher {

    public struct MatchResult: Equatable {
        public let source: BookSource
        /// How the source was identified, for UI feedback.
        public let by: MatchReason

        public enum MatchReason: String {
            case urlPattern = "bookUrlPattern"
            case hostPrefix = "网址前缀"
        }
    }

    public static func match(url: String, sources: [BookSource]) -> MatchResult? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. bookUrlPattern regex (declared ownership beats incidental prefix overlap).
        var best: MatchResult? = nil
        for source in sources {
            guard let pattern = source.bookUrlPattern, !pattern.isEmpty,
                  let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = trimmed as NSString
            if regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) != nil {
                if best == nil || source.bookSourceUrl.count > best?.source.bookSourceUrl.count ?? 0 {
                    best = MatchResult(source: source, by: .urlPattern)
                }
            }
        }
        if let best = best { return best }

        // 2. Longest host/prefix match on bookSourceUrl.
        for source in sources {
            let base = source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty else { continue }
            let normalized = base.hasSuffix("/") ? String(base.dropLast()) : base
            if trimmed.hasPrefix(normalized) {
                if best == nil || normalized.count > best?.source.bookSourceUrl.count ?? 0 {
                    best = MatchResult(source: source, by: .hostPrefix)
                }
            }
        }
        if let best = best { return best }

        // 3. Same host, different scheme/path shape (e.g. source url is the site root
        // without scheme match).
        guard let urlHost = URL(string: trimmed)?.host else { return nil }
        for source in sources {
            guard let sourceHost = URL(string: source.bookSourceUrl)?.host else { continue }
            if !sourceHost.isEmpty && sourceHost == urlHost {
                if best == nil || sourceHost.count > best?.source.bookSourceUrl.count ?? 0 {
                    best = MatchResult(source: source, by: .hostPrefix)
                }
            }
        }
        return best
    }
}

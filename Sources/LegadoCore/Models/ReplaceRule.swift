import Foundation

/// A 替换净化 rule. Property names are the exact GSON keys Android writes into
/// `replaceRule.json` (`data/entities/ReplaceRule.kt`).
///
/// Two naming traps worth remembering when exchanging files with Android:
/// - the ordering key serialises as **`order`**, even though the SQLite column is
///   `sortOrder` — GSON uses the property name, so `sortOrder` would be silently ignored.
/// - `timeoutMillisecond <= 0` is normalised to 3000 at use time, not at decode time.
public struct ReplaceRule: Codable, Identifiable, Equatable {
    public var id: Int64
    public var name: String
    public var group: String?
    public var pattern: String
    public var replacement: String
    public var scope: String?
    public var scopeTitle: Bool
    public var scopeContent: Bool
    public var excludeScope: String?
    public var isEnabled: Bool
    public var isRegex: Bool
    public var timeoutMillisecond: Int64
    public var order: Int

    public init(
        id: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        name: String = "",
        group: String? = nil,
        pattern: String = "",
        replacement: String = "",
        scope: String? = nil,
        scopeTitle: Bool = false,
        scopeContent: Bool = true,
        excludeScope: String? = nil,
        isEnabled: Bool = true,
        isRegex: Bool = true,
        timeoutMillisecond: Int64 = 3000,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.pattern = pattern
        self.replacement = replacement
        self.scope = scope
        self.scopeTitle = scopeTitle
        self.scopeContent = scopeContent
        self.excludeScope = excludeScope
        self.isEnabled = isEnabled
        self.isRegex = isRegex
        self.timeoutMillisecond = timeoutMillisecond
        self.order = order
    }

    public static let defaultTimeoutMilliseconds: Int64 = 3000

    public var effectiveTimeout: Int64 {
        timeoutMillisecond > 0 ? timeoutMillisecond : Self.defaultTimeoutMilliseconds
    }

    /// Android `ReplaceRule.isValid()`: non-empty pattern that compiles and does not end in
    /// an unescaped `|`.
    public var isValid: Bool {
        guard !pattern.isEmpty, !pattern.hasSuffix("|") else { return false }
        if !isRegex { return true }
        return (try? NSRegularExpression(pattern: pattern)) != nil
    }
}

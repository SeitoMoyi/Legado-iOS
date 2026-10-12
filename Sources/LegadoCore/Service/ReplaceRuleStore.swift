import Foundation

/// Persistence for the user's 替换净化 rule library. The stored array uses Android's
/// `replaceRule.json` key names, so a WebDAV archive can be restored on either platform.
public enum ReplaceRuleStore {
    public static let key = "legado_replace_rules_v1"

    public static func load(from defaults: UserDefaults = .standard) -> [ReplaceRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return TolerantJSON.decodeList(ReplaceRule.self, from: data, fallback: ReplaceRule()) ?? []
    }

    public static func save(_ rules: [ReplaceRule], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }

    /// Imports an Android `replaceRule.json` payload, appending to what is already stored
    /// and replacing rules that share an id.
    public static func importJSON(_ text: String, into existing: [ReplaceRule]) -> [ReplaceRule] {
        guard let data = text.data(using: .utf8),
              let imported = TolerantJSON.decodeList(ReplaceRule.self, from: data, fallback: ReplaceRule())
        else { return existing }

        var result = existing
        for rule in imported {
            if let index = result.firstIndex(where: { $0.id == rule.id }) {
                result[index] = rule
            } else {
                result.append(rule)
            }
        }
        return result.sorted { $0.order < $1.order }
    }

    public static func exportJSON(_ rules: [ReplaceRule]) -> String? {
        guard let data = try? JSONEncoder().encode(rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

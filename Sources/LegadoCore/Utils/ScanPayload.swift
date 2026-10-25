import Foundation

// MARK: - Scanned Payload Detector (Plan 第一批 Part 3: 二维码全链路)
//
// A scanned string can be a book-source / replace-rule / RSS-source / dict-rule JSON, a
// WebDAV credential card, an import direct link or plain text. Detection is key-shape based
// (the same field names Android GSON writes), kept here so `ScanPayloadTests` can lock the
// table down and the scanner sheet only renders results.

public enum ScanPayload: Equatable {

    case bookSources(json: String)
    case replaceRules(json: String)
    case rssSources(json: String)
    case dictRules(json: String)
    case webdavConfig(json: String)
    case importURL(String)
    case text(String)

    /// Classifies a raw scanned/decoded string. JSON payloads are returned with the original
    /// string so the app layer can feed the exact bytes to the matching importer.
    public static func detect(_ raw: String) -> ScanPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text(raw) }

        if let value = parseJSON(trimmed) {
            let array: [[String: Any]]
            if let items = value as? [[String: Any]] {
                array = items
            } else if let single = value as? [String: Any] {
                array = [single]
            } else {
                array = []
            }
            if let kind = payloadKind(of: array) {
                switch kind {
                case .bookSources: return .bookSources(json: trimmed)
                case .replaceRules: return .replaceRules(json: trimmed)
                case .rssSources: return .rssSources(json: trimmed)
                case .dictRules: return .dictRules(json: trimmed)
                case .webdav: return .webdavConfig(json: trimmed)
                }
            }
            return .text(raw)
        }

        // legado:// / yuedu:// deep links and plain http(s) links are both import intents.
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            || trimmed.lowercased().hasPrefix("legado://") || trimmed.lowercased().hasPrefix("yuedu://") {
            return .importURL(trimmed)
        }

        return .text(raw)
    }

    /// Non-dictionary JSON values (numbers, plain strings) are not payload candidates.
    private static func parseJSON(_ text: String) -> Any? {
        guard text.hasPrefix("[") || text.hasPrefix("{") else { return nil }
        guard let data = text.data(using: .utf8) ?? text.data(using: .isoLatin1) else { return nil }
        let options: JSONSerialization.ReadingOptions = [.fragmentsAllowed, .mutableContainers]
        guard let value = try? JSONSerialization.jsonObject(with: data, options: options) else { return nil }
        // A fragment (bare number/string) is not an import payload.
        if !JSONSerialization.isValidJSONObject(value), !(value is [[String: Any]] || value is [String: Any]) {
            return nil
        }
        return value
    }

    private enum PayloadKind {
        case bookSources, replaceRules, rssSources, dictRules, webdav
    }

    /// Majority vote across the array so one odd member does not flip the kind.
    private static func payloadKind(of items: [[String: Any]]) -> PayloadKind? {
        guard !items.isEmpty else { return nil }
        var scores: [PayloadKind: Int] = [:]
        func bump(_ kind: PayloadKind, by amount: Int) {
            scores[kind, default: 0] += amount
        }
        for item in items {
            if item["bookSourceUrl"] != nil { bump(.bookSources, by: 2) }
            if item["bookSourceName"] != nil { bump(.bookSources, by: 1) }
            if item["replaceRegex"] != nil || (item["pattern"] != nil && item["replacement"] != nil) {
                bump(.replaceRules, by: 2)
            }
            if item["sourceUrl"] != nil && (item["sortUrl"] != nil || item["ruleArticles"] != nil) {
                bump(.rssSources, by: 3)
            }
            if item["urlRule"] != nil { bump(.dictRules, by: 3) }
            if item["url"] != nil && item["username"] != nil && item["password"] != nil {
                bump(.webdav, by: 3)
            }
        }
        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= 2 else { return nil }
        return best.key
    }

    /// Human-readable kind label for the result sheet.
    public var kindLabel: String {
        switch self {
        case .bookSources: return "书源"
        case .replaceRules: return "替换净化规则"
        case .rssSources: return "订阅源"
        case .dictRules: return "字典规则"
        case .webdavConfig: return "WebDAV 配置"
        case .importURL: return "导入链接"
        case .text: return "文本"
        }
    }
}

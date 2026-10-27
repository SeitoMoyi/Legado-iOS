import Foundation

public struct AppLogEntry: Identifiable, Equatable {
    public let id: UUID
    public let time: Date
    public let category: String
    public let message: String
}

/// Session logs mirror Android AppLog's bounded in-memory history. Credentials are not
/// intentionally collected, and common secret fields are redacted before insertion.
public final class AppLogStore {
    public static let shared = AppLogStore()
    public static let didChange = Notification.Name("LegadoAppLogsChanged")
    private let lock = NSLock()
    private var entries: [AppLogEntry] = []
    public init() {}
    public func snapshot() -> [AppLogEntry] { lock.lock(); defer { lock.unlock() }; return entries }
    public func record(_ category: String, _ message: String) {
        let entry = AppLogEntry(id: UUID(), time: Date(), category: category, message: Self.redact(String(message.prefix(4096))))
        lock.lock(); entries.insert(entry, at: 0); if entries.count > 100 { entries.removeLast(entries.count - 100) }; lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
    public func clear() { lock.lock(); entries.removeAll(); lock.unlock(); NotificationCenter.default.post(name: Self.didChange, object: self) }
    public static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#,
            #"(?im)((?:Authorization|Cookie|Set-Cookie)\s*[:=]\s*)[^\r\n]+"#,
            #"(?i)([?&](?:password|token|access_token|authorization|api_key|key|cookie)=)[^&\s]+"#,
            #"(?i)(\"(?:password|token|access_token|cookie|authorization)\"\s*:\s*\")[^\"]*"#
        ]
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: index == 0 ? "$1[redacted]@" : "$1[redacted]")
            }
        }
        return result
    }
}

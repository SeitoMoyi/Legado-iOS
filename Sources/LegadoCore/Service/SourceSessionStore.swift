import Foundation

/// Android keeps login headers outside the source JSON. This cache also covers headers
/// refreshed by loginCheckJs while a request is being parsed.
public enum SourceSessionStore {
    private static let lock = NSLock()
    private static let prefix = "legado_source_login_header_"
    public static func header(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return UserDefaults.standard.string(forKey: prefix + key)
    }
    public static func save(header: String?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.set(header, forKey: prefix + key)
    }
}

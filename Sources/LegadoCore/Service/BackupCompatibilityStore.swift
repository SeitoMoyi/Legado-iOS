import Foundation

/// Opaque Android members are retained as bytes, never interpreted as iOS settings.
public enum BackupCompatibilityStore {
    public static let key = "legado_backup_members_v1"
    public static let maximumMemberSize = 64 * 1024 * 1024
    public static let maximumTotalSize = 256 * 1024 * 1024

    public static func validate(path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw WebDAVError.decodingFailed("备份包含无效路径")
        }
    }

    public static func validate(_ members: [String: Data]) throws {
        var total = 0
        for (path, data) in members {
            try validate(path: path)
            guard data.count <= maximumMemberSize, total <= maximumTotalSize - data.count else {
                throw WebDAVError.decodingFailed("备份数据超过大小限制")
            }
            total += data.count
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> [String: Data] {
        guard let data = defaults.data(forKey: key),
              let members = try? JSONDecoder().decode([String: Data].self, from: data) else { return [:] }
        return members
    }

    public static func save(_ members: [String: Data], to defaults: UserDefaults = .standard) throws {
        try validate(members)
        defaults.set(try JSONEncoder().encode(members), forKey: key)
    }
}

/// iOS-only reader state travels alongside the native Android style array.
public struct ReaderBackupSettings: Codable, Equatable {
    public var selectedStyle: Int
    public var prefs: ReaderPrefs
    public init(selectedStyle: Int = 0, prefs: ReaderPrefs = ReaderPrefs()) {
        self.selectedStyle = selectedStyle
        self.prefs = prefs
    }
}

import Foundation

/// Reads and writes reader appearance/behaviour from `UserDefaults`.
///
/// Lives in the core layer (alongside `WebDAVService`, which also owns its own
/// `UserDefaults` slice) so the storage contract is unit-testable without SwiftUI.
/// The stored payload for the style uses Android `readConfig.json` / `shareReadConfig.json`
/// key names, which keeps a future WebDAV backup interchangeable with Android.
public enum ReaderStore {
    public static let styleKey = "legado_read_config_v1"
    public static let prefsKey = "legado_reader_prefs_v1"
    /// Written by older builds, which only persisted the page mode.
    public static let legacyPageModeKey = "reader_page_mode"

    /// Decodes `data` on top of `fallback`, so a payload that omits keys still decodes.
    /// Kept as an alias of `TolerantJSON.decode` for reader-side call sites.
    public static func tolerantDecode<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> T? {
        TolerantJSON.decode(type, from: data, fallback: fallback)
    }

    public static func loadStyle(from defaults: UserDefaults = .standard) -> ReadStyleConfig? {
        guard let data = defaults.data(forKey: styleKey) else { return nil }
        return tolerantDecode(ReadStyleConfig.self, from: data, fallback: ReadStyleConfig())
    }

    public static func save(_ style: ReadStyleConfig, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        defaults.set(data, forKey: styleKey)
    }

    public static func save(_ prefs: ReaderPrefs, to defaults: UserDefaults = .standard) {
        var normalized = prefs
        normalized.normalizeClickActions()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: prefsKey)
    }

    public static func loadPrefs(from defaults: UserDefaults = .standard) -> ReaderPrefs {
        var prefs = ReaderPrefs()
        if let data = defaults.data(forKey: prefsKey),
           let decoded = tolerantDecode(ReaderPrefs.self, from: data, fallback: ReaderPrefs()) {
            prefs = decoded
        }
        prefs.normalizeClickActions()
        return prefs
    }

    public static func legacyPageMode(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: legacyPageModeKey)
    }

    public static func clearLegacyPageMode(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyPageModeKey)
    }
}

import Foundation

/// What a home-screen quick action (`UIApplicationShortcutItem`) asks the app to do.
///
/// The resolution lives in `LegadoCore` so it is testable without a UIKit host: the
/// `Info.plist` declares the shortcut identifiers and the reader/shelf wiring consumes the
/// intent, but the mapping itself is pure data. Keep this in sync with
/// `Sources/LegadoApp/Info.plist` → `UIApplicationShortcutItems` → `UIApplicationShortcutItemType`.
public enum LaunchIntent: String, Equatable, CaseIterable {
    /// `io.legado.action.search` — jump to the 分类 tab (the app's book search surface).
    case search
    /// `io.legado.action.lastRead` — reopen the most recently read book.
    case continueReading

    /// Shortcut type identifiers, exactly as declared in `Info.plist`.
    public static let searchShortcutType = "io.legado.action.search"
    public static let lastReadShortcutType = "io.legado.action.lastRead"

    /// Maps a `UIApplicationShortcutItem.type` to an intent, or `nil` when the identifier is
    /// unknown (a shortcut added by a newer build, or a stale one from an older install).
    public static func fromShortcutType(_ type: String?) -> LaunchIntent? {
        guard let type else { return nil }
        switch type {
        case searchShortcutType: return .search
        case lastReadShortcutType: return .continueReading
        default: return nil
        }
    }

    /// The book 「继续阅读」 should open: the one with the newest reading timestamp.
    ///
    /// Only books with a non-zero `durChapterTime` count as "read" — `lastCheckTime` is bumped by
    /// TOC refreshes and by pinning, so it would surface books the user never opened. Ties keep the
    /// first match, i.e. the caller's shelf order, so the result is deterministic.
    public static func lastReadBook(in books: [Book]) -> Book? {
        var best: Book?
        for book in books where book.durChapterTime > 0 {
            if best == nil || book.durChapterTime > best!.durChapterTime {
                best = book
            }
        }
        return best
    }
}

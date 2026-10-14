import Foundation
import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Bridges home-screen quick actions to the views that can act on them.
///
/// A shortcut can arrive before any view exists (cold launch) or while the app is already
/// running, and the work is spread across two places: `MainTabView` owns the tab selection and
/// `BookshelfView` owns the reader presentation. Rather than have the `AppDelegate` reach into
/// either, it parks the request here and the owning view consumes it on appear / on change.
public final class LaunchRouter: ObservableObject {
    public static let shared = LaunchRouter()

    /// Set when a shortcut arrives; `MainTabView` consumes and clears it.
    @Published public var pendingIntent: LaunchIntent?
    /// Set when 「继续阅读」 resolved to a concrete book; `BookshelfView` consumes and clears it.
    @Published public var pendingBook: Book?

    public init() {}

    /// Entry point from `LegadoAppDelegate.application(_:performActionFor:completionHandler:)`.
    ///
    /// Only the intent is parked here — resolving 「继续阅读」 to a book happens when
    /// `MainTabView` consumes it, so a cold launch is not racing `BookStore`'s load.
    public func handle(shortcutType: String?) {
        guard let intent = LaunchIntent.fromShortcutType(shortcutType) else { return }
        pendingIntent = intent
    }
}

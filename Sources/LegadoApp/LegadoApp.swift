import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif
#if os(iOS)
import UIKit
#endif

/// UIKit delegates, needed only for home-screen quick actions: SwiftUI has no equivalent hook, so
/// the `UIApplicationShortcutItems` declared in `Info.plist` would otherwise be inert (tapping one
/// just opened the app).
///
/// Per Apple's `UIApplicationDelegateAdaptor` documentation, app shortcuts are a **scene**-based
/// event: on a scene-enabled app the callback arrives at
/// `UIWindowSceneDelegate.windowScene(_:performActionFor:completionHandler:)`, not at the
/// application delegate. The scene delegate therefore does the work, and the app delegate's only
/// job is to hand SwiftUI a `UISceneConfiguration` naming that delegate class.
#if os(iOS)
public final class LegadoAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = LegadoSceneDelegate.self
        }
        return configuration
    }
}

/// Receives the shortcut and parks it in `LaunchRouter`; the tab view and shelf consume it.
public final class LegadoSceneDelegate: NSObject, UIWindowSceneDelegate {
    public func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        LaunchRouter.shared.handle(shortcutType: shortcutItem.type)
        completionHandler(true)
    }
}
#endif

@main
public struct LegadoApp: App {
    @StateObject private var bookStore = BookStore.shared
    @AppStorage("legado_app_theme") private var appTheme: String = "system"
    #if os(iOS)
    @UIApplicationDelegateAdaptor(LegadoAppDelegate.self) private var appDelegate
    #endif

    private var selectedColorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(bookStore)
                .preferredColorScheme(selectedColorScheme)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "legado" || scheme == "yuedu" || scheme == "http" || scheme == "https" else { return }

        // Parse query or host for source/book import
        // e.g. legado://import/source?src=https://... or legado://bookSource/importOnline?src=...
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let src = components.queryItems?.first(where: { $0.name == "src" || $0.name == "url" })?.value,
               let targetUrl = URL(string: src) {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: targetUrl),
                       let jsonStr = String(data: data, encoding: .utf8) {
                        _ = try? bookStore.importSources(json: jsonStr)
                    }
                }
            }
        }
    }
}

public struct MainTabView: View {
    /// Tab indices, matching the `TabView` order below.
    private enum Tab: Int {
        case shelf = 0
        case explore = 1
        case rss = 2
        case settings = 3
    }

    @State private var selectedTab: Tab = .shelf
    @ObservedObject private var launchRouter = LaunchRouter.shared

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            BookshelfView()
                .tabItem {
                    Label("书架", systemImage: "books.vertical.fill")
                }
                .tag(Tab.shelf)

            CategoryExploreView()
                .tabItem {
                    Label("分类", systemImage: "square.grid.2x2.fill")
                }
                .tag(Tab.explore)

            RssSourceListView()
                .tabItem {
                    Label("订阅", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(Tab.rss)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .onAppear { consumePendingIntent() }
        .onChange(of: launchRouter.pendingIntent) { _ in consumePendingIntent() }
    }

    /// A shortcut's only job at this level is picking the tab; 「继续阅读」 also resolves the book
    /// and leaves it in `pendingBook` for `BookshelfView` to open. Consumed once, then cleared.
    private func consumePendingIntent() {
        guard let intent = launchRouter.pendingIntent else { return }
        launchRouter.pendingIntent = nil
        switch intent {
        case .search:
            selectedTab = .explore
        case .continueReading:
            selectedTab = .shelf
            // Resolved here, not in the delegate: at cold launch the delegate runs before the
            // store has finished loading, so the shelf would look empty.
            launchRouter.pendingBook = LaunchIntent.lastReadBook(in: BookStore.shared.bookshelf)
        }
    }
}

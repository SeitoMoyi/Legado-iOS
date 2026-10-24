#if canImport(UIKit)
import UIKit

/// Explicit, UIKit-level TabBar visibility for pushed pages whose bottom action bar must own
/// the screen bottom (详情页).
///
/// Why not `.toolbar(.hidden, for: .tabBar)`: SwiftUI's preference-based restore is bound to
/// the END of the pop transition — the bar only fades back ~0.35–0.5s after the user taps
/// back, which reads as "返回书架等半秒才出现 tabbar". With this helper the popped-TO page's
/// `onAppear` (fires at pop START) calls `setHidden(false)`, so the bar slides back in with
/// the transition, matching native UX.
///
/// Note: hiding the UITabBar view leaves its safe-area slot reserved by the hosting
/// hierarchy, which is why the detail page additionally pins its content with
/// `ignoresSafeArea(.container, edges: .bottom)`.
enum TabBarVisibility {

    static func setHidden(_ hidden: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .compactMap { keyWindow -> UIView? in keyWindow.rootViewController?.view }
                .forEach { root in
                    findTabBar(in: root)?.isHidden = hidden
                }
        }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }
}

#endif

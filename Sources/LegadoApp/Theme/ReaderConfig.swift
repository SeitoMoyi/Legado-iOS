import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

public enum ReaderTheme: String, CaseIterable, Identifiable {
    case white = "默认白"
    case parchment = "复古羊皮纸"
    case eyeCare = "护眼绿"
    case dark = "夜间暗黑"
    case eink = "水墨屏"
    case custom = "自定义"

    public var id: String { rawValue }

    public var backgroundHex: String {
        switch self {
        case .white: return "#FAFAFA"
        case .parchment: return "#F2E6D1"
        case .eyeCare: return "#E0F0E0"
        case .dark: return "#1F1F1F"
        case .eink: return "#FFFFFF"
        case .custom: return "#F5EAD8"
        }
    }

    public var textHex: String {
        switch self {
        case .white: return "#262626"
        case .parchment: return "#382E26"
        case .eyeCare: return "#264026"
        case .dark: return "#CCCCCC"
        case .eink: return "#000000"
        case .custom: return "#332211"
        }
    }
    public var backgroundColor: Color { Color(hex: backgroundHex) }
    public var textColor: Color { Color(hex: textHex) }

    static func matching(backgroundHex: String) -> ReaderTheme? {
        let target = backgroundHex.uppercased()
        return allCases.first { $0 != .custom && $0.backgroundHex.uppercased() == target }
    }

    static let defaultTheme: ReaderTheme = .parchment
}

extension Color {
    init(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        var value: UInt64 = 0
        guard raw.count == 6, Scanner(string: raw).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

/// Live reader appearance + behaviour state.
///
/// The stored `@Published` values are the runtime source of truth (SwiftUI binds to them
/// directly). Every mutation snapshots them into a `ReadStyleConfig` / `ReaderPrefs` pair
/// and writes both to `UserDefaults`, which is what fixes the previous bug where
/// `fontSize`, `lineSpacing` and `theme` reset on every cold launch.
public final class ReaderConfig: ObservableObject {
    public static let shared = ReaderConfig()

    private let defaults = UserDefaults.standard

    // MARK: Typography

    @Published public var fontSize: CGFloat = 18 { didSet { persistStyle() } }
    @Published public var lineSpacing: CGFloat = 8 { didSet { persistStyle() } }
    @Published public var letterSpacing: CGFloat = 0 { didSet { persistStyle() } }
    @Published public var paragraphSpacing: CGFloat = 4 { didSet { persistStyle() } }
    /// First-line indent prefix. "" disables indentation.
    @Published public var paragraphIndent: String = "　　" { didSet { persistStyle() } }
    @Published public var textFont: String = "" { didSet { persistStyle() } }
    /// 0 正常 / 1 粗体 / 2 细体 (Android `textBold`)
    @Published public var textBold: Int = 0 { didSet { persistStyle() } }

    // MARK: Page layout

    /// Raw values follow Android `PageAnim`; `.scroll` selects the continuous-scroll canvas,
    /// the other four are paged rendering with different transitions.
    @Published public var pageAnim: PageAnim = .scroll { didSet { persistStyle() } }

    /// Compatibility view for call sites that only care about scroll vs paged.
    public var pageMode: PageMode {
        get { pageAnim == .scroll ? .scroll : .pageByPage }
        set { pageAnim = (newValue == .scroll) ? .scroll : .cover }
    }

    /// First-line indent choices, matching Android's 无/一/二/三/四字符缩进.
    public static let indentChoices: [(value: String, label: String)] = [
        ("", "无缩进"),
        ("\u{3000}", "一字符"),
        ("\u{3000}\u{3000}", "二字符"),
        ("\u{3000}\u{3000}\u{3000}", "三字符"),
        ("\u{3000}\u{3000}\u{3000}\u{3000}", "四字符")
    ]

    public func setPageAnim(_ anim: PageAnim) {
        pageAnim = anim
    }

    /// 0 means "system default"; iOS has no scaled touch slop to read, so 30 pt is used.
    public var pageTouchSlop: CGFloat {
        prefs.pageTouchSlop == 0 ? 30 : CGFloat(prefs.pageTouchSlop)
    }

    /// Horizontal travel that commits a page turn.
    public var pageTurnThreshold: CGFloat {
        max(pageTouchSlop * 1.5, 40)
    }

    // MARK: Tap zones

    /// The nine configured actions, row-major. Always length 9.
    public var clickActionList: [ClickActionCode] {
        ReaderPrefs.defaultClickActions.enumerated().map { index, fallback in
            ClickActionCode.from(prefs.clickActions.count == 9 ? prefs.clickActions[index] : fallback)
        }
    }

    public func setClickAction(_ zone: Int, to action: ClickActionCode) {
        guard zone >= 0 && zone < 9 else { return }
        var updated = prefs
        updated.clickActions = clickActionList.map { $0.rawValue }
        updated.clickActions[zone] = action.rawValue
        updated.normalizeClickActions()
        prefs = updated
    }

    public func resetClickActions() {
        var updated = prefs
        updated.clickActions = ReaderPrefs.defaultClickActions
        prefs = updated
    }

    /// Landscape and portrait margins move together, as they do in the paged renderer where
    /// a single pair drives layout.
    public func syncTrailingPadding() { paddingTrailing = paddingLeading }
    public func syncBottomPadding() { paddingBottom = paddingTop }

    @Published public var paddingTop: CGFloat = 24 { didSet { persistStyle() } }
    @Published public var paddingBottom: CGFloat = 24 { didSet { persistStyle() } }
    @Published public var paddingLeading: CGFloat = 20 { didSet { persistStyle() } }
    @Published public var paddingTrailing: CGFloat = 20 { didSet { persistStyle() } }

    /// Title placement, mirrors Android `titleMode`: 0 靠左 / 1 居中 / 2 隐藏.
    @Published public var titleMode: Int = 0 { didSet { persistStyle() } }

    // MARK: Colors

    @Published public var theme: ReaderTheme = .defaultTheme { didSet { persistStyle() } }
    @Published public var customBgHex: String = "#F5EAD8" { didSet { persistStyle() } }
    @Published public var customTextHex: String = "#332211" { didSet { persistStyle() } }
    // MARK: Behaviour

    @Published public var prefs: ReaderPrefs = ReaderPrefs() { didSet { persistPrefs() } }

    private var isRestoring = true
    private var pendingSave: DispatchWorkItem?
    private var baseStyle = ReadStyleConfig()

    public init() {
        restore()
        isRestoring = false
    }

    // MARK: Derived values used by the renderer

    public var effectiveTextColor: Color {
        theme == .custom ? Color(hex: customTextHex) : theme.textColor
    }
    public var effectiveBackgroundColor: Color {
        theme == .custom ? Color(hex: customBgHex) : theme.backgroundColor
    }

    /// The Android-shaped style snapshot, handed to `ContentProcessor` per chapter.
    public var styleConfig: ReadStyleConfig { makeStyleConfig() }

    /// Binding into a `ReaderPrefs` field. `ReaderPrefs` is a value type, so every write has
    /// to replace the whole struct for `@Published` to fire — doing it once here keeps the
    /// panel code readable.
    public func pref<Value>(_ keyPath: WritableKeyPath<ReaderPrefs, Value>) -> Binding<Value> {
        Binding(
            get: { self.prefs[keyPath: keyPath] },
            set: { var updated = self.prefs; updated[keyPath: keyPath] = $0; self.prefs = updated }
        )
    }

    /// Binding into the active style, writing back into every stored property at once.
    public func styleField<Value>(_ keyPath: WritableKeyPath<ReadStyleConfig, Value>) -> Binding<Value> {
        Binding(
            get: { self.styleConfig[keyPath: keyPath] },
            set: { newValue in
                var style = self.styleConfig
                style[keyPath: keyPath] = newValue
                self.apply(style: style)
                self.persistStyle()
            }
        )
    }

    /// Content width inside a container of the given size.
    public func contentSize(for container: CGSize) -> CGSize {
        CGSize(
            width: max(40, container.width - paddingLeading - paddingTrailing),
            height: max(40, container.height - paddingTop - paddingBottom)
        )
    }

    // MARK: Persistence

    /// Slider drags fire dozens of mutations per second; coalesce the disk writes.
    private func persistStyle() {
        guard !isRestoring else { return }
        scheduleSave { ReaderStore.save(self.makeStyleConfig(), to: self.defaults) }
    }

    private func persistPrefs() {
        guard !isRestoring else { return }
        scheduleSave { ReaderStore.save(self.prefs, to: self.defaults) }
    }

    private func scheduleSave(_ action: @escaping () -> Void) {
        pendingSave?.cancel()
        let work = DispatchWorkItem(block: action)
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Starts from the loaded style so Android-compatible fields that have no iOS control
    /// yet (`tipHeaderLeft`, `headerMode`, `bgAlpha`, …) survive a round trip.
    private func makeStyleConfig() -> ReadStyleConfig {
        var style = baseStyle
        style.name = theme.rawValue
        style.bgStr = theme == .custom ? customBgHex : theme.backgroundHex
        style.textColor = theme == .custom ? customTextHex : theme.textHex
        style.darkStatusIcon = theme != .dark
        style.textFont = textFont
        style.textBold = textBold
        style.textSize = Double(fontSize)
        style.letterSpacing = Double(letterSpacing)
        style.lineSpacingExtra = Double(lineSpacing)
        style.paragraphSpacing = Double(paragraphSpacing)
        style.paragraphIndent = paragraphIndent
        style.titleMode = titleMode
        style.paddingTop = Double(paddingTop)
        style.paddingRight = Double(paddingTrailing)
        style.paddingBottom = Double(paddingBottom)
        style.paddingLeft = Double(paddingLeading)
        return style
    }

    private func restore() {
        prefs = ReaderStore.loadPrefs(from: defaults)

        guard let saved = ReaderStore.loadStyle(from: defaults) else {
            applyLegacyPageMode()
            return
        }
        apply(style: saved)
    }

    private func apply(style saved: ReadStyleConfig) {
        baseStyle = saved
        fontSize = CGFloat(saved.textSize)
        lineSpacing = CGFloat(saved.lineSpacingExtra)
        letterSpacing = CGFloat(saved.letterSpacing)
        paragraphSpacing = CGFloat(saved.paragraphSpacing)
        paragraphIndent = saved.paragraphIndent
        textFont = saved.textFont
        textBold = saved.textBold
        titleMode = saved.titleMode
        paddingTop = CGFloat(saved.paddingTop)
        paddingBottom = CGFloat(saved.paddingBottom)
        paddingLeading = CGFloat(saved.paddingLeft)
        paddingTrailing = CGFloat(saved.paddingRight)
        if let matched = ReaderTheme.matching(backgroundHex: saved.bgStr) {
            theme = matched
        } else {
            theme = .custom
            customBgHex = saved.bgStr
            customTextHex = saved.textColor
        }
    }

    /// Before the style model existed only `reader_page_mode` was written. Honour it once
    /// so an upgrade does not silently flip the user back to scroll.
    private func applyLegacyPageMode() {
        if let raw = ReaderStore.legacyPageMode(in: defaults),
           let mode = PageMode(rawValue: raw) {
            pageAnim = (mode == .scroll) ? .scroll : .cover
        }
        ReaderStore.clearLegacyPageMode(from: defaults)
    }
}

public enum PageMode: String, CaseIterable, Identifiable {
    case scroll = "连续滚动"
    case pageByPage = "左右翻页"

    public var id: String { rawValue }
}

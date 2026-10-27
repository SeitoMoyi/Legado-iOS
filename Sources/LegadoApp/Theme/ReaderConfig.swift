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

    static func matching(backgroundHex: String, textHex: String) -> ReaderTheme? {
        guard let background = ReaderHexColor(hex: backgroundHex),
              let text = ReaderHexColor(hex: textHex) else { return nil }
        return allCases.first {
            $0 != .custom && ReaderHexColor(hex: $0.backgroundHex) == background
                && ReaderHexColor(hex: $0.textHex) == text
        }
    }

    static let defaultTheme: ReaderTheme = .parchment
}

/// Shared parser for the editor and restored Android colors (#RRGGBB / #AARRGGBB).
/// Short RGB is accepted too; partial hex input must never become a partially scanned color.
struct ReaderHexColor: Equatable {
    let argb: UInt32

    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        guard [6, 8].contains(raw.count),
              raw.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }),
              let value = UInt32(raw, radix: 16) else { return nil }
        argb = raw.count == 6 ? 0xFF000000 | value : value
    }

    private init(argb: UInt32) { self.argb = argb }

    var color: Color {
        Color(red: Double((argb >> 16) & 0xFF) / 255,
              green: Double((argb >> 8) & 0xFF) / 255,
              blue: Double(argb & 0xFF) / 255,
              opacity: Double(argb >> 24) / 255)
    }

    func composited(over background: ReaderHexColor) -> ReaderHexColor {
        let alpha = Double(argb >> 24) / 255
        var rgb: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let front = Double((argb >> shift) & 0xFF)
            let back = Double((background.argb >> shift) & 0xFF)
            rgb |= UInt32((front * alpha + back * (1 - alpha)).rounded()) << shift
        }
        return ReaderHexColor(argb: 0xFF000000 | rgb)
    }

    var isDark: Bool {
        let brightness = Double((argb >> 16) & 0xFF) * 0.299
            + Double((argb >> 8) & 0xFF) * 0.587 + Double(argb & 0xFF) * 0.114
        return brightness < 128
    }

    static let black = ReaderHexColor(argb: 0xFF000000)
    static let white = ReaderHexColor(argb: 0xFFFFFFFF)
}

/// An invalid editor value used to make both colors gray. Keep the saved input editable,
/// but draw a valid palette and recover text that would be invisible against its background.
struct ReaderPalette {
    let background: ReaderHexColor
    let text: ReaderHexColor

    init(backgroundHex: String, textHex: String) {
        let background = (ReaderHexColor(hex: backgroundHex)
            ?? ReaderHexColor(hex: ReaderTheme.custom.backgroundHex)!).composited(over: .white)
        let candidate = ReaderHexColor(hex: textHex)
            ?? ReaderHexColor(hex: ReaderTheme.custom.textHex)!
        self.background = background
        text = candidate.composited(over: background) == background
            ? (background.isDark ? .white : .black) : candidate
    }
}

extension Color {
    init(hex: String) {
        self = ReaderHexColor(hex: hex)?.color ?? .gray
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

    private let defaults: UserDefaults

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
    private var restoreObserver: NSObjectProtocol?
    private var baseStyle = ReadStyleConfig()
    private var initialStyle: ReadStyleConfig?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        initialStyle = makeStyleConfig()
        restore()
        isRestoring = false
        restoreObserver = NotificationCenter.default.addObserver(forName: ReaderStore.didRestore, object: defaults, queue: .main) { [weak self] _ in
            self?.reloadFromStore()
        }
    }

    deinit {
        if let observer = restoreObserver { NotificationCenter.default.removeObserver(observer) }
        pendingSave?.cancel()
    }

    public func reloadFromStore() {
        pendingSave?.cancel()
        pendingSave = nil
        isRestoring = true
        restore()
        isRestoring = false
    }

    public func selectStoredStyle(_ index: Int) {
        let styles = ReaderStore.loadStyles(from: defaults)
        guard styles.indices.contains(index) else { return }
        pendingSave?.cancel()
        ReaderStore.save(makeStyleConfig(), to: defaults)
        ReaderStore.saveStyles(ReaderStore.loadStyles(from: defaults), selectedIndex: index, to: defaults)
        reloadFromStore()
    }

    // MARK: Derived values used by the renderer

    var palette: ReaderPalette {
        ReaderPalette(backgroundHex: theme == .custom ? customBgHex : theme.backgroundHex,
                      textHex: theme == .custom ? customTextHex : theme.textHex)
    }

    public var effectiveTextColor: Color { palette.text.color }
    public var effectiveBackgroundColor: Color { palette.background.color }

    /// The Android-shaped style snapshot, handed to `ContentProcessor` per chapter.
    public var styleConfig: ReadStyleConfig { makeStyleConfig() }
    public var storedStyles: [ReadStyleConfig] { ReaderStore.loadStyles(from: defaults) }

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
        scheduleSave()
    }

    private func persistPrefs() {
        guard !isRestoring else { return }
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        // A preference change must not cancel a pending theme save (or vice versa).
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            ReaderStore.save(self.makeStyleConfig(), to: self.defaults)
            ReaderStore.save(self.prefs, to: self.defaults)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    public func flushPendingSettings() {
        pendingSave?.cancel()
        pendingSave = nil
        ReaderStore.save(makeStyleConfig(), to: defaults)
        ReaderStore.save(prefs, to: defaults)
    }

    /// Starts from the loaded style so Android-compatible fields that have no iOS control
    /// yet (`tipHeaderLeft`, `headerMode`, `bgAlpha`, …) survive a round trip.
    private func makeStyleConfig() -> ReadStyleConfig {
        var style = baseStyle
        if style.name.isEmpty { style.name = theme.rawValue }
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
        style.pageAnim = pageAnim.rawValue
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
            apply(style: initialStyle ?? ReadStyleConfig())
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
        // Restore the page-turn mode too — it is part of the style snapshot (Android keeps
        // `pageAnim` in readConfig.json); without this every reader open fell back to scroll.
        pageAnim = PageAnim(rawValue: saved.pageAnim) ?? .scroll
        textFont = saved.textFont
        textBold = saved.textBold
        titleMode = saved.titleMode
        paddingTop = CGFloat(saved.paddingTop)
        paddingBottom = CGFloat(saved.paddingBottom)
        paddingLeading = CGFloat(saved.paddingLeft)
        paddingTrailing = CGFloat(saved.paddingRight)
        if saved.name != ReaderTheme.custom.rawValue,
           let matched = ReaderTheme.matching(backgroundHex: saved.bgStr, textHex: saved.textColor) {
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

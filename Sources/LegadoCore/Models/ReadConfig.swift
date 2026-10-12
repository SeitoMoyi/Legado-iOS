import Foundation

// MARK: - Page animation (Android constant/PageAnim.kt)

/// Raw values match Android `PageAnim`: 0 覆盖 / 1 滑动 / 2 仿真 / 3 滚动 / 4 无动画.
public enum PageAnim: Int, CaseIterable, Codable, Identifiable {
    case cover = 0
    case slide = 1
    case simulation = 2
    case scroll = 3
    case none = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .cover: return "覆盖"
        case .slide: return "滑动"
        case .simulation: return "仿真"
        case .scroll: return "滚动"
        case .none: return "无动画"
        }
    }
}

/// Android `ContentRule.imageStyle` / reader menu 「图片样式」.
public enum ReadImageStyle: String, CaseIterable, Codable, Identifiable {
    case standard = "DEFAULT"
    case full = "FULL"
    case textOnly = "TEXT"
    case singleImage = "SINGLE"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: return "默认"
        case .full: return "完整"
        case .textOnly: return "纯文字"
        case .singleImage: return "单图"
        }
    }
}

/// Header/footer info-bar item ids. Values must equal Android `ReadTipConfig` constants
/// because they are persisted inside `readConfig.json`.
public enum ReadTipItem {
    public static let none = 0
    public static let chapterTitle = 1
    public static let time = 2
    public static let battery = 3
    public static let page = 4
    public static let totalProgress = 5
    public static let pageAndTotal = 6
    public static let bookName = 7
    public static let timeBattery = 8
    public static let timeBatteryPercentage = 9
    public static let batteryPercentage = 10
    public static let totalProgress1 = 11

    public static let allLabels: [(value: Int, label: String)] = [
        (none, "无"), (chapterTitle, "标题"), (time, "时间"), (battery, "电量"),
        (batteryPercentage, "电量%"), (page, "页数"), (totalProgress, "进度(%)"),
        (totalProgress1, "进度(xx/yyy)"), (pageAndTotal, "页数及进度"),
        (bookName, "书名"), (timeBattery, "时间及电量"), (timeBatteryPercentage, "时间及电量%")
    ]
}

public enum ChineseConverterMode {
    public static let off = 0
    public static let traditionalToSimple = 1
    public static let simpleToTraditional = 2
}

// MARK: - ReadStyleConfig

/// One reader style. Property names are the **exact GSON keys** Android writes into
/// `readConfig.json` / `shareReadConfig.json` (`help/config/ReadBookConfig.kt`), so a
/// WebDAV archive produced by either platform decodes on the other.
///
/// Unit note: Android stores `textSize` in sp and the spacing fields in dp; iOS renders
/// in pt. We persist pt. The 0.9 sp/pt factor is applied only by `androidTextSizeSp` /
/// `init(androidSp:)` when exchanging a config with Android.
public struct ReadStyleConfig: Codable, Equatable {

    // Colors
    public var name: String
    public var bgStr: String
    public var bgStrNight: String
    public var bgStrEInk: String
    public var bgAlpha: Int
    public var bgType: Int
    public var textColor: String
    public var textColorNight: String
    public var textColorEInk: String
    public var darkStatusIcon: Bool

    // Typography
    public var pageAnim: Int
    public var pageAnimEInk: Int
    public var textFont: String
    public var textBold: Int
    public var textSize: Double
    public var letterSpacing: Double
    public var lineSpacingExtra: Double
    public var paragraphSpacing: Double
    public var paragraphIndent: String
    public var underline: Bool

    // Title
    public var titleMode: Int
    public var titleSize: Int
    public var titleTopSpacing: Int
    public var titleBottomSpacing: Int

    // Paddings
    public var paddingTop: Double
    public var paddingRight: Double
    public var paddingBottom: Double
    public var paddingLeft: Double
    public var headerPaddingTop: Double
    public var headerPaddingRight: Double
    public var headerPaddingBottom: Double
    public var headerPaddingLeft: Double
    public var footerPaddingTop: Double
    public var footerPaddingRight: Double
    public var footerPaddingBottom: Double
    public var footerPaddingLeft: Double
    public var showHeaderLine: Bool
    public var showFooterLine: Bool

    // Info bar
    public var tipHeaderLeft: Int
    public var tipHeaderMiddle: Int
    public var tipHeaderRight: Int
    public var tipFooterLeft: Int
    public var tipFooterMiddle: Int
    public var tipFooterRight: Int
    public var tipColor: Int
    public var tipDividerColor: Int
    public var headerMode: Int
    public var footerMode: Int

    public init(
        name: String = "",
        bgStr: String = "#EEEEEE",
        bgStrNight: String = "#000000",
        bgStrEInk: String = "#FFFFFF",
        bgAlpha: Int = 100,
        bgType: Int = 0,
        textColor: String = "#3E3D3B",
        textColorNight: String = "#ADADAD",
        textColorEInk: String = "#000000",
        darkStatusIcon: Bool = true,
        pageAnim: Int = PageAnim.cover.rawValue,
        pageAnimEInk: Int = PageAnim.none.rawValue,
        textFont: String = "",
        textBold: Int = 0,
        textSize: Double = 18,
        letterSpacing: Double = 0,
        lineSpacingExtra: Double = 8,
        paragraphSpacing: Double = 4,
        paragraphIndent: String = "　　",
        underline: Bool = false,
        titleMode: Int = 0,
        titleSize: Int = 0,
        titleTopSpacing: Int = 0,
        titleBottomSpacing: Int = 0,
        paddingTop: Double = 6,
        paddingRight: Double = 16,
        paddingBottom: Double = 6,
        paddingLeft: Double = 16,
        headerPaddingTop: Double = 0,
        headerPaddingRight: Double = 16,
        headerPaddingBottom: Double = 0,
        headerPaddingLeft: Double = 16,
        footerPaddingTop: Double = 6,
        footerPaddingRight: Double = 16,
        footerPaddingBottom: Double = 6,
        footerPaddingLeft: Double = 16,
        showHeaderLine: Bool = false,
        showFooterLine: Bool = true,
        tipHeaderLeft: Int = ReadTipItem.time,
        tipHeaderMiddle: Int = ReadTipItem.none,
        tipHeaderRight: Int = ReadTipItem.battery,
        tipFooterLeft: Int = ReadTipItem.chapterTitle,
        tipFooterMiddle: Int = ReadTipItem.none,
        tipFooterRight: Int = ReadTipItem.pageAndTotal,
        tipColor: Int = 0,
        tipDividerColor: Int = -1,
        headerMode: Int = 0,
        footerMode: Int = 0
    ) {
        self.name = name
        self.bgStr = bgStr
        self.bgStrNight = bgStrNight
        self.bgStrEInk = bgStrEInk
        self.bgAlpha = bgAlpha
        self.bgType = bgType
        self.textColor = textColor
        self.textColorNight = textColorNight
        self.textColorEInk = textColorEInk
        self.darkStatusIcon = darkStatusIcon
        self.pageAnim = pageAnim
        self.pageAnimEInk = pageAnimEInk
        self.textFont = textFont
        self.textBold = textBold
        self.textSize = textSize
        self.letterSpacing = letterSpacing
        self.lineSpacingExtra = lineSpacingExtra
        self.paragraphSpacing = paragraphSpacing
        self.paragraphIndent = paragraphIndent
        self.underline = underline
        self.titleMode = titleMode
        self.titleSize = titleSize
        self.titleTopSpacing = titleTopSpacing
        self.titleBottomSpacing = titleBottomSpacing
        self.paddingTop = paddingTop
        self.paddingRight = paddingRight
        self.paddingBottom = paddingBottom
        self.paddingLeft = paddingLeft
        self.headerPaddingTop = headerPaddingTop
        self.headerPaddingRight = headerPaddingRight
        self.headerPaddingBottom = headerPaddingBottom
        self.headerPaddingLeft = headerPaddingLeft
        self.footerPaddingTop = footerPaddingTop
        self.footerPaddingRight = footerPaddingRight
        self.footerPaddingBottom = footerPaddingBottom
        self.footerPaddingLeft = footerPaddingLeft
        self.showHeaderLine = showHeaderLine
        self.showFooterLine = showFooterLine
        self.tipHeaderLeft = tipHeaderLeft
        self.tipHeaderMiddle = tipHeaderMiddle
        self.tipHeaderRight = tipHeaderRight
        self.tipFooterLeft = tipFooterLeft
        self.tipFooterMiddle = tipFooterMiddle
        self.tipFooterRight = tipFooterRight
        self.tipColor = tipColor
        self.tipDividerColor = tipDividerColor
        self.headerMode = headerMode
        self.footerMode = footerMode
    }

    /// Android `bgAlpha` is 0-100 (percent); iOS renders 0-1.
    public var backgroundOpacity: Double { Double(bgAlpha) / 100.0 }

    /// `bgType == 2` stores an absolute device path on Android, which never resolves on
    /// another machine. Only colour backgrounds (type 0) are honoured on iOS.
    public var isColorBackground: Bool { bgType == 0 }

    public var pageAnimValue: PageAnim {
        get { PageAnim(rawValue: pageAnim) ?? .cover }
        set { pageAnim = newValue.rawValue }
    }
}

// MARK: - ReaderPrefs

/// Non-style reader preferences. Property names mirror Android `PreferKey` constants so a
/// future `config.xml` mapping layer is mechanical.
public struct ReaderPrefs: Codable, Equatable {

    /// 0 默认 / 60 / 300 / 600 / -1 常亮 (Android `keep_light`)
    public var keepLight: Int = 0
    public var hideStatusBar: Bool = false
    public var screenOrientation: Int = 0

    /// 0 调整本章页数 / 1 调整章节位置
    public var progressBarBehavior: Int = 0
    public var textFullJustify: Bool = true
    public var textBottomJustify: Bool = false
    public var noAnimScrollPage: Bool = false

    public var volumeKeyPage: Bool = true
    public var volumeKeyPageOnPlay: Bool = false
    public var keyPageOnLongPress: Bool = false
    public var mouseWheelPage: Bool = true
    public var pageTouchSlop: Int = 0

    public var autoChangeSource: Bool = false
    public var previewImageByClick: Bool = true
    public var disableReturnKey: Bool = false
    public var showReadTitleAddition: Bool = true
    public var readBarStyleFollowPage: Bool = false

    /// 3x3 tap zones, row-major TL TC TR / ML MC MR / BL BC BR. Values are Android
    /// `ReadView.click(action)` codes; see `ClickActionCode`.
    public static let defaultClickActions: [Int] = [2, 2, 1, 2, 0, 1, 2, 1, 1]
    public var clickActions: [Int] = ReaderPrefs.defaultClickActions

    public var chineseConverterType: Int = ChineseConverterMode.off
    public var replaceEnableDefault: Bool = true
    public var imageStyle: ReadImageStyle = .standard

    public var ttsSpeechRate: Int = 5
    public var ttsFollowSys: Bool = true
    public var ttsTimer: Int = 0
    public var readAloudByPage: Bool = false

    public var searchScope: String = ""
    public var searchGroup: String = ""
    public var precisionSearch: Bool = false

    public init() {}

    /// Android forces the centre zone to "menu" when no zone is assigned to it, otherwise
    /// the reader can become impossible to operate. Same guard here.
    public mutating func normalizeClickActions() {
        if clickActions.count != 9 {
            clickActions = Self.defaultClickActions
            return
        }
        if !clickActions.contains(ClickActionCode.menu.rawValue) {
            clickActions[4] = ClickActionCode.menu.rawValue
        }
    }
}

/// Android `ReadView.click(action)` codes.
public enum ClickActionCode: Int, CaseIterable, Codable {
    case menu = 0
    case nextPage = 1
    case prevPage = 2
    case nextChapter = 3
    case prevChapter = 4
    case aloudPrevParagraph = 5
    case aloudNextParagraph = 6
    case addBookmark = 7
    case editContent = 8
    case toggleReplaceRule = 9
    case openToc = 10
    case openSearch = 11
    case syncProgress = 12
    case aloudToggle = 13

    public var label: String {
        switch self {
        case .menu: return "菜单"
        case .nextPage: return "下一页"
        case .prevPage: return "上一页"
        case .nextChapter: return "下一章"
        case .prevChapter: return "上一章"
        case .aloudPrevParagraph: return "朗读上一段"
        case .aloudNextParagraph: return "朗读下一段"
        case .addBookmark: return "添加书签"
        case .editContent: return "编辑内容"
        case .toggleReplaceRule: return "替换净化"
        case .openToc: return "目录"
        case .openSearch: return "全文搜索"
        case .syncProgress: return "同步进度"
        case .aloudToggle: return "朗读播放/暂停"
        }
    }

    public static func from(_ raw: Int) -> ClickActionCode { ClickActionCode(rawValue: raw) ?? .menu }
}

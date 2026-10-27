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
/// in pt. Values are currently retained numerically across platforms; there is no
/// implicit sp/pt conversion during backup import or export.
public struct ReadStyleConfig: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

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

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, bgStr, bgStrNight, bgStrEInk, bgAlpha, bgType, textColor, textColorNight, textColorEInk, darkStatusIcon, pageAnim, pageAnimEInk, textFont, textBold, textSize, letterSpacing, lineSpacingExtra, paragraphSpacing, paragraphIndent, underline, titleMode, titleSize, titleTopSpacing, titleBottomSpacing, paddingTop, paddingRight, paddingBottom, paddingLeft, headerPaddingTop, headerPaddingRight, headerPaddingBottom, headerPaddingLeft, footerPaddingTop, footerPaddingRight, footerPaddingBottom, footerPaddingLeft, showHeaderLine, showFooterLine, tipHeaderLeft, tipHeaderMiddle, tipHeaderRight, tipFooterLeft, tipFooterMiddle, tipFooterRight, tipColor, tipDividerColor, headerMode, footerMode
    }
    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        bgStr = try c.decodeIfPresent(String.self, forKey: .bgStr) ?? bgStr
        bgStrNight = try c.decodeIfPresent(String.self, forKey: .bgStrNight) ?? bgStrNight
        bgStrEInk = try c.decodeIfPresent(String.self, forKey: .bgStrEInk) ?? bgStrEInk
        bgAlpha = try c.decodeIfPresent(Int.self, forKey: .bgAlpha) ?? bgAlpha
        bgType = try c.decodeIfPresent(Int.self, forKey: .bgType) ?? bgType
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor) ?? textColor
        textColorNight = try c.decodeIfPresent(String.self, forKey: .textColorNight) ?? textColorNight
        textColorEInk = try c.decodeIfPresent(String.self, forKey: .textColorEInk) ?? textColorEInk
        darkStatusIcon = try c.decodeIfPresent(Bool.self, forKey: .darkStatusIcon) ?? darkStatusIcon
        pageAnim = try c.decodeIfPresent(Int.self, forKey: .pageAnim) ?? pageAnim
        pageAnimEInk = try c.decodeIfPresent(Int.self, forKey: .pageAnimEInk) ?? pageAnimEInk
        textFont = try c.decodeIfPresent(String.self, forKey: .textFont) ?? textFont
        textBold = try c.decodeIfPresent(Int.self, forKey: .textBold) ?? textBold
        textSize = try c.decodeIfPresent(Double.self, forKey: .textSize) ?? textSize
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? letterSpacing
        lineSpacingExtra = try c.decodeIfPresent(Double.self, forKey: .lineSpacingExtra) ?? lineSpacingExtra
        paragraphSpacing = try c.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? paragraphSpacing
        paragraphIndent = try c.decodeIfPresent(String.self, forKey: .paragraphIndent) ?? paragraphIndent
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? underline
        titleMode = try c.decodeIfPresent(Int.self, forKey: .titleMode) ?? titleMode
        titleSize = try c.decodeIfPresent(Int.self, forKey: .titleSize) ?? titleSize
        titleTopSpacing = try c.decodeIfPresent(Int.self, forKey: .titleTopSpacing) ?? titleTopSpacing
        titleBottomSpacing = try c.decodeIfPresent(Int.self, forKey: .titleBottomSpacing) ?? titleBottomSpacing
        paddingTop = try c.decodeIfPresent(Double.self, forKey: .paddingTop) ?? paddingTop
        paddingRight = try c.decodeIfPresent(Double.self, forKey: .paddingRight) ?? paddingRight
        paddingBottom = try c.decodeIfPresent(Double.self, forKey: .paddingBottom) ?? paddingBottom
        paddingLeft = try c.decodeIfPresent(Double.self, forKey: .paddingLeft) ?? paddingLeft
        headerPaddingTop = try c.decodeIfPresent(Double.self, forKey: .headerPaddingTop) ?? headerPaddingTop
        headerPaddingRight = try c.decodeIfPresent(Double.self, forKey: .headerPaddingRight) ?? headerPaddingRight
        headerPaddingBottom = try c.decodeIfPresent(Double.self, forKey: .headerPaddingBottom) ?? headerPaddingBottom
        headerPaddingLeft = try c.decodeIfPresent(Double.self, forKey: .headerPaddingLeft) ?? headerPaddingLeft
        footerPaddingTop = try c.decodeIfPresent(Double.self, forKey: .footerPaddingTop) ?? footerPaddingTop
        footerPaddingRight = try c.decodeIfPresent(Double.self, forKey: .footerPaddingRight) ?? footerPaddingRight
        footerPaddingBottom = try c.decodeIfPresent(Double.self, forKey: .footerPaddingBottom) ?? footerPaddingBottom
        footerPaddingLeft = try c.decodeIfPresent(Double.self, forKey: .footerPaddingLeft) ?? footerPaddingLeft
        showHeaderLine = try c.decodeIfPresent(Bool.self, forKey: .showHeaderLine) ?? showHeaderLine
        showFooterLine = try c.decodeIfPresent(Bool.self, forKey: .showFooterLine) ?? showFooterLine
        tipHeaderLeft = try c.decodeIfPresent(Int.self, forKey: .tipHeaderLeft) ?? tipHeaderLeft
        tipHeaderMiddle = try c.decodeIfPresent(Int.self, forKey: .tipHeaderMiddle) ?? tipHeaderMiddle
        tipHeaderRight = try c.decodeIfPresent(Int.self, forKey: .tipHeaderRight) ?? tipHeaderRight
        tipFooterLeft = try c.decodeIfPresent(Int.self, forKey: .tipFooterLeft) ?? tipFooterLeft
        tipFooterMiddle = try c.decodeIfPresent(Int.self, forKey: .tipFooterMiddle) ?? tipFooterMiddle
        tipFooterRight = try c.decodeIfPresent(Int.self, forKey: .tipFooterRight) ?? tipFooterRight
        tipColor = try c.decodeIfPresent(Int.self, forKey: .tipColor) ?? tipColor
        tipDividerColor = try c.decodeIfPresent(Int.self, forKey: .tipDividerColor) ?? tipDividerColor
        headerMode = try c.decodeIfPresent(Int.self, forKey: .headerMode) ?? headerMode
        footerMode = try c.decodeIfPresent(Int.self, forKey: .footerMode) ?? footerMode
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(bgStr, forKey: .bgStr)
        try c.encode(bgStrNight, forKey: .bgStrNight)
        try c.encode(bgStrEInk, forKey: .bgStrEInk)
        try c.encode(bgAlpha, forKey: .bgAlpha)
        try c.encode(bgType, forKey: .bgType)
        try c.encode(textColor, forKey: .textColor)
        try c.encode(textColorNight, forKey: .textColorNight)
        try c.encode(textColorEInk, forKey: .textColorEInk)
        try c.encode(darkStatusIcon, forKey: .darkStatusIcon)
        try c.encode(pageAnim, forKey: .pageAnim)
        try c.encode(pageAnimEInk, forKey: .pageAnimEInk)
        try c.encode(textFont, forKey: .textFont)
        try c.encode(textBold, forKey: .textBold)
        try c.encode(textSize, forKey: .textSize)
        try c.encode(letterSpacing, forKey: .letterSpacing)
        try c.encode(lineSpacingExtra, forKey: .lineSpacingExtra)
        try c.encode(paragraphSpacing, forKey: .paragraphSpacing)
        try c.encode(paragraphIndent, forKey: .paragraphIndent)
        try c.encode(underline, forKey: .underline)
        try c.encode(titleMode, forKey: .titleMode)
        try c.encode(titleSize, forKey: .titleSize)
        try c.encode(titleTopSpacing, forKey: .titleTopSpacing)
        try c.encode(titleBottomSpacing, forKey: .titleBottomSpacing)
        try c.encode(paddingTop, forKey: .paddingTop)
        try c.encode(paddingRight, forKey: .paddingRight)
        try c.encode(paddingBottom, forKey: .paddingBottom)
        try c.encode(paddingLeft, forKey: .paddingLeft)
        try c.encode(headerPaddingTop, forKey: .headerPaddingTop)
        try c.encode(headerPaddingRight, forKey: .headerPaddingRight)
        try c.encode(headerPaddingBottom, forKey: .headerPaddingBottom)
        try c.encode(headerPaddingLeft, forKey: .headerPaddingLeft)
        try c.encode(footerPaddingTop, forKey: .footerPaddingTop)
        try c.encode(footerPaddingRight, forKey: .footerPaddingRight)
        try c.encode(footerPaddingBottom, forKey: .footerPaddingBottom)
        try c.encode(footerPaddingLeft, forKey: .footerPaddingLeft)
        try c.encode(showHeaderLine, forKey: .showHeaderLine)
        try c.encode(showFooterLine, forKey: .showFooterLine)
        try c.encode(tipHeaderLeft, forKey: .tipHeaderLeft)
        try c.encode(tipHeaderMiddle, forKey: .tipHeaderMiddle)
        try c.encode(tipHeaderRight, forKey: .tipHeaderRight)
        try c.encode(tipFooterLeft, forKey: .tipFooterLeft)
        try c.encode(tipFooterMiddle, forKey: .tipFooterMiddle)
        try c.encode(tipFooterRight, forKey: .tipFooterRight)
        try c.encode(tipColor, forKey: .tipColor)
        try c.encode(tipDividerColor, forKey: .tipDividerColor)
        try c.encode(headerMode, forKey: .headerMode)
        try c.encode(footerMode, forKey: .footerMode)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
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
public struct ReaderPrefs: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

    /// 0 默认 / 60 / 300 / 600 / -1 常亮 (Android `keep_light`)
    public var keepLight: Int = 0
    public var hideStatusBar: Bool = false
    public var screenOrientation: Int = 0

    /// 0 调整本章页数 / 1 调整章节位置
    public var progressBarBehavior: Int = 0
    public var textFullJustify: Bool = true
    public var textBottomJustify: Bool = false
    public var noAnimScrollPage: Bool = false

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

    enum CodingKeys: String, CodingKey, CaseIterable { case keepLight, hideStatusBar, screenOrientation, progressBarBehavior, textFullJustify, textBottomJustify, noAnimScrollPage, mouseWheelPage, pageTouchSlop, autoChangeSource, previewImageByClick, disableReturnKey, showReadTitleAddition, readBarStyleFollowPage, clickActions, chineseConverterType, replaceEnableDefault, imageStyle, ttsSpeechRate, ttsFollowSys, ttsTimer, readAloudByPage, searchScope, searchGroup, precisionSearch }
    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepLight = try c.decodeIfPresent(Int.self, forKey: .keepLight) ?? keepLight
        hideStatusBar = try c.decodeIfPresent(Bool.self, forKey: .hideStatusBar) ?? hideStatusBar
        screenOrientation = try c.decodeIfPresent(Int.self, forKey: .screenOrientation) ?? screenOrientation
        progressBarBehavior = try c.decodeIfPresent(Int.self, forKey: .progressBarBehavior) ?? progressBarBehavior
        textFullJustify = try c.decodeIfPresent(Bool.self, forKey: .textFullJustify) ?? textFullJustify
        textBottomJustify = try c.decodeIfPresent(Bool.self, forKey: .textBottomJustify) ?? textBottomJustify
        noAnimScrollPage = try c.decodeIfPresent(Bool.self, forKey: .noAnimScrollPage) ?? noAnimScrollPage
        mouseWheelPage = try c.decodeIfPresent(Bool.self, forKey: .mouseWheelPage) ?? mouseWheelPage
        pageTouchSlop = try c.decodeIfPresent(Int.self, forKey: .pageTouchSlop) ?? pageTouchSlop
        autoChangeSource = try c.decodeIfPresent(Bool.self, forKey: .autoChangeSource) ?? autoChangeSource
        previewImageByClick = try c.decodeIfPresent(Bool.self, forKey: .previewImageByClick) ?? previewImageByClick
        disableReturnKey = try c.decodeIfPresent(Bool.self, forKey: .disableReturnKey) ?? disableReturnKey
        showReadTitleAddition = try c.decodeIfPresent(Bool.self, forKey: .showReadTitleAddition) ?? showReadTitleAddition
        readBarStyleFollowPage = try c.decodeIfPresent(Bool.self, forKey: .readBarStyleFollowPage) ?? readBarStyleFollowPage
        clickActions = try c.decodeIfPresent([Int].self, forKey: .clickActions) ?? clickActions
        chineseConverterType = try c.decodeIfPresent(Int.self, forKey: .chineseConverterType) ?? chineseConverterType
        replaceEnableDefault = try c.decodeIfPresent(Bool.self, forKey: .replaceEnableDefault) ?? replaceEnableDefault
        imageStyle = try c.decodeIfPresent(ReadImageStyle.self, forKey: .imageStyle) ?? imageStyle
        ttsSpeechRate = try c.decodeIfPresent(Int.self, forKey: .ttsSpeechRate) ?? ttsSpeechRate
        ttsFollowSys = try c.decodeIfPresent(Bool.self, forKey: .ttsFollowSys) ?? ttsFollowSys
        ttsTimer = try c.decodeIfPresent(Int.self, forKey: .ttsTimer) ?? ttsTimer
        readAloudByPage = try c.decodeIfPresent(Bool.self, forKey: .readAloudByPage) ?? readAloudByPage
        searchScope = try c.decodeIfPresent(String.self, forKey: .searchScope) ?? searchScope
        searchGroup = try c.decodeIfPresent(String.self, forKey: .searchGroup) ?? searchGroup
        precisionSearch = try c.decodeIfPresent(Bool.self, forKey: .precisionSearch) ?? precisionSearch
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
        normalizeClickActions()
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keepLight, forKey: .keepLight)
        try c.encode(hideStatusBar, forKey: .hideStatusBar)
        try c.encode(screenOrientation, forKey: .screenOrientation)
        try c.encode(progressBarBehavior, forKey: .progressBarBehavior)
        try c.encode(textFullJustify, forKey: .textFullJustify)
        try c.encode(textBottomJustify, forKey: .textBottomJustify)
        try c.encode(noAnimScrollPage, forKey: .noAnimScrollPage)
        try c.encode(mouseWheelPage, forKey: .mouseWheelPage)
        try c.encode(pageTouchSlop, forKey: .pageTouchSlop)
        try c.encode(autoChangeSource, forKey: .autoChangeSource)
        try c.encode(previewImageByClick, forKey: .previewImageByClick)
        try c.encode(disableReturnKey, forKey: .disableReturnKey)
        try c.encode(showReadTitleAddition, forKey: .showReadTitleAddition)
        try c.encode(readBarStyleFollowPage, forKey: .readBarStyleFollowPage)
        try c.encode(clickActions, forKey: .clickActions)
        try c.encode(chineseConverterType, forKey: .chineseConverterType)
        try c.encode(replaceEnableDefault, forKey: .replaceEnableDefault)
        try c.encode(imageStyle, forKey: .imageStyle)
        try c.encode(ttsSpeechRate, forKey: .ttsSpeechRate)
        try c.encode(ttsFollowSys, forKey: .ttsFollowSys)
        try c.encode(ttsTimer, forKey: .ttsTimer)
        try c.encode(readAloudByPage, forKey: .readAloudByPage)
        try c.encode(searchScope, forKey: .searchScope)
        try c.encode(searchGroup, forKey: .searchGroup)
        try c.encode(precisionSearch, forKey: .precisionSearch)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }


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

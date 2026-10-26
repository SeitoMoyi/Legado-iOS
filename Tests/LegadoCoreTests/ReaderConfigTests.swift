import XCTest
@testable import LegadoCore

/// P0-2: reader style/prefs model + persistence.
///
/// The load-bearing contract here is that our stored JSON uses the *same key names* as
/// Android's GSON output (`help/config/ReadBookConfig.kt`), and that a payload missing
/// keys still decodes — GSON omits nulls, and every field we add later will be absent in
/// archives written before it existed.
final class ReaderConfigTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "LegadoReaderStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - PageAnim / ClickActionCode / ReadTipItem: raw values are the wire format

    func testPageAnimRawValuesMatchAndroid() {
        // Android constant/PageAnim.kt: 0 覆盖 1 滑动 2 仿真 3 滚动 4 无动画
        XCTAssertEqual(PageAnim.cover.rawValue, 0)
        XCTAssertEqual(PageAnim.slide.rawValue, 1)
        XCTAssertEqual(PageAnim.simulation.rawValue, 2)
        XCTAssertEqual(PageAnim.scroll.rawValue, 3)
        XCTAssertEqual(PageAnim.none.rawValue, 4)
        XCTAssertEqual(PageAnim.allCases.count, 5)
    }

    func testClickActionCodeRawValuesMatchAndroid() {
        // Android ReadView.click(action) switch codes 0...13
        XCTAssertEqual(ClickActionCode.menu.rawValue, 0)
        XCTAssertEqual(ClickActionCode.nextPage.rawValue, 1)
        XCTAssertEqual(ClickActionCode.prevPage.rawValue, 2)
        XCTAssertEqual(ClickActionCode.nextChapter.rawValue, 3)
        XCTAssertEqual(ClickActionCode.prevChapter.rawValue, 4)
        XCTAssertEqual(ClickActionCode.aloudPrevParagraph.rawValue, 5)
        XCTAssertEqual(ClickActionCode.aloudNextParagraph.rawValue, 6)
        XCTAssertEqual(ClickActionCode.addBookmark.rawValue, 7)
        XCTAssertEqual(ClickActionCode.editContent.rawValue, 8)
        XCTAssertEqual(ClickActionCode.toggleReplaceRule.rawValue, 9)
        XCTAssertEqual(ClickActionCode.openToc.rawValue, 10)
        XCTAssertEqual(ClickActionCode.openSearch.rawValue, 11)
        XCTAssertEqual(ClickActionCode.syncProgress.rawValue, 12)
        XCTAssertEqual(ClickActionCode.aloudToggle.rawValue, 13)
        XCTAssertEqual(ClickActionCode.allCases.count, 14)
    }

    func testClickActionFromUnknownCodeFallsBackToMenu() {
        XCTAssertEqual(ClickActionCode.from(99), .menu)
        XCTAssertEqual(ClickActionCode.from(-1), .menu)
        XCTAssertEqual(ClickActionCode.from(7), .addBookmark)
    }

    func testReadTipItemConstantsMatchAndroid() {
        // Android help/config/ReadTipConfig.kt
        XCTAssertEqual(ReadTipItem.none, 0)
        XCTAssertEqual(ReadTipItem.chapterTitle, 1)
        XCTAssertEqual(ReadTipItem.time, 2)
        XCTAssertEqual(ReadTipItem.battery, 3)
        XCTAssertEqual(ReadTipItem.page, 4)
        XCTAssertEqual(ReadTipItem.totalProgress, 5)
        XCTAssertEqual(ReadTipItem.pageAndTotal, 6)
        XCTAssertEqual(ReadTipItem.bookName, 7)
        XCTAssertEqual(ReadTipItem.timeBattery, 8)
        XCTAssertEqual(ReadTipItem.timeBatteryPercentage, 9)
        XCTAssertEqual(ReadTipItem.batteryPercentage, 10)
        XCTAssertEqual(ReadTipItem.totalProgress1, 11)
    }

    // MARK: - ReadStyleConfig

    func testStyleConfigDefaultsMatchAndroid() {
        let style = ReadStyleConfig()
        XCTAssertEqual(style.bgStr, "#EEEEEE")
        XCTAssertEqual(style.textColor, "#3E3D3B")
        XCTAssertEqual(style.paragraphIndent, "　　")
        XCTAssertEqual(style.showFooterLine, true)
        XCTAssertEqual(style.showHeaderLine, false)
        XCTAssertEqual(style.tipHeaderLeft, ReadTipItem.time)
        XCTAssertEqual(style.tipHeaderRight, ReadTipItem.battery)
        XCTAssertEqual(style.tipFooterLeft, ReadTipItem.chapterTitle)
        XCTAssertEqual(style.tipFooterRight, ReadTipItem.pageAndTotal)
        XCTAssertEqual(style.tipDividerColor, -1)
        XCTAssertEqual(style.backgroundOpacity, 1.0, accuracy: 0.001)
        XCTAssertTrue(style.isColorBackground)
    }

    func testStyleConfigRoundTripPreservesEveryField() throws {
        var style = ReadStyleConfig()
        style.name = "护眼绿"
        style.bgStr = "#E0F0E0"
        style.textColor = "#264026"
        style.textSize = 22.5
        style.letterSpacing = -0.4
        style.lineSpacingExtra = 11
        style.paragraphSpacing = 7.5
        style.paragraphIndent = "　　　"
        style.pageAnim = PageAnim.slide.rawValue
        style.paddingLeft = 31
        style.titleMode = 1
        style.tipFooterRight = ReadTipItem.timeBatteryPercentage
        style.bgAlpha = 65

        let decoded = try JSONDecoder().decode(ReadStyleConfig.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)
        XCTAssertEqual(decoded.backgroundOpacity, 0.65, accuracy: 0.001)
    }

    func testEncodedUsesAndroidKeyNames() throws {
        let data = try JSONEncoder().encode(ReadStyleConfig())
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Keys Android's GSON output uses. Renaming any of these breaks WebDAV interop.
        let required = [
            "name", "bgStr", "bgStrNight", "bgStrEInk", "bgAlpha", "bgType",
            "textColor", "textColorNight", "textColorEInk", "darkStatusIcon",
            "pageAnim", "pageAnimEInk", "textFont", "textBold", "textSize",
            "letterSpacing", "lineSpacingExtra", "paragraphSpacing", "paragraphIndent",
            "underline", "titleMode", "titleSize", "titleTopSpacing", "titleBottomSpacing",
            "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
            "headerPaddingTop", "footerPaddingLeft", "showHeaderLine", "showFooterLine",
            "tipHeaderLeft", "tipHeaderMiddle", "tipHeaderRight",
            "tipFooterLeft", "tipFooterMiddle", "tipFooterRight",
            "tipColor", "tipDividerColor", "headerMode", "footerMode"
        ]
        for key in required {
            XCTAssertTrue(dict.keys.contains(key), "missing Android key: \(key)")
        }
    }

    func testDecodesPartialAndroidConfig() throws {
        // A minimal Android-authored object: everything unspecified must fall back,
        // not throw.
        let json = """
        {"name":"默认","bgStr":"#EEEEEE","textColor":"#3E3D3B","textSize":20,"pageAnim":1}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        // The native style decoder now owns defaults, including for ordinary JSONDecoder callers.
        let strict = try JSONDecoder().decode(ReadStyleConfig.self, from: data)
        XCTAssertEqual(strict.paddingLeft, ReadStyleConfig().paddingLeft)
        XCTAssertEqual(strict.textSize, 20)

        let recovered = try XCTUnwrap(
            ReaderStore.tolerantDecode(ReadStyleConfig.self, from: data, fallback: ReadStyleConfig())
        )
        XCTAssertEqual(recovered.name, "默认")
        XCTAssertEqual(recovered.bgStr, "#EEEEEE")
        XCTAssertEqual(recovered.textSize, 20)
        XCTAssertEqual(recovered.pageAnim, PageAnim.slide.rawValue)
        // untouched keys keep the fallback
        XCTAssertEqual(recovered.paragraphIndent, "　　")
        XCTAssertEqual(recovered.tipFooterRight, ReadTipItem.pageAndTotal)
    }

    func testTolerantDecodeIgnoresUnknownKeysAndNulls() throws {
        var style = ReadStyleConfig()
        style.textSize = 19
        let data = try JSONEncoder().encode(style)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict["someFutureAndroidField"] = "whatever"
        dict["textColor"] = NSNull()
        let nullish = try JSONSerialization.data(withJSONObject: dict)

        let recovered = try XCTUnwrap(
            ReaderStore.tolerantDecode(ReadStyleConfig.self, from: nullish, fallback: ReadStyleConfig())
        )
        XCTAssertEqual(recovered.textSize, 19)
        // null must not overwrite the default
        XCTAssertEqual(recovered.textColor, "#3E3D3B")
    }

    func testTolerantDecodeRejectsGarbage() {
        let data = try! JSONSerialization.data(withJSONObject: [1, 2, 3])
        XCTAssertNil(ReaderStore.tolerantDecode(ReadStyleConfig.self, from: data, fallback: ReadStyleConfig()))
    }

    // MARK: - ReaderPrefs

    func testPrefsDefaultsMatchAndroid() {
        let prefs = ReaderPrefs()
        XCTAssertEqual(prefs.clickActions, [2, 2, 1, 2, 0, 1, 2, 1, 1])
        XCTAssertEqual(prefs.keepLight, 0)
        XCTAssertEqual(prefs.mouseWheelPage, true)
        XCTAssertEqual(prefs.progressBarBehavior, 0)
        XCTAssertEqual(prefs.textFullJustify, true)
        XCTAssertEqual(prefs.autoChangeSource, false)
        XCTAssertEqual(prefs.chineseConverterType, 0)
        XCTAssertEqual(prefs.replaceEnableDefault, true)
        XCTAssertEqual(prefs.ttsSpeechRate, 5)
        XCTAssertEqual(prefs.ttsTimer, 0)
        XCTAssertEqual(prefs.precisionSearch, false)
    }

    func testNormalizeClickActionsForcesMenu() {
        // Android AppConfig: if no zone is the menu, the centre becomes the menu.
        var prefs = ReaderPrefs()
        prefs.clickActions = [1, 1, 1, 1, 1, 1, 1, 1, 1]
        prefs.normalizeClickActions()
        XCTAssertEqual(prefs.clickActions[4], ClickActionCode.menu.rawValue)
        XCTAssertEqual(prefs.clickActions.filter { $0 == ClickActionCode.menu.rawValue }.count, 1)

        // An explicit menu elsewhere is left alone.
        var withMenu = ReaderPrefs()
        withMenu.clickActions = [0, 1, 1, 1, 2, 1, 2, 2, 2]
        withMenu.normalizeClickActions()
        XCTAssertEqual(withMenu.clickActions, [0, 1, 1, 1, 2, 1, 2, 2, 2])

        // Corrupt length resets to the Android default layout.
        var short = ReaderPrefs()
        short.clickActions = [1, 2]
        short.normalizeClickActions()
        XCTAssertEqual(short.clickActions, [2, 2, 1, 2, 0, 1, 2, 1, 1])
    }

    func testPreservesClickActionsTheUserChose() {
        var prefs = ReaderPrefs()
        prefs.clickActions = [3, 0, 4, 1, 7, 2, 1, 0, 2]
        prefs.normalizeClickActions()
        XCTAssertEqual(prefs.clickActions, [3, 0, 4, 1, 7, 2, 1, 0, 2])
    }

    // MARK: - ReaderStore

    func testStylePersistsAndReloads() throws {
        var style = ReadStyleConfig()
        style.textSize = 27
        style.bgStr = "#1F1F1F"
        style.paragraphIndent = ""
        ReaderStore.save(style, to: defaults)

        let reloaded = try XCTUnwrap(ReaderStore.loadStyle(from: defaults))
        XCTAssertEqual(reloaded.textSize, 27)
        XCTAssertEqual(reloaded.bgStr, "#1F1F1F")
        XCTAssertEqual(reloaded.paragraphIndent, "")
    }

    func testPrefsPersistsAndReloads() {
        var prefs = ReaderPrefs()
        prefs.ttsSpeechRate = 12
        prefs.keepLight = 300
        prefs.clickActions = [1, 1, 1, 1, 1, 1, 1, 1, 1]
        ReaderStore.save(prefs, to: defaults)

        let reloaded = ReaderStore.loadPrefs(from: defaults)
        XCTAssertEqual(reloaded.ttsSpeechRate, 12)
        XCTAssertEqual(reloaded.keepLight, 300)
        // normalized on the way in as well
        XCTAssertEqual(reloaded.clickActions[4], ClickActionCode.menu.rawValue)
    }

    func testEmptyStoreReturnsNilStyleAndDefaultPrefs() {
        XCTAssertNil(ReaderStore.loadStyle(from: defaults))
        XCTAssertEqual(ReaderStore.loadPrefs(from: defaults), ReaderPrefs())
    }

    func testLegacyPageModeIsReadThenCleared() {
        defaults.set("左右翻页", forKey: ReaderStore.legacyPageModeKey)
        XCTAssertEqual(ReaderStore.legacyPageMode(in: defaults), "左右翻页")
        ReaderStore.clearLegacyPageMode(from: defaults)
        XCTAssertNil(ReaderStore.legacyPageMode(in: defaults))
    }

    func testMissingPrefsKeysInOlderPayloadFallBack() throws {
        // A prefs blob written before `imageStyle` existed, carrying one key iOS no longer
        // has at all (the removed brightness feature). Neither may break the decode.
        let json = "{\"brightness\":100,\"ttsSpeechRate\":8}"
        let recovered = try XCTUnwrap(
            ReaderStore.tolerantDecode(ReaderPrefs.self,
                                       from: Data(json.utf8),
                                       fallback: ReaderPrefs())
        )
        XCTAssertEqual(recovered.ttsSpeechRate, 8)
        XCTAssertEqual(recovered.imageStyle, .standard)
        XCTAssertEqual(recovered.keepLight, 0)
    }
}

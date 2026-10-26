import XCTest
import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#endif
#if canImport(LegadoCore)
import LegadoCore
#endif
@testable import LegadoApp

final class ReaderThemeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "ReaderThemeTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFreshInstallStartsWithReadablePresetWithoutSelectingTheme() {
        let config = ReaderConfig(defaults: defaults)
        XCTAssertEqual(config.theme, .parchment)
        XCTAssertNotEqual(config.palette.text.composited(over: config.palette.background), config.palette.background)
    }

    func testColdLaunchRestoresCustomTextEvenOnPresetBackground() {
        var style = ReadStyleConfig()
        style.bgStr = ReaderTheme.white.backgroundHex
        style.textColor = "#008800"
        ReaderStore.save(style, to: defaults)
        let config = ReaderConfig(defaults: defaults)
        XCTAssertEqual(config.theme, .custom)
        XCTAssertEqual(config.palette.text, ReaderHexColor(hex: "#008800"))
        XCTAssertEqual(config.styleConfig.textColor, "#008800")
    }

    func testExplicitCustomThemeStaysCustomWhenColorsMatchPreset() {
        var style = ReadStyleConfig()
        style.name = ReaderTheme.custom.rawValue
        style.bgStr = ReaderTheme.dark.backgroundHex
        style.textColor = ReaderTheme.dark.textHex
        ReaderStore.save(style, to: defaults)
        XCTAssertEqual(ReaderConfig(defaults: defaults).theme, .custom)
    }

    func testInvalidRestoredColorsDoNotMakeBodyAndBackgroundGray() {
        var style = ReadStyleConfig()
        style.bgStr = "#"
        style.textColor = "12ZZZZ"
        ReaderStore.save(style, to: defaults)
        let config = ReaderConfig(defaults: defaults)
        XCTAssertEqual(config.palette.background, ReaderHexColor(hex: ReaderTheme.custom.backgroundHex))
        XCTAssertEqual(config.palette.text, ReaderHexColor(hex: ReaderTheme.custom.textHex))
        // Preserve the original editor values; recovery must not discard imported settings.
        XCTAssertEqual(config.customBgHex, "#")
        XCTAssertEqual(config.customTextHex, "12ZZZZ")
    }

    func testIdenticalOrTransparentRestoredTextIsReadableImmediately() {
        for background in ["#000000", "#FFFFFF", "#777777"] {
            for text in [background, "#00112233"] {
                var style = ReadStyleConfig()
                style.name = ReaderTheme.custom.rawValue
                style.bgStr = background
                style.textColor = text
                ReaderStore.save(style, to: defaults)
                let config = ReaderConfig(defaults: defaults)
                XCTAssertNotEqual(config.palette.text.composited(over: config.palette.background), config.palette.background)
            }
        }
    }

    func testAndroidArgbAndShortRgbParseWithoutGrayFallback() {
        XCTAssertEqual(ReaderHexColor(hex: "#FF112233"), ReaderHexColor(hex: "#112233"))
        XCTAssertEqual(ReaderHexColor(hex: "#abc"), ReaderHexColor(hex: "#AABBCC"))
        XCTAssertEqual(ReaderHexColor(hex: " #ff112233 \n"), ReaderHexColor(hex: "112233"))
        for invalid in ["", "#", "12ZZZZ", "1234567", "#GGGGGG", "#12345Z"] {
            XCTAssertNil(ReaderHexColor(hex: invalid), invalid)
        }
    }

    func testPreferenceChangeDoesNotCancelThemePersistence() {
        let config = ReaderConfig(defaults: defaults)
        config.theme = .custom
        config.customBgHex = "#102030"
        config.customTextHex = "#EEEEEE"
        config.prefs.keepLight = 3
        let saved = expectation(description: "Debounced theme and preferences saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { saved.fulfill() }
        wait(for: [saved], timeout: 2)
        let restored = ReaderConfig(defaults: defaults)
        XCTAssertEqual(restored.theme, .custom)
        XCTAssertEqual(restored.customBgHex, "#102030")
        XCTAssertEqual(restored.customTextHex, "#EEEEEE")
        XCTAssertEqual(restored.prefs.keepLight, config.prefs.keepLight)
    }

    #if os(macOS)
    func testBodyDrawsOnFirstRenderWithRestoredCustomTheme() throws {
        for (background, text) in [("#", "#"), ("#000000", "#000000"), ("#FF112233", "#FFF0E0D0")] {
            var style = ReadStyleConfig()
            style.name = ReaderTheme.custom.rawValue
            style.bgStr = background
            style.textColor = text
            ReaderStore.save(style, to: defaults)
            let config = ReaderConfig(defaults: defaults)
            let width = 320, height = 100
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.setFillColor(NSColor(config.effectiveBackgroundColor).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            CoreTextPageRenderer.draw(
                ctx: context, lines: ["首次打开，正文应当可见。"], isParagraphEnd: [true],
                fontSize: 20, lineSpacing: 8, textColor: NSColor(config.effectiveTextColor).cgColor,
                containerWidth: CGFloat(width), letterSpacing: 0, paragraphSpacing: 0, justify: false)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let hasVisibleText = stride(from: 0, to: width * height * 4, by: 4).contains { offset in
                (0..<3).contains { abs(Int(pixels[offset + $0]) - Int(pixels[$0])) > 10 }
            }
            XCTAssertTrue(hasVisibleText, "Restored colors \(background) / \(text) must draw body glyphs before any theme change")
        }
    }
    #endif
}

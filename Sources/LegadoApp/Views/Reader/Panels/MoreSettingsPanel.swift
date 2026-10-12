import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// The 「更多设置」 panel — the iOS counterpart of Android's `pref_config_read.xml`,
/// restricted to what iOS can actually honour. Entries that Android has but iOS cannot
/// (dual-page, cutout padding, render optimisation…) are simply not offered.
///
/// Same `ReaderPanelCard` and same rows as 「界面」, so the two sheets are one card at one
/// height on one edge. There are more entries here than fit that height, so the card scrolls
/// instead of growing past 「界面」.
struct MoreSettingsPanel: View {
    @ObservedObject var config: ReaderConfig
    let onClose: () -> Void
    /// Re-reads the current chapter: 简繁转换 and 图片样式 are applied while text is processed.
    var onChapterRefresh: () -> Void = {}
    /// Re-pages without re-reading: 页边距 and 文字两端对齐 only affect layout.
    var onRepaginate: () -> Void = {}
    @State private var showTapZones = false

    var body: some View {
        ReaderPanelCard(config: config, scrollable: true) {
            VStack(alignment: .leading, spacing: ReaderPanelMetrics.rowSpacing) {
                ReaderPanelHeader(title: "更多设置", config: config, onClose: onClose)

                section("显示") {
                    ReaderPanelSwitchRow(title: "隐藏状态栏", config: config,
                                         isOn: pref(\.hideStatusBar))
                    ReaderPanelSwitchRow(title: "展示顶部工具栏附加区域", config: config,
                                         isOn: pref(\.showReadTitleAddition))
                    ReaderPanelSwitchRow(title: "文字两端对齐", config: config,
                                         isOn: pref(\.textFullJustify, after: onRepaginate))
                    ReaderPanelMenuRow(title: "屏幕常亮", config: config,
                                       current: keepLightLabel, labelWidth: nil) {
                        ForEach(keepLightChoices, id: \.value) { choice in
                            Button(choice.label) { setKeepLight(choice.value) }
                        }
                    }
                }

                section("翻页") {
                    ReaderPanelStepperRow(title: "滑动翻页阈值", config: config,
                                          value: pref(\.pageTouchSlop),
                                          range: 0...300, step: 5,
                                          suffix: slopLabel)
                }

                section("内容") {
                    ReaderPanelNavRow(title: "点击区域设置", config: config) { showTapZones = true }
                    ReaderPanelMenuRow(title: "简繁转换", config: config,
                                       current: converterLabel, labelWidth: nil) {
                        ForEach(converterChoices, id: \.value) { choice in
                            Button(choice.label) { setConverter(choice.value) }
                        }
                    }
                    ReaderPanelMenuRow(title: "图片样式", config: config,
                                       current: config.prefs.imageStyle.label, labelWidth: nil) {
                        ForEach(ReadImageStyle.allCases) { style in
                            Button(style.label) {
                                config.prefs.imageStyle = style
                                onChapterRefresh()
                            }
                        }
                    }
                    ReaderPanelSwitchRow(title: "新书默认启用净化", config: config,
                                         isOn: pref(\.replaceEnableDefault))
                    ReaderPanelSwitchRow(title: "自动换源", config: config,
                                         isOn: pref(\.autoChangeSource))
                }

                section("页边距") {
                    ReaderPanelSliderRow(title: "左右边距", config: config,
                                         value: $config.paddingLeading, range: 0...48, step: 2,
                                         suffix: "\(Int(config.paddingLeading))", labelWidth: nil,
                                         onChange: { config.syncTrailingPadding(); onRepaginate() })
                    ReaderPanelSliderRow(title: "上下边距", config: config,
                                         value: $config.paddingTop, range: 0...48, step: 2,
                                         suffix: "\(Int(config.paddingTop))", labelWidth: nil,
                                         onChange: { config.syncBottomPadding(); onRepaginate() })
                }
            }
        }
        .sheet(isPresented: $showTapZones) {
            NavigationView {
                TapZoneEditorPanel(config: config)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showTapZones = false }
                        }
                    }
            }
        }
    }

    /// A group caption plus its rows. Rows keep 「界面」's spacing inside the group; the groups
    /// themselves sit one `rowSpacing` apart.
    private func section<Content: View>(_ title: String,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ReaderPanelSection(title: title, config: config)
            content()
        }
    }

    /// Binding into a preference, with an optional follow-up for the settings whose effect only
    /// shows once the chapter is re-laid-out or re-read.
    private func pref<T>(_ keyPath: WritableKeyPath<ReaderPrefs, T>,
                         after: @escaping () -> Void = {}) -> Binding<T> {
        Binding(
            get: { config.prefs[keyPath: keyPath] },
            set: { newValue in
                var prefs = config.prefs
                prefs[keyPath: keyPath] = newValue
                config.prefs = prefs
                after()
            }
        )
    }

    private var slopLabel: String {
        config.prefs.pageTouchSlop == 0 ? "系统默认" : "\(config.prefs.pageTouchSlop) pt"
    }

    private struct Choice { let value: Int; let label: String }

    private let keepLightChoices = [Choice(value: 0, label: "默认"), Choice(value: 60, label: "1 分钟"),
                                    Choice(value: 300, label: "5 分钟"), Choice(value: 600, label: "10 分钟"),
                                    Choice(value: -1, label: "常亮")]

    private let converterChoices = [Choice(value: ChineseConverterMode.off, label: "关闭"),
                                    Choice(value: ChineseConverterMode.traditionalToSimple, label: "繁体转简体"),
                                    Choice(value: ChineseConverterMode.simpleToTraditional, label: "简体转繁体")]

    private var keepLightLabel: String {
        keepLightChoices.first { $0.value == config.prefs.keepLight }?.label ?? "默认"
    }

    private var converterLabel: String {
        converterChoices.first { $0.value == config.prefs.chineseConverterType }?.label ?? "关闭"
    }

    private func setKeepLight(_ value: Int) {
        var prefs = config.prefs
        prefs.keepLight = value
        config.prefs = prefs
    }

    private func setConverter(_ value: Int) {
        var prefs = config.prefs
        prefs.chineseConverterType = value
        config.prefs = prefs
        onChapterRefresh()
    }
}

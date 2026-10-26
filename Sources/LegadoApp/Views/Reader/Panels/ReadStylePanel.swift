import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// The 「界面」 panel: typography, colours and page animation.
///
/// Every control writes straight into `ReaderConfig`, which persists on change (P0-2), so a
/// slider drag survives a relaunch. Chrome and rows come from `ReaderPanelChrome`, which
/// 「更多设置」 uses too — the two panels are the same card by construction.
struct ReadStylePanel: View {
    @ObservedObject var config: ReaderConfig
    let onRepaginate: () -> Void
    let onClose: () -> Void
    let onOpenMore: () -> Void

    var body: some View {
        // Scrollable with the rest, so both sheets are exactly one height on every device
        // instead of one hugging its content and the other not.
        ReaderPanelCard(config: config, scrollable: true) {
            VStack(alignment: .leading, spacing: ReaderPanelMetrics.rowSpacing) {
                Group {
                    ReaderPanelHeader(title: "阅读界面", config: config, onClose: onClose)

                    ReaderPanelSliderRow(title: "字号", config: config, value: $config.fontSize,
                                         range: 12...32, step: 1,
                                         suffix: "\(Int(config.fontSize)) pt") { onRepaginate() }

                    ReaderPanelSliderRow(title: "行距", config: config, value: $config.lineSpacing,
                                         range: 2...30, step: 1,
                                         suffix: "\(Int(config.lineSpacing))") { onRepaginate() }

                    ReaderPanelSliderRow(title: "字距", config: config,
                                         value: config.styleField(\.letterSpacing).mapCGFloat(),
                                         range: -0.5...0.5, step: 0.05,
                                         suffix: String(format: "%.2f", config.letterSpacing)) { onRepaginate() }

                    ReaderPanelSliderRow(title: "段距", config: config,
                                         value: config.styleField(\.paragraphSpacing).mapCGFloat(),
                                         range: 0...20, step: 0.5,
                                         suffix: String(format: "%.1f", config.paragraphSpacing)) { onRepaginate() }
                }

                Group {
                    ReaderPanelMenuRow(title: "字体", config: config, current: fontLabel) {
                        Button("系统默认 (苹方)") { config.textFont = ""; onRepaginate() }
                        Button("楷体 (STKaiti)") { config.textFont = "STKaiti"; onRepaginate() }
                        Button("宋体 (Songti SC)") { config.textFont = "Songti SC"; onRepaginate() }
                        Button("圆体 (Yuanti SC)") { config.textFont = "Yuanti SC"; onRepaginate() }
                    }

                    ReaderPanelMenuRow(title: "缩进", config: config, current: indentLabel) {
                        ForEach(ReaderConfig.indentChoices, id: \.value) { choice in
                            Button(choice.label) { config.paragraphIndent = choice.value; onRepaginate() }
                        }
                    }
                    // Android `rg_page_anim` 同构：五等宽方块横置单选（覆盖/滑动/仿真/滚动/无动画）。
                    blockSelector(title: "翻页",
                                  options: PageAnim.allCases,
                                  label: { $0.label },
                                  isSelected: { config.pageAnim == $0 },
                                  onSelect: { config.setPageAnim($0) })

                    ReaderPanelRow(title: "主题", config: config,
                                   labelWidth: ReaderPanelMetrics.shortLabelWidth) {
                        HStack(spacing: 8) {
                            ForEach(ReaderTheme.allCases) { theme in
                                themeButton(for: theme)
                            }
                        }
                    }

                    if config.theme == .custom {
                        HStack(spacing: 12) {
                            HStack {
                                Text("背景色")
                                    .font(.caption)
                                    .foregroundColor(config.effectiveTextColor.opacity(0.8))
                                TextField("#F5EAD8", text: $config.customBgHex)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(config.effectiveTextColor.opacity(0.08))
                            .cornerRadius(6)

                            HStack {
                                Text("文字色")
                                    .font(.caption)
                                    .foregroundColor(config.effectiveTextColor.opacity(0.8))
                                TextField("#332211", text: $config.customTextHex)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(config.effectiveTextColor.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    HStack {
                        Button("更多设置", action: onOpenMore)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("点击正文区域可自定义翻页")
                            .font(.caption2)
                            .foregroundColor(config.effectiveTextColor.opacity(0.5))
                    }
                }
            }
        }
    }

    /// 方块横置单选组：小标题 + 一排等宽方块，选中项 accent 实心白字
    /// （对应 Android RadioGroup + button=@null 的块状 RadioButton）。
    private func blockSelector<T: Identifiable>(
        title: String,
        options: [T],
        label: @escaping (T) -> String,
        isSelected: @escaping (T) -> Bool,
        onSelect: @escaping (T) -> Void
    ) -> some View where T: Hashable {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(config.effectiveTextColor.opacity(0.6))
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = isSelected(option)
                    Button {
                        onSelect(option)
                    } label: {
                        Text(label(option))
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundColor(selected ? Color.white : config.effectiveTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selected ? Color.accentColor : config.effectiveTextColor.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 纯色主题块（对齐 Android StyleAdapter 色块）：无文字，底色即主题背景色，
    /// 内嵌 "文" 字样张显前景对比，选中 accent 描边。小屏不再出现省略号。
    private func themeButton(for theme: ReaderTheme) -> some View {
        let isSelected = (config.theme == theme)
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                config.theme = theme
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.backgroundColor)
                Text("文")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : config.effectiveTextColor.opacity(0.15),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.rawValue)
    }

    private var indentLabel: String {
        ReaderConfig.indentChoices.first { $0.value == config.paragraphIndent }?.label ?? "自定义"
    }

    private var fontLabel: String {
        switch config.textFont {
        case "STKaiti": return "楷体"
        case "Songti SC": return "宋体"
        case "Yuanti SC": return "圆体"
        default: return "系统默认"
        }
    }
}

private extension Binding where Value == Double {
    /// Panels work in `CGFloat`; the persisted model keeps Android-shaped `Double`s.
    func mapCGFloat() -> Binding<CGFloat> {
        Binding<CGFloat>(get: { CGFloat(wrappedValue) }, set: { wrappedValue = Double($0) })
    }
}

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
                    ReaderPanelMenuRow(title: "翻页", config: config, current: config.pageAnim.label) {
                        ForEach(PageAnim.allCases) { anim in
                            Button(anim.label) { config.setPageAnim(anim); onRepaginate() }
                        }
                    }

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
                                    .foregroundColor(config.theme.textColor.opacity(0.8))
                                TextField("#F5EAD8", text: $config.customBgHex)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(config.theme.textColor.opacity(0.08))
                            .cornerRadius(6)

                            HStack {
                                Text("文字色")
                                    .font(.caption)
                                    .foregroundColor(config.theme.textColor.opacity(0.8))
                                TextField("#332211", text: $config.customTextHex)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(config.theme.textColor.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    HStack {
                        Button("更多设置", action: onOpenMore)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("点击正文区域可自定义翻页")
                            .font(.caption2)
                            .foregroundColor(config.theme.textColor.opacity(0.5))
                    }
                }
            }
        }
    }

    private func themeButton(for theme: ReaderTheme) -> some View {
        let isSelected = (config.theme == theme)
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                config.theme = theme
            }
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.backgroundColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(config.theme.textColor.opacity(0.25), lineWidth: 1))
                Text(theme.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : config.theme.textColor.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : config.theme.textColor)
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

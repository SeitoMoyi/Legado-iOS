import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Shared chrome and row primitives for the bottom reader panels.
///
/// 「界面」/「更多设置」/「朗读」 are one card, one height, one edge. They used to each carry
/// their own copy of the paddings and colours, which drifted into three different-looking
/// sheets — different height, different position, row labels in different colours. Everything
/// the panels draw now lives here once.
enum ReaderPanelMetrics {
    /// How much of the reading screen the card takes: the lower half.
    static let heightFraction: CGFloat = 0.5
    /// 「界面」's titles are two characters and line up in a column; 「更多设置」's are not.
    static let shortLabelWidth: CGFloat = 36
    static let valueWidth: CGFloat = 46
    static let cornerRadius: CGFloat = 16
    static let rowSpacing: CGFloat = 13
}

/// The card, exactly as the first 「界面」 panel drew it: inner padding, theme background with a
/// shadow, four rounded corners, hairline stroke, and the 10/6 pt margin that keeps it off the
/// screen edges.
struct ReaderPanelCard<Content: View>: View {
    let config: ReaderConfig
    var scrollable: Bool = false
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReaderPanelMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        inner
            .frame(maxWidth: .infinity)
            // Rows that only set a font inherit this, which is what keeps a light theme readable
            // when the system is in dark mode.
            .foregroundColor(config.theme.textColor)
            .background(
                config.theme.backgroundColor
                    .opacity(0.98)
                    .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: -6)
                    .ignoresSafeArea(edges: .bottom)
            )
            .clipShape(shape)
            .overlay(shape.stroke(config.theme.textColor.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
    }

    @ViewBuilder private var inner: some View {
        if scrollable {
            ScrollView { padded }
        } else {
            padded
        }
    }

    private var padded: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
    }
}

/// Title + optional readout + close button.
struct ReaderPanelHeader<Accessory: View>: View {
    let title: String
    let config: ReaderConfig
    let onClose: () -> Void
    var accessory: () -> Accessory

    init(title: String, config: ReaderConfig, onClose: @escaping () -> Void,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.config = config
        self.onClose = onClose
        self.accessory = accessory
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(config.theme.textColor)
            accessory()
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(config.theme.textColor.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Section caption such as 显示 / 翻页输入.
struct ReaderPanelSection: View {
    let title: String
    let config: ReaderConfig

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(config.theme.textColor.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `title` plus whatever control follows it. The title colour and font are the one definition
/// both panels share, which is what fixes the mismatched labels.
struct ReaderPanelRow<Trailing: View>: View {
    let title: String
    let config: ReaderConfig
    var labelWidth: CGFloat? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(config.theme.textColor.opacity(0.7))
                .frame(width: labelWidth, alignment: .leading)
            trailing()
        }
    }
}

/// Right-hand monospaced readout, e.g. 「18 pt」.
///
/// `minWidth` rather than `width`: numbers line up at 46 pt, but a CJK readout like 「系统默认」
/// needs more and must not truncate.
struct ReaderPanelValue: View {
    let text: String
    let config: ReaderConfig

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(config.theme.textColor.opacity(0.7))
            .lineLimit(1)
            .frame(minWidth: ReaderPanelMetrics.valueWidth, alignment: .trailing)
    }
}

/// The value capsule a `Menu` opens.
struct ReaderPanelCapsule: View {
    let current: String
    let config: ReaderConfig

    var body: some View {
        HStack(spacing: 4) {
            Text(current)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10))
        }
        .font(.system(size: 13))
        .foregroundColor(config.theme.textColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(config.theme.textColor.opacity(0.06))
        )
    }
}

// MARK: - Ready-made rows

struct ReaderPanelSliderRow: View {
    let title: String
    let config: ReaderConfig
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let suffix: String
    var labelWidth: CGFloat? = ReaderPanelMetrics.shortLabelWidth
    let onChange: () -> Void

    var body: some View {
        ReaderPanelRow(title: title, config: config, labelWidth: labelWidth) {
            Slider(value: $value, in: range, step: step)
                .onChange(of: value) { _ in onChange() }
            ReaderPanelValue(text: suffix, config: config)
        }
    }
}

struct ReaderPanelMenuRow<MenuContent: View>: View {
    let title: String
    let config: ReaderConfig
    let current: String
    var labelWidth: CGFloat? = ReaderPanelMetrics.shortLabelWidth
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        // The capsule is trailing-aligned like the switch, stepper and disclosure rows, so both
        // panels read as one form: label on the left, control on the right.
        ReaderPanelRow(title: title, config: config, labelWidth: labelWidth) {
            Spacer(minLength: 0)
            Menu {
                menu()
            } label: {
                ReaderPanelCapsule(current: current, config: config)
            }
        }
    }
}

struct ReaderPanelSwitchRow: View {
    let title: String
    let config: ReaderConfig
    @Binding var isOn: Bool

    var body: some View {
        ReaderPanelRow(title: title, config: config) {
            Spacer(minLength: 0)
            // Label is passed but hidden so VoiceOver still announces which switch is which.
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct ReaderPanelStepperRow: View {
    let title: String
    let config: ReaderConfig
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    var body: some View {
        ReaderPanelRow(title: title, config: config) {
            Spacer(minLength: 0)
            ReaderPanelValue(text: suffix, config: config)
            Stepper(title, value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

/// A row that opens something else; the chevron is the only hint it needs.
struct ReaderPanelNavRow: View {
    let title: String
    let config: ReaderConfig
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReaderPanelRow(title: title, config: config) {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(config.theme.textColor.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }
}

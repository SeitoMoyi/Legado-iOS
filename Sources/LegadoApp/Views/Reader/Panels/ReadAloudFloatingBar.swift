import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Floating read-aloud controls: 播放 / 暂停 / 结束.
///
/// Deliberately independent of the menu and the panels — it is driven by the speech state, so
/// playback can be stopped or resumed without opening anything. The 朗读面板 carries the fine
/// controls (逐段、语速、定时); this bar exists so a reader who started speaking is never stuck
/// with a chapter reading aloud and no visible way to stop it.
struct ReadAloudFloatingBar: View {
    @ObservedObject var audio: AudioBookService
    let config: ReaderConfig
    /// Start/continue goes through the reader's re-anchoring policy — after 翻页 the queue must
    /// restart at the newly visible paragraph, not the stale speaking index.
    var onPlay: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            control(icon: "play.circle.fill", label: "播放",
                    highlight: !audio.isPlaying,
                    enabled: !audio.isPlaying, action: onPlay)
            control(icon: "pause.circle.fill", label: "暂停",
                    highlight: audio.isPlaying,
                    enabled: audio.isPlaying) { audio.pause() }
            control(icon: "stop.circle.fill", label: "结束",
                    highlight: false,
                    enabled: true) { audio.stop() }
        }
        .padding(.vertical, 6)
        .background(
            Capsule().fill(config.theme.backgroundColor.opacity(0.92))
        )
        .overlay(
            Capsule().stroke(config.theme.textColor.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 2)
    }

    private func control(icon: String, label: String, highlight: Bool, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(disabledColor(enabled: enabled, highlight: highlight))
            .frame(width: 54)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func disabledColor(enabled: Bool, highlight: Bool) -> Color {
        if !enabled { return config.theme.textColor.opacity(0.28) }
        return highlight ? .accentColor : config.theme.textColor
    }
}

import SwiftUI
import AVFoundation
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Read-aloud control panel — the iOS counterpart of Android's `ReadAloudDialog`.
///
/// Paragraph stepping, 定时 (0…180 min), 语速 and 音调 are the same controls; Android's
/// engine picker and HttpTTS switching both live here via `AudioBookService`.
struct ReadAloudPanel: View {
    @ObservedObject var audio: AudioBookService
    @ObservedObject var config: ReaderConfig

    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onOpenToc: () -> Void
    let onMainMenu: () -> Void
    let onGoBackground: () -> Void
    let onOpenSettings: () -> Void
    /// Start/continue via the reader's re-anchor policy (翻页后从新页开头读).
    var onPlayPause: () -> Void = {}

    private static let timerPresets = [0, 5, 10, 15, 30, 60, 90, 180]

    var body: some View {
        ReaderPanelCard(config: config, scrollable: true) {
            VStack(alignment: .leading, spacing: ReaderPanelMetrics.rowSpacing) {
                ReaderPanelHeader(title: "朗读", config: config, onClose: onMainMenu) {
                    if audio.timerMinutes > 0 {
                        ReaderPanelValue(text: "剩余 \(audio.timerRemaining) 分钟", config: config)
                    }
                }

                transportRow

                timerRow

                rateRow

                engineRow

                HStack(spacing: 10) {
                    chip("目录", systemImage: "list.bullet", action: onOpenToc)
                    chip("主菜单", systemImage: "book", action: onMainMenu)
                    chip("后台", systemImage: "arrow.down.forward", action: onGoBackground)
                    chip("设置", systemImage: "slider.horizontal.3", action: onOpenSettings)
                    Spacer()
                }
            }
        }
        .onAppear {
            audio.speechRatePref = config.prefs.ttsSpeechRate
            audio.followSystemRate = config.prefs.ttsFollowSys
            audio.timerMinutes = config.prefs.ttsTimer
        }
        .onChange(of: audio.speechRatePref) { value in persist(\.ttsSpeechRate, value) }
        .onChange(of: audio.followSystemRate) { value in persist(\.ttsFollowSys, value) }
        .onChange(of: audio.timerMinutes) { value in persist(\.ttsTimer, value) }
    }

    private func persist<Value>(_ keyPath: WritableKeyPath<ReaderPrefs, Value>, _ value: Value) {
        var prefs = config.prefs
        prefs[keyPath: keyPath] = value
        config.prefs = prefs
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            transportButton("chevron.left", label: "上一章", enabled: canGoPrevious, action: onPreviousChapter)
            transportButton("arrow.turn.up.left", label: "上一段", enabled: true) { audio.prevParagraph() }
            transportButton(audio.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                            label: audio.isPlaying ? "暂停" : "播放",
                            enabled: true, emphasized: true, action: onPlayPause)
            transportButton("stop.circle", label: "停止", enabled: audio.isActive) { audio.stop() }
            transportButton("arrow.turn.up.right", label: "下一段", enabled: true) { audio.nextParagraph() }
            transportButton("chevron.right", label: "下一章", enabled: canGoNext, action: onNextChapter)
        }
    }

    private func transportButton(_ icon: String, label: String, enabled: Bool,
                                 emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: emphasized ? 24 : 17))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(enabled ? (emphasized ? .accentColor : config.theme.textColor)
                                     : config.theme.textColor.opacity(0.3))
            .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)
    }

    private var timerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("定时停止")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(audio.timerMinutes == 0 ? "不开启" : "\(audio.timerMinutes) 分钟")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(config.theme.textColor.opacity(0.7))
            }
            Slider(value: Binding(get: { Double(audio.timerMinutes) },
                                  set: { audio.timerMinutes = Int($0.rounded()) }),
                   in: 0...180, step: 5)
            HStack(spacing: 6) {
                ForEach(Self.timerPresets, id: \.self) { minutes in
                    Button(minutes == 0 ? "关" : "\(minutes)") {
                        audio.timerMinutes = minutes
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(audio.timerMinutes == minutes
                                  ? Color.accentColor.opacity(0.18)
                                  : config.theme.textColor.opacity(0.06))
                    )
                }
            }
        }
    }

    private var engineRow: some View {
        let engines = HttpTTSStore.load().filter { $0.enabled }
        return ReaderPanelMenuRow(title: "引擎", config: config, current: audio.selectedEngineName) {
            ForEach(engines) { e in
                Button(e.name) {
                    audio.selectedEngineName = e.name
                    if audio.isPlaying {
                        audio.speakParagraph(at: audio.currentIndex)
                    }
                }
            }
        }
    }

    private var rateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("语速")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(audio.followSystemRate ? "跟随系统"
                                            : String(format: "%.1fx", Double(audio.effectiveRate / AVSpeechUtteranceDefaultSpeechRate)))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(config.theme.textColor.opacity(0.7))
                Button {
                    audio.followSystemRate.toggle()
                } label: {
                    Image(systemName: audio.followSystemRate ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("−") { audio.speechRatePref = max(0, audio.speechRatePref - 1) }
                Slider(value: Binding(get: { Double(audio.speechRatePref) },
                                      set: { audio.speechRatePref = Int($0.rounded()) }),
                       in: 0...45, step: 1)
                    .disabled(audio.followSystemRate)
                Button("+") { audio.speechRatePref = min(45, audio.speechRatePref + 1) }
            }
            HStack {
                Text("音调")
                    .font(.system(size: 13, weight: .medium))
                Slider(value: $audio.pitch, in: 0.5...1.8)
                Text(String(format: "%.1f", audio.pitch))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(config.theme.textColor.opacity(0.7))
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func chip(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 12))
                Text(label).font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(config.theme.textColor.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

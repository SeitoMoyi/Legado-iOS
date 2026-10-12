import SwiftUI
#if os(iOS)
import MediaPlayer
#endif

/// Hardware volume buttons as page-turn input.
///
/// iOS has no volume-key event. The only route available on the iOS 15 deployment floor is
/// a hidden `MPVolumeView`: its internal slider tracks the system volume, so pressing a
/// volume key moves it, and we immediately write the previous value back so the user's
/// volume is unchanged.
///
/// The supported replacement, `AVAudioApplication.addInputVolumeButtonHandler(for:handler:)`,
/// exists from iOS 17 — it cannot be compiled against the iOS 16 SDK this project still
/// builds with, so it is deliberately not referenced here. When the deployment toolchain
/// gains iOS 17, prefer it and keep this as the fallback.
///
/// Nothing fires while a reader panel is open, matching Android's
/// `if (menuLayoutIsVisible) return super.onKeyDown(...)`.
public struct VolumeKeyObserver: View {
    var isEnabled: Bool
    var ignoreWhilePlaying: Bool
    var isPlaying: Bool
    var continuousWhilePressed: Bool
    var onPage: (_ forward: Bool) -> Void

    public init(isEnabled: Bool,
                ignoreWhilePlaying: Bool = false,
                isPlaying: Bool = false,
                continuousWhilePressed: Bool = false,
                onPage: @escaping (Bool) -> Void) {
        self.isEnabled = isEnabled
        self.ignoreWhilePlaying = ignoreWhilePlaying
        self.isPlaying = isPlaying
        self.continuousWhilePressed = continuousWhilePressed
        self.onPage = onPage
    }

    public var body: some View {
        #if os(iOS)
        VolumeKeyProxy(isEnabled: isEnabled,
                       ignoreWhilePlaying: ignoreWhilePlaying,
                       isPlaying: isPlaying,
                       continuousWhilePressed: continuousWhilePressed,
                       onPage: onPage)
            .frame(width: 0, height: 0)
            .hidden()
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
private struct VolumeKeyProxy: UIViewRepresentable {
    let isEnabled: Bool
    let ignoreWhilePlaying: Bool
    let isPlaying: Bool
    let continuousWhilePressed: Bool
    let onPage: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MPVolumeView {
        // Off-screen but with real size: a zero-frame MPVolumeView never creates its slider.
        let view = MPVolumeView(frame: CGRect(x: -4_000, y: -4_000, width: 320, height: 24))
        view.alpha = 0.01

        for subview in view.subviews {
            // Touches must fall through to the reader underneath.
            subview.isUserInteractionEnabled = false
            guard let slider = subview as? UISlider else { continue }
            slider.minimumTrackTintColor = .clear
            slider.maximumTrackTintColor = .clear
            context.coordinator.slider = slider
            context.coordinator.lastVolume = slider.value
            slider.addTarget(context.coordinator,
                             action: #selector(Coordinator.valueChanged(_:)),
                             for: .valueChanged)
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.ignoreWhilePlaying = ignoreWhilePlaying
        context.coordinator.isPlaying = isPlaying
        context.coordinator.continuousWhilePressed = continuousWhilePressed
        context.coordinator.onPage = onPage
    }

    final class Coordinator: NSObject {
        var isEnabled = true
        var ignoreWhilePlaying = false
        var isPlaying = false
        var continuousWhilePressed = false
        var onPage: ((Bool) -> Void)?

        weak var slider: UISlider?
        var lastVolume: Float = -1
        private var isRestoring = false
        private var lastFire = Date.distantPast

        @objc func valueChanged(_ sender: UISlider) {
            let value = sender.value
            guard !isRestoring else { return }
            guard lastVolume >= 0, abs(value - lastVolume) > 0.0001 else {
                lastVolume = value
                return
            }
            let forward = value < lastVolume

            isRestoring = true
            sender.value = lastVolume
            isRestoring = false

            fire(forward: forward)
        }

        private func fire(forward: Bool) {
            guard isEnabled else { return }
            if ignoreWhilePlaying && isPlaying { return }
            // 600 ms leading-edge debounce unless the user asked for continuous paging.
            if !continuousWhilePressed, Date().timeIntervalSince(lastFire) < 0.6 { return }
            lastFire = Date()
            onPage?(forward)
        }
    }
}
#endif

import SwiftUI
import AVFoundation
#if canImport(LegadoCore)
import LegadoCore
#endif
#if os(iOS)
import MediaPlayer
#endif

/// 网络音频书播放页 (Android AudioPlayActivity Counterpart)
/// 针对 bookSourceType == 1 (音频书源) 的真实流媒体章节播放页。
public struct AudioPlayView: View {
    let book: Book
    let source: BookSource?
    let chapters: [BookChapter]
    let initialChapterIndex: Int
    var onDismiss: (() -> Void)? = nil

    @ObservedObject var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentChapterIndex: Int
    @State private var isPlaying: Bool = false
    @State private var isLoadingAudio: Bool = false
    @State private var currentTime: Double = 0
    @State private var totalDuration: Double = 0
    @State private var audioPlayer: AVPlayer?
    @State private var timeObserver: Any?
    @State private var audioUrlString: String = ""
    @State private var errorMessage: String? = nil
    @State private var showTOCSheet: Bool = false
    @State private var playbackRate: Float = 1.0
    @State private var timerMinutes: Int = 0
    @State private var timerRemainingSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?

    private static let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    public init(book: Book, source: BookSource?, initialChapterIndex: Int = 0, onDismiss: (() -> Void)? = nil) {
        self.book = book
        self.source = source
        self.chapters = BookStore.shared.getChapters(for: book.bookUrl)
        self.initialChapterIndex = initialChapterIndex
        self._currentChapterIndex = State(initialValue: initialChapterIndex)
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Blurred album art background
            backgroundCoverArt

            VStack(spacing: 24) {
                topNavigationBar

                Spacer()

                // Center spinning/glowing vinyl-style cover
                centerVinylCover

                Spacer()

                // Chapter & track titles
                chapterTitleSection

                // Progress slider
                progressSliderSection

                // Playback main transport controls
                transportControlsSection

                // Bottom feature chips (TOC, Timer, Speed)
                bottomControlsRow

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            setupAudioSession()
            loadCurrentChapterAudio()
        }
        .onDisappear {
            stopPlayback()
        }
        .sheet(isPresented: $showTOCSheet) {
            NavigationView {
                ChapterListView(
                    bookUrl: book.bookUrl,
                    chapters: chapters,
                    currentChapterIndex: currentChapterIndex,
                    showCloseButton: true,
                    onSelectChapter: { idx in
                        showTOCSheet = false
                        jumpToChapter(idx)
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var backgroundCoverArt: some View {
        if let coverUrlStr = book.displayCoverURL, let url = URL(string: coverUrlStr) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .blur(radius: 40)
                        .overlay(Color.black.opacity(0.6))
                } else {
                    Color.black.opacity(0.85).ignoresSafeArea()
                }
            }
        } else {
            LinearGradient(
                colors: [Color.purple.opacity(0.4), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var topNavigationBar: some View {
        HStack {
            Button(action: {
                stopPlayback()
                onDismiss?() ?? dismiss()
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(book.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(book.author.isEmpty ? "有声小说" : book.author)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { showTOCSheet = true }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.top, 12)
    }

    private var centerVinylCover: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 240, height: 240)
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 2))

            if let coverUrlStr = book.displayCoverURL, let url = URL(string: coverUrlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())
                    } else {
                        vinylPlaceholder
                    }
                }
            } else {
                vinylPlaceholder
            }

            if isLoadingAudio {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 200, height: 200)
                    .overlay(ProgressView().scaleEffect(1.4).tint(.white))
            }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
    }

    private var vinylPlaceholder: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 200, height: 200)
            .overlay(
                Image(systemName: "headphones")
                    .font(.system(size: 56))
                    .foregroundColor(.white.opacity(0.8))
            )
    }

    private var chapterTitleSection: some View {
        VStack(spacing: 6) {
            let currentTitle = currentChapterIndex < chapters.count ? chapters[currentChapterIndex].title : "准备播放"
            Text(currentTitle)
                .font(.headline.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else {
                Text("来源：\(source?.bookSourceName ?? book.originName)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var progressSliderSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { seekTo(seconds: $0) }
                ),
                in: 0...max(totalDuration, 1)
            )
            .accentColor(.white)

            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(formatTime(totalDuration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var transportControlsSection: some View {
        HStack(spacing: 32) {
            Button(action: { skipChapter(by: -1) }) {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundColor(currentChapterIndex > 0 ? .white : .white.opacity(0.3))
            }
            .disabled(currentChapterIndex <= 0)

            Button(action: { seekBy(seconds: -15) }) {
                Image(systemName: "gobackward.15")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
            }

            Button(action: { seekBy(seconds: 15) }) {
                Image(systemName: "goforward.15")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            Button(action: { skipChapter(by: 1) }) {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundColor(currentChapterIndex < chapters.count - 1 ? .white : .white.opacity(0.3))
            }
            .disabled(currentChapterIndex >= chapters.count - 1)
        }
    }

    private var bottomControlsRow: some View {
        HStack(spacing: 20) {
            // Speed menu
            Menu {
                ForEach(Self.playbackRates, id: \.self) { rate in
                    Button(String(format: "%.2fx", rate)) {
                        playbackRate = rate
                        if isPlaying { audioPlayer?.rate = rate }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "speedometer")
                    Text(String(format: "%.2fx", playbackRate))
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
            }

            // Sleep Timer Menu
            Menu {
                ForEach([0, 15, 30, 45, 60, 90], id: \.self) { min in
                    Button(min == 0 ? "关闭定时" : "\(min) 分钟") {
                        setTimer(minutes: min)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill")
                    Text(timerMinutes == 0 ? "定时" : "\(timerRemainingSeconds / 60)m")
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Audio Playback Logic

    private func setupAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func loadCurrentChapterAudio() {
        guard currentChapterIndex < chapters.count else { return }
        let ch = chapters[currentChapterIndex]
        isLoadingAudio = true
        errorMessage = nil
        currentTime = 0
        totalDuration = 0

        Task {
            do {
                // If chapter already resolved to audio direct URL
                let directUrlStr: String
                if ch.url.hasPrefix("http") && (ch.url.contains(".mp3") || ch.url.contains(".m4a") || ch.url.contains(".aac") || ch.url.contains(".flac")) {
                    directUrlStr = ch.url
                } else {
                    let content = try await BookContentService.shared.fetchChapterContent(
                        chapter: ch,
                        source: source,
                        nextChapterUrl: nil
                    )
                    directUrlStr = content.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                guard let audioUrl = URL(string: directUrlStr) else {
                    await MainActor.run {
                        self.isLoadingAudio = false
                        self.errorMessage = "解析音频播放地址失败"
                    }
                    return
                }

                await MainActor.run {
                    self.audioUrlString = directUrlStr
                    self.startPlayback(with: audioUrl)
                }
            } catch {
                await MainActor.run {
                    self.isLoadingAudio = false
                    self.errorMessage = "音频获取异常: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startPlayback(with url: URL) {
        removePeriodicTimeObserver()
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.audioPlayer = player

        // Observe total duration
        Task {
            if let duration = try? await playerItem.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if !seconds.isNaN && seconds > 0 {
                    await MainActor.run {
                        self.totalDuration = seconds
                    }
                }
            }
        }

        // Periodic time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let cur = CMTimeGetSeconds(time)
            if !cur.isNaN {
                self.currentTime = cur
            }
        }

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            self.skipChapter(by: 1)
        }

        player.play()
        player.rate = playbackRate
        isPlaying = true
        isLoadingAudio = false
        bookStore.updateProgress(bookUrl: book.bookUrl, chapterIndex: currentChapterIndex, chapterTitle: chapters[currentChapterIndex].title)
    }

    private func togglePlayPause() {
        guard let player = audioPlayer else {
            loadCurrentChapterAudio()
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }

    private func seekTo(seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        audioPlayer?.seek(to: time)
    }

    private func seekBy(seconds: Double) {
        let target = max(0, min(currentTime + seconds, totalDuration))
        seekTo(seconds: target)
    }

    private func skipChapter(by delta: Int) {
        let nextIndex = currentChapterIndex + delta
        guard nextIndex >= 0, nextIndex < chapters.count else {
            stopPlayback()
            return
        }
        currentChapterIndex = nextIndex
        loadCurrentChapterAudio()
    }

    private func jumpToChapter(_ index: Int) {
        guard index >= 0, index < chapters.count else { return }
        currentChapterIndex = index
        loadCurrentChapterAudio()
    }

    private func stopPlayback() {
        audioPlayer?.pause()
        removePeriodicTimeObserver()
        audioPlayer = nil
        isPlaying = false
        timerTask?.cancel()
        timerTask = nil
    }

    private func removePeriodicTimeObserver() {
        if let observer = timeObserver, let player = audioPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func setTimer(minutes: Int) {
        timerTask?.cancel()
        timerMinutes = minutes
        timerRemainingSeconds = minutes * 60
        guard minutes > 0 else { return }

        timerTask = Task { @MainActor in
            while timerRemainingSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                timerRemainingSeconds -= 1
                if timerRemainingSeconds == 0 {
                    stopPlayback()
                    break
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let s = Int(seconds)
        let m = s / 60
        let h = m / 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m % 60, s % 60)
        } else {
            return String(format: "%02d:%02d", m, s % 60)
        }
    }
}

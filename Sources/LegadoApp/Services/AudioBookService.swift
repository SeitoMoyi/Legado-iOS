import Foundation
import AVFoundation
#if canImport(LegadoCore)
import LegadoCore
#endif
#if os(iOS)
import MediaPlayer
#endif

/// Read-aloud engine.
///
/// The unit of speech is the **paragraph**, not the sentence — same as Android's
/// `BaseReadAloudService`, which splits the chapter on newlines. `上一段 / 下一段`, the
/// character offset it reports back for highlighting, and the auto-advance into the next
/// chapter all fall out of that choice.
///
/// Progress is reported as `currentCharPos`, a character offset within the chapter that
/// counts the title line, so it is directly interchangeable with `Book.durChapterPos`,
/// `Bookmark.chapterPos` and the WebDAV progress files.
public final class AudioBookService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = AudioBookService()

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVPlayer?

    @Published public private(set) var paragraphs: [String] = []
    @Published public private(set) var currentIndex: Int = 0
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var isPaused: Bool = false
    /// Selected engine name (defaults to System)
    @Published public var selectedEngineName: String = "系统原生 TTS (本地离线)"
    /// Chapter-relative character offset of the paragraph being spoken.
    @Published public private(set) var currentCharPos: Int = 0
    @Published public private(set) var currentParagraph: String = ""
    /// a change restarts the current paragraph — and the panel writes all three values on
    /// appear, which without these guards would restart speech three times over.
    @Published public var speechRatePref: Int = 5 { didSet { if oldValue != speechRatePref { respeakCurrentParagraph() } } }
    /// Android's `ttsFollowSys` — hand rate control back to the system voice.
    @Published public var followSystemRate: Bool = true { didSet { if oldValue != followSystemRate { respeakCurrentParagraph() } } }
    @Published public var pitch: Double = 1.0 { didSet { if oldValue != pitch { respeakCurrentParagraph() } } }

    /// Android's `ttsTimer`, in minutes. 0 means no timer. Re-arming on an unchanged value
    /// would restart the countdown every time the panel is opened.
    @Published public var timerMinutes: Int = 0 { didSet { if oldValue != timerMinutes { startTimerIfNeeded() } } }
    @Published public private(set) var timerRemaining: Int = 0

    /// Asked to move ±1 chapter when speech runs off either end of the paragraph list.
    public var onRequestChapter: ((Int) -> Void)?

    /// Lock-screen title / subtitle. Set by the reader; only consumed on iOS.
    public var nowPlayingTitle: String = ""
    public var nowPlayingSubtitle: String = ""

    private var timerTask: Task<Void, Never>?
    private var pauseVerifyTask: Task<Void, Never>?
    private var language = "zh-CN"
    /// Chapter offset where the current paragraph starts; `willSpeakRange` reports positions
    /// relative to the utterance, so the highlight needs this base added once, not repeatedly.
    private var paragraphStartOffset = 0

    /// Android's `AppPattern.notReadAloudRegex`: nothing worth speaking in a line made only
    /// of whitespace, punctuation or symbols.

    public override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        #if os(iOS)
        registerRemoteCommands()
        #endif
    }

    /// True while speech has run off either end of the paragraph list and the reader is
    /// fetching the neighbouring chapter. Without it `state` dips to `.stopped` for the whole
    /// fetch, which makes the floating control bar blink out mid-reading.
    @Published public private(set) var isSwitchingChapter: Bool = false

    public var isActive: Bool { state != .stopped || isSwitchingChapter }

    // MARK: - Loading

    /// Chapter text currently split into `paragraphs` — lets the reader detect that the user
    /// changed chapters while paused (resume must not replay the old chapter's queue).
    public private(set) var loadedChapterText: String = ""

    /// Loads a chapter's text and starts at `startCharPos` (or from the top when 0).
    public func load(chapterText: String, startCharPos: Int = 0, language: String = "zh-CN") {
        isSwitchingChapter = false
        self.language = language
        loadedChapterText = chapterText
        let lines = ReadAloudText.paragraphs(in: chapterText)
        paragraphs = lines
        guard !lines.isEmpty else {
            stop()
            return
        }
        speakParagraph(at: ReadAloudText.paragraphIndex(containing: startCharPos, in: lines))
    }

    /// Paragraph index containing a ReadAloudText-basis char offset; nil when nothing is
    /// loaded. The reader uses it to decide 翻页后 resume-vs-re-anchor.
    public func paragraphIndex(containingCharPos pos: Int) -> Int? {
        guard !paragraphs.isEmpty else { return nil }
        return ReadAloudText.paragraphIndex(containing: pos, in: paragraphs)
    }

    // MARK: - Speaking a paragraph

    public func speakParagraph(at index: Int) {
        guard index >= 0, index < paragraphs.count else {
            if index >= paragraphs.count { advanceChapter(by: 1) } else { stop() }
            return
        }
        stopSpeakingOnly()
        pauseVerifyTask?.cancel()
        pauseVerifyTask = nil

        currentIndex = index
        currentParagraph = paragraphs[index]
        paragraphStartOffset = ReadAloudText.offset(of: paragraphs, at: index)
        currentCharPos = paragraphStartOffset

        let activeEngine = HttpTTSStore.load().first { $0.name == selectedEngineName && $0.enabled }

        if let engine = activeEngine, !engine.url.isEmpty {
            speakWithHttpTTS(engine: engine, text: currentParagraph)
        } else {
            speakWithSystemTTS(text: currentParagraph)
        }
    }

    private func speakWithSystemTTS(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = effectiveRate
        utterance.pitchMultiplier = Float(pitch)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        synthesizer.speak(utterance)

        state = .speaking
        #if os(iOS)
        updateNowPlaying(elapsed: 0)
        #endif
    }

    private func speakWithHttpTTS(engine: HttpTTS, text: String) {
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let renderedUrl = engine.url.replacingOccurrences(of: "{{speakText}}", with: encodedText)
        guard let parsed = NetworkClient.parseLegadoUrl(renderedUrl, defaultHeader: engine.header) else {
            speakWithSystemTTS(text: text)
            return
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let playerItem = AVPlayerItem(url: parsed.url)
        audioPlayer = AVPlayer(playerItem: playerItem)

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            guard let self = self, self.state == .speaking else { return }
            self.step(to: self.currentIndex + 1)
        }

        audioPlayer?.play()
        state = .speaking
        #if os(iOS)
        updateNowPlaying(elapsed: 0)
        #endif
    }
    /// Rate in `AVSpeechUtterance` terms. Android computes `(pref + 5) / 10`, and the value
    /// is clamped because 45 would otherwise ask for 5x on a system that tops out lower.
    public var effectiveRate: Float {
        if followSystemRate { return AVSpeechUtteranceDefaultSpeechRate }
        let requested = Float(speechRatePref + 5) / 10.0
        return min(max(requested, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    // MARK: - Transport
    //
    // `state` is the single source of truth and is written synchronously; `isPlaying` /
    // `isPaused` are its published mirror. Doing it this way is the fix for 「点暂停没反应」:
    // the previous version only flipped the flags inside `didPause`, and that callback is not
    // guaranteed to arrive — a `pauseSpeaking` request that lands between two utterances is
    // dropped silently. The button then stayed on 「暂停」, the next tap went to `play()`,
    // and `speakParagraph` restarted the same paragraph forever.

    public enum State { case stopped, speaking, paused }

    public private(set) var state: State = .stopped {
        didSet {
            isPlaying = (state == .speaking)
            isPaused = (state == .paused)
        }
    }

    public func play() {
        if state == .paused {
            resume()
            return
        }
        guard !paragraphs.isEmpty else { return }
        speakParagraph(at: min(currentIndex, max(0, paragraphs.count - 1)))
    }

    public func pause() {
        guard state == .speaking else { return }
        if let player = audioPlayer {
            player.pause()
        } else if synthesizer.isSpeaking && !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .word)
        } else {
            if synthesizer.isPaused { synthesizer.continueSpeaking() }
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        }
        state = .paused
        verifyPauseLands()
    }
    /// `pauseSpeaking` is not guaranteed to take: a request that lands between two utterances
    /// is dropped, and if it is dropped the user hears audio with the UI claiming 「已暂停」 —
    /// which reads as a dead button. Short-circuit that by hard-stopping if the engine is still
    /// speaking a moment later.
    private func verifyPauseLands() {
        pauseVerifyTask?.cancel()
        pauseVerifyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled, self.state == .paused else { return }
            if self.synthesizer.isSpeaking && !self.synthesizer.isPaused {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    public func resume() {
        guard state == .paused else { return }
        pauseVerifyTask?.cancel()
        pauseVerifyTask = nil
        if let player = audioPlayer {
            player.play()
            state = .speaking
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            state = .speaking
        } else {
            speakParagraph(at: currentIndex)
        }
    }
    public func togglePlayPause() {
        switch state {
        case .speaking: pause()
        case .paused:   resume()
        case .stopped:  play()
        }
    }

    public func stop() {
        stopTimer()
        isSwitchingChapter = false
        stopSpeakingOnly()
        paragraphs = []
        currentParagraph = ""
        loadedChapterText = ""
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    private func stopSpeakingOnly() {
        pauseVerifyTask?.cancel()
        pauseVerifyTask = nil
        if let player = audioPlayer {
            player.pause()
            audioPlayer = nil
        }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .stopped
    }
    // MARK: - Stepping

    public func nextParagraph() {
        step(to: currentIndex + 1)
    }

    public func prevParagraph() {
        step(to: currentIndex - 1)
    }

    private func step(to index: Int) {
        guard !paragraphs.isEmpty else { return }
        if index >= paragraphs.count {
            advanceChapter(by: 1)
            return
        }
        if index < 0 {
            advanceChapter(by: -1)
            return
        }
        let forward = index >= currentIndex
        guard let target = ReadAloudText.nextSpeakableIndex(paragraphs, from: index, forward: forward) else {
            advanceChapter(by: forward ? 1 : -1)
            return
        }
        speakParagraph(at: target)
    }

    private func advanceChapter(by delta: Int) {
        stopTimer()
        stopSpeakingOnly()
        // Nobody will resume speech if the reader is not listening, so do not claim a
        // handoff is in flight — the bar would stay up forever.
        guard let onRequestChapter else { return }
        isSwitchingChapter = true
        onRequestChapter(delta)
    }

    private func respeakCurrentParagraph() {
        guard state == .speaking, !currentParagraph.isEmpty else { return }
        speakParagraph(at: currentIndex)
    }

    // MARK: - Sleep timer

    /// Ticks once a minute and only counts down while actually speaking, as Android does.
    /// The task runs on the main actor because it reads and writes `@Published` state; the
    /// class itself is not `@MainActor`, so a bare `await` here would be a no-op.
    private func startTimerIfNeeded() {
        stopTimer()
        guard timerMinutes > 0 else { timerRemaining = 0; return }
        timerRemaining = timerMinutes
        let minutes = timerMinutes
        timerTask = Task { @MainActor [weak self] in
            for _ in 0..<minutes {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.isPlaying else { continue }
                self.timerRemaining = max(0, self.timerRemaining - 1)
                if self.timerRemaining == 0 {
                    self.stop()
                    return
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }


    // MARK: - Session

    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioBookService] Failed to activate audio session: \(error)")
        }
        #endif
    }

    // MARK: - Delegate

    // The delegate only ever *aligns* `state`; it never decides it, so a callback that lands
    // after `pause()` or `stop()` cannot resurrect speech or skip a paragraph.

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.state == .speaking else { return }
            self.step(to: self.currentIndex + 1)
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if self.state == .speaking { self.state = .paused }
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if self.state == .paused { self.state = .speaking }
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let absolute = paragraphStartOffset + characterRange.location
        DispatchQueue.main.async {
            guard self.state == .speaking else { return }
            self.currentCharPos = absolute
        }
        #if os(iOS)
        updateNowPlaying(elapsed: Double(characterRange.location))
        #endif
    }

    #if os(iOS)
    // MARK: - Lock screen / headphones

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextParagraph()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.prevParagraph()
            return .success
        }
    }

    private func updateNowPlaying(elapsed: Double) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = nowPlayingTitle
        info[MPMediaItemPropertyArtist] = nowPlayingSubtitle.isEmpty ? currentParagraph : nowPlayingSubtitle
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(effectiveRate / AVSpeechUtteranceDefaultSpeechRate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    #endif
}

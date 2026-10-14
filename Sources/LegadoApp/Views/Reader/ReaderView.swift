import SwiftUI
import CoreText
#if canImport(LegadoCore)
import LegadoCore
#endif

public struct ContentBlock: Identifiable {
    public let id: Int
    public let isImage: Bool
    public let text: String
    public let imageUrl: String?
}

public struct LoadedChapter: Identifiable {
    public var id: Int { chapter.index }
    public let chapter: BookChapter
    public var content: String
    public var typography: ChapterTypography? = nil
    public var blocks: [ContentBlock] = []
    public var pages: [[ContentBlock]] = []
}

public struct BlockFrameInfo: Equatable {
    public let chapterIndex: Int
    public let blockId: Int
    public let minY: CGFloat
    public let maxY: CGFloat
}

public struct ReaderScrollPreferenceKey: PreferenceKey {
    public static var defaultValue: [BlockFrameInfo] = []
    public static func reduce(value: inout [BlockFrameInfo], nextValue: () -> [BlockFrameInfo]) {
        value.append(contentsOf: nextValue())
    }
}

public struct ScrollOffsetPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// `.kerning` needs iOS 16 / macOS 13 while this project still deploys to iOS 15 and
    /// macOS 12, so it is applied behind a runtime check. Paged text is kerned through
    /// CoreText instead, which has no such constraint.
    @ViewBuilder
    func kerningWhenAvailable(_ value: CGFloat) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            self.kerning(value)
        } else {
            self
        }
    }
}

/// Which panel the reader shows over the canvas. Android opens these as separate dialogs;
/// one enum keeps them mutually exclusive instead of letting two overlays stack.
enum ReaderPanel: Equatable {
    case none
    case style
    case moreSettings
    case aloud
}

public struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var readerConfig = ReaderConfig.shared
    @StateObject private var audioService = AudioBookService.shared

    /// Mutable so 换源 can rewrite the shelf entry it is displaying.
    @State private var book: Book
    /// Nil means "resolve from the shelf", which is what `effectiveSource` does.
    @State private var currentSource: BookSource?

    private var effectiveSource: BookSource? {
        currentSource ?? BookStore.shared.findSource(for: book)
    }

    @State private var chapters: [BookChapter] = []
    @State private var currentChapterIndex: Int = 0
    @State private var loadedChapters: [LoadedChapter] = []
    @State private var currentPageIndex: Int = 0
    @State private var currentReadingBlockId: Int = 0
    /// Which side the incoming page enters from; `cover` and `slide` differ only here.
    @State private var pageEdge: Edge = .trailing
    @State private var chapterCache: [Int: LoadedChapter] = [:]
    @State private var readerContainerSize: CGSize = CGSize(width: 390, height: 700)

    @State private var isLoadingInitial: Bool = true
    @State private var scrollSessionId: UUID = UUID()
    @State private var scrollToChapterId: String? = nil
    @State private var scrollTargetCharPos: Int? = nil
    @State private var scrollReadingCharOffset: Int = 0
    @State private var errorMessage: String? = nil
    /// Next step the user can actually take, shown under the failure text. The failure page
    /// used to state the error and offer a dead 重试 button, which read as an inescapable screen.
    @State private var errorGuidance: String? = nil
    /// Re-applies the 屏幕常亮 timeout without leaking the previous one.
    @State private var idleTimerTask: Task<Void, Never>? = nil

    @State private var showTOC: Bool = false
    @State private var showSearch: Bool = false
    @State private var showEffectiveReplaces: Bool = false
    @State private var showBookmarks: Bool = false
    @State private var changeSourceMode: ChangeSourceSheet.Mode? = nil
    @State private var loginSource: BookSource?
    /// Guards against 自动换源 recursing when the replacement also fails.
    @State private var isAutoChangingSource: Bool = false
    @State private var showRangeDownload: Bool = false
    @State private var showEditContentSheet: Bool = false
    @State private var editingBookmark: Bookmark?
    @State private var bookmarkIsNew: Bool = true
    @State private var panel: ReaderPanel = .none
    @State private var showControls: Bool = false
    /// One-line explanation shown above the bottom bar after a control that has no visible
    /// effect of its own (净化 is the case that prompted this: a bare toggle labelled with
    /// Android's internal term).
    @State private var controlHint: String? = nil
    @State private var controlHintTask: Task<Void, Never>? = nil
    /// True while the reader keeps speaking after the view goes away ("后台").
    @State private var keepAloudInBackground: Bool = false
    @State private var readingSessionStartTime: Date? = nil

    // Auto Page Turn State
    @State private var isAutoPageTurning: Bool = false
    @State private var autoTurnIntervalSeconds: Double = 5.0
    @State private var autoTurnTask: Task<Void, Never>? = nil

    // Text Selection & Dict Popup State
    @State private var selectedWordForDict: String? = nil

    public var onDismiss: (() -> Void)? = nil

    public init(book: Book, source: BookSource?, initialChapterIndex: Int? = nil, onDismiss: (() -> Void)? = nil) {
        _book = State(initialValue: book)
        _currentSource = State(initialValue: source)
        self._currentChapterIndex = State(initialValue: initialChapterIndex ?? book.durChapterIndex)
        self.onDismiss = onDismiss
    }

    private var currentLoadedChapter: LoadedChapter? {
        loadedChapters.first(where: { $0.chapter.index == currentChapterIndex }) ?? loadedChapters.first
    }

    /// Whether the canvas can still show a chapter body. `currentChapterIndex` only advances on
    /// success, so a failed load leaves the previous chapter intact.
    private var hasReadableContent: Bool {
        loadedChapters.contains {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var currentChapterContent: String {
        currentLoadedChapter?.content ?? ""
    }

    /// Same key `BookContentService.finalize` uses, so the sheet reads back this chapter.
    private var currentChapterCacheKey: String {
        guard currentChapterIndex < chapters.count else { return "" }
        return "\(chapters[currentChapterIndex].bookUrl)|\(currentChapterIndex)"
    }

    private var effectiveRulesForCurrentChapter: [ReplaceRule] {
        ContentProcessor.shared.result(forKey: currentChapterCacheKey)?.effectiveRules ?? []
    }

    // MARK: - Panel and control state

    private func openPanel(_ next: ReaderPanel) {
        withAnimation(.easeInOut(duration: 0.22)) {
            panel = next
            showControls = true
        }
    }

    private func closePanel() {
        withAnimation(.easeInOut(duration: 0.22)) {
            panel = .none
        }
    }

    /// The action bound to the middle of the tap map; scroll mode routes every tap here.
    private var scrollTapAction: ClickActionCode {
        readerConfig.clickActionList[4]
    }

    private func setConverter(_ mode: Int) {
        var prefs = readerConfig.prefs
        prefs.chineseConverterType = mode
        readerConfig.prefs = prefs
        reloadCurrentChapter()
    }

    /// Drops the in-memory chapter so it is re-read from the (unprocessed) disk cache, which
    /// re-runs the 净化 pipeline with whatever just changed.
    private func reloadCurrentChapter() {
        chapterCache[currentChapterIndex] = nil
        if readerConfig.pageMode == .scroll {
            loadedChapters.removeAll { $0.chapter.index == currentChapterIndex }
        }
        loadInitialChapter(at: currentChapterIndex)
    }

    private func clearBookCache() {
        BookContentService.shared.clearCache(for: book.bookUrl)
        chapterCache.removeAll()
        loadedChapters.removeAll()
        reloadCurrentChapter()
    }

    private func setControls(_ open: Bool) {
        withAnimation(.easeInOut(duration: 0.22)) {
            showControls = open
            if !open { panel = .none }
        }
    }

    private func toggleControls() {
        if panel != .none {
            closePanel()
        } else {
            setControls(!showControls)
        }
    }

    /// Applies the 屏幕常亮 preference. Anything other than 常亮 hands the idle timer back
    /// to the system once the timeout elapses — iOS offers no way to force the display off.
    private func applyIdleTimerPreference() {
        #if os(iOS)
        let keepLight = readerConfig.prefs.keepLight
        UIApplication.shared.isIdleTimerDisabled = (keepLight == -1)
        idleTimerTask?.cancel()
        if keepLight > 0 {
            idleTimerTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(keepLight) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
            }
        }
        #endif
    }

    private func restoreIdleTimer() {
        idleTimerTask?.cancel()
        idleTimerTask = nil
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    /// Single dispatch point for the nine tap zones, so paged and scrolling modes agree.
    private func handleTapAction(_ action: ClickActionCode) {
        switch action {
        case .menu: toggleControls()
        case .nextPage, .prevPage:
            // Continuous scroll is one long document with no page index, so paging by tap
            // has no target there; the paged renderer owns these two actions.
            guard readerConfig.pageMode == .pageByPage else { return }
            turnPage(forward: action == .nextPage)
        case .nextChapter: jumpChapter(by: 1)
        case .prevChapter: jumpChapter(by: -1)
        case .openToc: showTOC = true
        case .openSearch: showSearch = true
        case .toggleReplaceRule: toggleReplaceRule()
        case .aloudToggle: toggleAloud()
        case .addBookmark: addBookmark()
        case .aloudPrevParagraph: audioService.prevParagraph()
        case .aloudNextParagraph: audioService.nextParagraph()
        case .editContent:
            showEditContentSheet = true
        case .syncProgress:
            performProgressSync()
        }
    }

    private func jumpChapter(by delta: Int) {
        if delta > 0 {
            nextChapter()
        } else if delta < 0 {
            previousChapter()
        }
    }

    /// Toggles 净化 for this book only. The cache deliberately stores unprocessed text, so
    /// this takes effect on the next read without clearing anything.
    private func toggleReplaceRule() {
        let current = book.useReplaceRule ?? readerConfig.prefs.replaceEnableDefault
        setReplaceRule(enabled: !current)
    }

    private func setReplaceRule(enabled: Bool) {
        guard let index = BookStore.shared.bookshelf.firstIndex(where: { $0.bookUrl == book.bookUrl }) else { return }
        BookStore.shared.bookshelf[index].useReplaceRule = enabled
        BookStore.shared.saveBookshelf()
        book.useReplaceRule = enabled
        chapterCache[currentChapterIndex] = nil
        loadInitialChapter(at: currentChapterIndex)
        showControlHint(replaceHintText(enabled: enabled))
    }

    /// 「净化」 is Android's label for "apply the 替换规则 list". It means nothing on its own, so
    /// the tap answers in prose — including the case where the user has no rules at all, which
    /// otherwise looks like a dead button.
    private func replaceHintText(enabled: Bool) -> String {
        guard enabled else { return "净化已关闭 · 正文按书源原样显示" }
        let rules = BookStore.shared.matchingReplaceRules(bookName: book.name, bookOrigin: book.origin)
                        .filter { $0.isEnabled }
        if rules.isEmpty {
            return "净化已开启 · 但当前没有匹配的替换规则，长按本按钮查看"
        }
        return "净化已开启 · \(rules.count) 条规则将清理正文中的广告与乱码"
    }

    /// Caption above the bottom bar; iOS has no Toast, and `showControlHint` auto-dismisses it.
    private func hintBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(readerConfig.theme.textColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(readerConfig.theme.textColor.opacity(0.08)))
            .padding(.bottom, 8)
            .transition(.opacity)
    }

    private func showControlHint(_ text: String) {
        controlHintTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) { controlHint = text }
        controlHintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { controlHint = nil }
        }
    }

    public var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                readerConfig.theme.backgroundColor
                    .ignoresSafeArea()

                // 1. Reading Canvas with Permanent Fixed Bottom Info Bar
                readingCanvas

                aloudFloatingLayer
                autoTurnFloatingLayer
                controlsLayer
                panelLayer(maxHeight: outerGeo.size.height)
            }
            .onAppear {
                let readingHeight = max(200, outerGeo.size.height - 26)
                updateContainerSizeIfNeeded(CGSize(width: outerGeo.size.width, height: readingHeight))
                applyIdleTimerPreference()
                wireAudioService()
                readingSessionStartTime = Date()
            }
            .onDisappear {
                if let start = readingSessionStartTime {
                    let elapsedMs = Int64(Date().timeIntervalSince(start) * 1000)
                    if elapsedMs > 2000 {
                        ReadRecordStore.addDuration(bookName: book.name, durationMs: elapsedMs)
                    }
                    readingSessionStartTime = nil
                }
                stopAutoPageTurn()
            }
            .onChange(of: outerGeo.size) { newSize in
                let readingHeight = max(200, newSize.height - 26)
                updateContainerSizeIfNeeded(CGSize(width: newSize.width, height: readingHeight))
            }
            .onChange(of: readerConfig.prefs.keepLight) { _ in
                applyIdleTimerPreference()
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        .statusBar(hidden: false)
        .preferredColorScheme(readerConfig.theme == .dark ? .dark : .light)
        #endif
        .sheet(isPresented: $showTOC) {
            tocSheet
        }
        .sheet(isPresented: $showSearch) {
            searchSheet
        }
        .sheet(isPresented: $showEffectiveReplaces) {
            EffectiveReplacesSheet(book: book,
                                   cacheKey: currentChapterCacheKey,
                                   enabled: book.useReplaceRule ?? readerConfig.prefs.replaceEnableDefault,
                                   onSetEnabled: { setReplaceRule(enabled: $0) })
        }
        .sheet(item: $loginSource) { source in
            SourceLoginSheet(source: source)
        }
        .sheet(item: $changeSourceMode) { mode in
            ChangeSourceSheet(book: book, mode: mode,
                              chapterTitle: currentChapterIndex < chapters.count
                              ? chapters[currentChapterIndex].title : "",
                              onApply: { candidate, toc in applySourceChange(candidate, toc) },
                              onApplyChapterText: { text in applyChapterText(text) })
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkSheet(book: book) { bookmark in
                jumpToBookmark(bookmark)
            }
        }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditorSheet(bookmark: bookmark, isNew: bookmarkIsNew) { saved in
                if bookmarkIsNew {
                    BookStore.shared.addBookmark(saved)
                } else {
                    BookStore.shared.updateBookmark(saved)
                }
            } onDelete: { removed in
                BookStore.shared.deleteBookmark(time: removed.time)
            }
        }
        .sheet(isPresented: $showRangeDownload) {
            ChapterRangeDownloadSheet(
                book: book,
                chapters: chapters,
                source: effectiveSource,
                currentChapterIndex: currentChapterIndex
            )
        }
        .sheet(isPresented: $showEditContentSheet) {
            if currentChapterIndex < chapters.count {
                EditContentSheet(
                    title: chapters[currentChapterIndex].title,
                    content: currentChapterContent,
                    onSave: { newTitle, newContent in
                        saveEditedChapter(newTitle: newTitle, newContent: newContent)
                    },
                    onReset: {
                        resetEditedChapter()
                    }
                )
            }
        }
        .sheet(item: $selectedWordForDict) { word in
            NavigationView {
                DictResultPopupView(word: word)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { selectedWordForDict = nil }
                        }
                    }
            }
        }
        .task {
            await loadTOCAndStart()
        }
        .onDisappear {
            saveCurrentProgress()
            if !keepAloudInBackground {
                audioService.stop()
            }
            restoreIdleTimer()
        }
        .onChange(of: readerConfig.pageAnim) { _ in
            handlePageModeChange(to: readerConfig.pageMode)
        }
    }



    // MARK: - Body layers
    //
    // The reader used to be one huge ZStack; the type checker eventually gave up on it.
    // Each layer is now its own view, which also makes the panel stack easier to read.

    private var readingCanvas: some View {
        VStack(spacing: 0) {
            Group {
                if isLoadingInitial {
                    loadingPlaceholder
                } else if let error = errorMessage {
                    loadFailureView(error)
                } else {
                    ZStack {
                        if readerConfig.pageMode == .scroll {
                            infiniteScrollView
                        } else {
                            pageByPageView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Fixed Bottom Information Bar (Apple Books Style)
            fixedBottomStatusBar
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("正在加载章节内容...")
                .font(.subheadline)
                .foregroundColor(readerConfig.theme.textColor.opacity(0.7))
            Spacer()
        }
    }

    private func loadFailureView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("加载失败")
                .font(.headline)
                .foregroundColor(readerConfig.theme.textColor)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let guidance = errorGuidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundColor(readerConfig.theme.textColor.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            HStack(spacing: 12) {
                // Retrying has to restart from the TOC: the previous target,
                // `loadInitialChapter`, begins with `guard !chapters.isEmpty` and so silently
                // did nothing whenever the目录 was what failed.
                Button("重试") { Task { await loadTOCAndStart() } }
                    .buttonStyle(.borderedProminent)
                Button("返回书架", action: exitReader)
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This view replaces the whole canvas, and with it the 3×3 tap zones and the swipe
        // gesture that raise the menu. Without its own gesture there is no way to reach 退出.
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
    }

    /// Floating 播放 / 暂停 / 结束 controls while speech is running.
    ///
    /// Bound to the audio state, not to `showControls`: stopping or resuming playback has to
    /// stay reachable after the menu collapses, which is the whole reason this exists next to
    /// the 朗读面板.
    @ViewBuilder private var aloudFloatingLayer: some View {
        if audioService.isActive {
            VStack(spacing: 0) {
                Spacer()
                ReadAloudFloatingBar(audio: audioService, config: readerConfig)
                    .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder private var autoTurnFloatingLayer: some View {
        if isAutoPageTurning {
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                        .foregroundColor(.accentColor)
                    Text("自动翻页 (\(Int(autoTurnIntervalSeconds))s)")
                        .font(.caption.bold())
                        .foregroundColor(readerConfig.theme.textColor)

                    Button("-1s") {
                        autoTurnIntervalSeconds = max(2.0, autoTurnIntervalSeconds - 1.0)
                        restartAutoTurnTimer()
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(readerConfig.theme.textColor.opacity(0.1))
                    .cornerRadius(4)

                    Button("+1s") {
                        autoTurnIntervalSeconds = min(30.0, autoTurnIntervalSeconds + 1.0)
                        restartAutoTurnTimer()
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(readerConfig.theme.textColor.opacity(0.1))
                    .cornerRadius(4)

                    Button {
                        stopAutoPageTurn()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(readerConfig.theme.backgroundColor)
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                )
                .padding(.bottom, 32)
            }
        }
    }

    /// Top bar + bottom bar + the backdrop that dismisses them.
    @ViewBuilder private var controlsLayer: some View {
        if showControls && panel == .none {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { setControls(false) }
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topNavigationBar
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))

            VStack(spacing: 0) {
                Spacer()
                if let hint = controlHint { hintBubble(hint) }
                bottomControlPanel
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Only one panel is ever open; the enum makes that structural.
    @ViewBuilder private func panelLayer(maxHeight: CGFloat) -> some View {
        if panel != .none {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { closePanel() }
                .ignoresSafeArea()
        }

        if panel == .style {
            bottomAnchored(maxHeight: maxHeight * ReaderPanelMetrics.heightFraction) {
                ReadStylePanel(config: readerConfig,
                               onRepaginate: { recomputePagination() },
                               onClose: { closePanel() },
                               onOpenMore: { openPanel(.moreSettings) })
            }
        }

        if panel == .moreSettings {
            bottomAnchored(maxHeight: maxHeight * ReaderPanelMetrics.heightFraction) {
                MoreSettingsPanel(config: readerConfig,
                                  onClose: { closePanel() },
                                  onChapterRefresh: { reloadCurrentChapter() },
                                  onRepaginate: { recomputePagination() })
            }
        }

        if panel == .aloud {
            bottomAnchored(maxHeight: maxHeight * ReaderPanelMetrics.heightFraction) { aloudOverlayContent }
        }
    }

    /// Pins a panel to the bottom edge and caps how tall it may grow.
    ///
    /// The cap belongs on the *content*, not on the stack: `.frame(maxHeight:)` centres whatever
    /// it wraps, so capping the whole `VStack { Spacer; panel }` left the panel floating around
    /// the middle of the screen instead of sitting on the bottom edge.
    private func bottomAnchored<Content: View>(maxHeight: CGFloat = .infinity,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
                .frame(maxHeight: maxHeight)
                // On the card, not the stack: the stack is full-height, so sliding it would move
                // the panel a whole screen instead of letting it rise from the bottom edge.
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Mode 1: Infinite Scroll Down (连续滚动)
    private var infiniteScrollView: some View {
        ReaderScrollCanvasView(
            loadedChapter: currentLoadedChapter,
            chaptersMeta: chapters,
            currentChapterIndex: currentChapterIndex,
            scrollSessionId: scrollSessionId,
            targetCharPos: scrollTargetCharPos,
            readerConfig: readerConfig,
            aloudParagraph: audioService.currentParagraph,
            aloudIsActive: audioService.isActive,
            onChapterChange: { newIdx, newTitle in
                if self.currentChapterIndex != newIdx {
                    self.currentChapterIndex = newIdx
                    self.preCacheNeighbors(around: newIdx)
                    let pos = self.currentChapterCharOffset()
                    BookStore.shared.updateProgress(
                        bookUrl: self.book.bookUrl,
                        chapterIndex: newIdx,
                        chapterTitle: newTitle,
                        chapterPos: pos
                    )
                }
            },
            onCharOffsetChange: { offset in
                self.scrollReadingCharOffset = offset
            },
            onTapZone: { action in
                self.handleTapAction(action)
            },
            onRequestChapter: { targetIdx in
                await self.getOrFetchChapter(at: targetIdx)
            }
        )
    }


    // MARK: - Mode 2: Page by Page (左右翻页)
    private var pageByPageView: some View {
        GeometryReader { geo in
            let pages = currentLoadedChapter?.pages ?? []

            ZStack {
                if pages.isEmpty || currentPageIndex >= pages.count {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    let pageBlocks = pages[currentPageIndex]
                    let usableWidth = readerConfig.contentSize(for: readerContainerSize).width

                    VStack(alignment: .leading, spacing: 0) {
                        // If it's page 0, display Chapter Title at top
                        if currentPageIndex == 0, let cur = currentLoadedChapter {
                            let titleLines = cur.typography?.titleLines ?? [cur.chapter.title]
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(titleLines.enumerated()), id: \.offset) { _, tLine in
                                    Text(tLine)
                                        .font(.system(size: readerConfig.fontSize + 4, weight: .bold))
                                        .foregroundColor(readerConfig.theme.textColor)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Page Content
                        if pageBlocks.first?.isImage == true, let urlStr = pageBlocks.first?.imageUrl {
                            let isFullImg = readerConfig.prefs.imageStyle == .full
                            ChapterImageView(urlString: urlStr, referer: effectiveSource?.bookSourceUrl)
                                .frame(maxWidth: .infinity, maxHeight: isFullImg ? .infinity : nil)
                        } else {
                            let lines = pageBlocks.map { $0.text }
                            let isParagraphEnd = pageBlocks.map { $0.imageUrl == "p_end" }
                            let effectiveLineHeight = readerConfig.fontSize * 1.25 + readerConfig.lineSpacing
                            let gaps = CGFloat(isParagraphEnd.dropLast().filter { $0 }.count) * readerConfig.paragraphSpacing
                            let pageContentHeight = CGFloat(lines.count) * effectiveLineHeight + gaps

                            CoreTextPageView(
                                lines: lines,
                                isParagraphEnd: isParagraphEnd,
                                fontSize: readerConfig.fontSize,
                                lineSpacing: readerConfig.lineSpacing,
                                textColor: readerConfig.theme.textColor,
                                width: usableWidth,
                                height: pageContentHeight,
                                letterSpacing: readerConfig.letterSpacing,
                                paragraphSpacing: readerConfig.paragraphSpacing,
                                justify: readerConfig.prefs.textFullJustify
                            )
                            .frame(width: usableWidth, height: pageContentHeight, alignment: .topLeading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, readerConfig.paddingLeading)
                    .padding(.trailing, readerConfig.paddingTrailing)
                    .padding(.top, readerConfig.paddingTop)
                    .padding(.bottom, readerConfig.paddingBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id("page_\(currentChapterIndex)_\(currentPageIndex)")
                    .transition(pageTransition)
                }

                // Nine-zone tap map (Android ReadView.setRect9x), plus the swipe gesture.
                TapZoneOverlay(actions: readerConfig.clickActionList) { action in
                    handleTapAction(action)
                }
            }
            .contentShape(Rectangle())
            .onAppear {
                updateContainerSizeIfNeeded(geo.size)
            }
            .onChange(of: geo.size) { newSize in
                updateContainerSizeIfNeeded(newSize)
            }
            .gesture(
                DragGesture(minimumDistance: readerConfig.pageTouchSlop)
                    .onEnded { value in
                        let threshold = readerConfig.pageTurnThreshold
                        if value.translation.width < -threshold {
                            turnPage(forward: true)
                        } else if value.translation.width > threshold {
                            turnPage(forward: false)
                        }
                    }
            )
        }
    }

    private func updateContainerSizeIfNeeded(_ size: CGSize) {
        guard size.width > 100 && size.height > 100 else { return }
        if abs(size.width - readerContainerSize.width) > 6 || abs(size.height - readerContainerSize.height) > 6 {
            DispatchQueue.main.async {
                self.readerContainerSize = size
                self.recomputePagination()
            }
        }
    }

    private func updateReadingBlockIdFromCurrentPage() {
        guard let cur = currentLoadedChapter, !cur.pages.isEmpty else { return }
        var charPos = 0
        let limit = min(currentPageIndex, cur.pages.count)
        for p in 0..<limit {
            for block in cur.pages[p] {
                charPos += block.text.count
            }
        }
        var accumulated = 0
        var targetBlockId = cur.blocks.first?.id ?? 0
        for block in cur.blocks {
            if accumulated + block.text.count > charPos {
                targetBlockId = block.id
                break
            }
            accumulated += block.text.count
            targetBlockId = block.id
        }
        currentReadingBlockId = targetBlockId
    }

    // MARK: - Page Turn Handler (Once chapter ends, next chapter starts next page)
    private func turnPage(forward: Bool) {
        guard let current = currentLoadedChapter else { return }
        let totalPages = current.pages.count

        if forward {
            if currentPageIndex < totalPages - 1 {
                animatePageTurn(forward: true) {
                    currentPageIndex += 1
                }
                updateReadingBlockIdFromCurrentPage()
                saveCurrentProgress()
            } else {
                // Chapter ended! Once one chapter ends, the new chapter starts the next page!
                if currentChapterIndex < chapters.count - 1 {
                    audioService.stop()
                    let nextIdx = currentChapterIndex + 1
                    currentChapterIndex = nextIdx
                    currentPageIndex = 0
                    currentReadingBlockId = 0
                    loadInitialChapter(at: nextIdx, targetPageIndex: 0)
                }
            }
        } else {
            if currentPageIndex > 0 {
                animatePageTurn(forward: false) {
                    currentPageIndex -= 1
                }
                updateReadingBlockIdFromCurrentPage()
                saveCurrentProgress()
            } else {
                // Return to previous chapter's last page!
                if currentChapterIndex > 0 {
                    audioService.stop()
                    let prevIdx = currentChapterIndex - 1
                    currentChapterIndex = prevIdx
                    loadInitialChapter(at: prevIdx, targetPageIndex: -1) // -1 indicates last page
                }
            }
        }
    }

    /// Applies the configured page-turn animation. `simulation` is rendered as `slide`
    /// until the page-curl work lands; `none` skips animation entirely.
    private func animatePageTurn(forward: Bool, _ change: () -> Void) {
        pageEdge = forward ? .trailing : .leading
        switch readerConfig.pageAnim {
        case .none:
            change()
        default:
            withAnimation(.easeInOut(duration: 0.25)) { change() }
        }
    }

    private var pageTransition: AnyTransition {
        let incoming: Edge = pageEdge
        let outgoing: Edge = (incoming == .trailing) ? .leading : .trailing
        switch readerConfig.pageAnim {
        case .none:
            return .identity
        case .cover:
            // New page slides over a stationary old page.
            return .asymmetric(insertion: .move(edge: incoming), removal: .identity)
        case .slide, .simulation:
            return .asymmetric(insertion: .move(edge: incoming), removal: .move(edge: outgoing))
        case .scroll:
            return .opacity
        }
    }

    // MARK: - Navigation Bars & Toolbars (Apple Books Layout)
    private var topNavigationBar: some View {
        HStack(alignment: .center) {
            // Exit button
            Button(action: exitReader) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                    Text("书架")
                        .font(.system(size: 16))
                }
                .foregroundColor(readerConfig.theme.textColor)
                .contentShape(Rectangle())
            }

            Spacer()

            // Book title, with the chapter name underneath when the extra title area is on.
            VStack(spacing: 2) {
                Text(book.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(readerConfig.theme.textColor)
                    .lineLimit(1)
                if readerConfig.prefs.showReadTitleAddition && currentChapterIndex < chapters.count {
                    Text(chapters[currentChapterIndex].title)
                        .font(.system(size: 11))
                        .foregroundColor(readerConfig.theme.textColor.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 180)

            Spacer()

            // Overflow menu. Android puts 换源/刷新/离线缓存 on the bar itself; those
            // arrive with the cache export, so the menu starts with what works today.
            HStack(spacing: 12) {
                Button(action: { changeSourceMode = .wholeBook }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16))
                }

                Button(action: { reloadCurrentChapter() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }

                Menu {
                    Section("书签") {
                        Button("添加书签", action: addBookmark)
                        Button("书签 (\(BookStore.shared.bookmarks(for: book).count))") { showBookmarks = true }
                    }

                    Section("正文") {
                        Button("编辑内容") { showEditContentSheet = true }
                        Button(book.useReplaceRule ?? readerConfig.prefs.replaceEnableDefault
                               ? "关闭净化" : "开启净化", action: toggleReplaceRule)
                        Button("净化与替换规则") { showEffectiveReplaces = true }

                        Menu("图片样式") {
                            ForEach(ReadImageStyle.allCases) { style in
                                Button(style.label) {
                                    var prefs = readerConfig.prefs
                                    prefs.imageStyle = style
                                    readerConfig.prefs = prefs
                                    reloadCurrentChapter()
                                }
                            }
                        }

                        Menu("简繁转换") {
                            Button("关闭") { setConverter(ChineseConverterMode.off) }
                            Button("繁体转简体") { setConverter(ChineseConverterMode.traditionalToSimple) }
                            Button("简体转繁体") { setConverter(ChineseConverterMode.simpleToTraditional) }
                        }
                    }

                    Section("来源") {
                        Button("整书换源") { changeSourceMode = .wholeBook }
                        Button("本章换源") { changeSourceMode = .singleChapter(chapterIndex: currentChapterIndex) }
                        if let source = effectiveSource, let loginUrl = source.loginUrl,
                           !loginUrl.isEmpty {
                            Button("登录该书源") { loginSource = source }
                        }
                    }

                    Section("缓存与离线") {
                        Button("离线下载章节...") { showRangeDownload = true }
                        Button("刷新本章") { reloadCurrentChapter() }
                        Button("更新目录") { Task { await refreshTOC(force: true, notice: .always) } }
                        Button("同步云端进度", action: performProgressSync)
                        Button("清理本书缓存") { clearBookCache() }
                        Button(isAutoPageTurning ? "停止自动翻页" : "开启自动翻页") {
                            toggleAutoPageTurn()
                        }
                    }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                    }
            }
            .foregroundColor(readerConfig.theme.textColor)
            .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            readerConfig.theme.backgroundColor
                .opacity(0.97)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            Rectangle()
                .fill(readerConfig.theme.textColor.opacity(0.12))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var bottomControlPanel: some View {
        VStack(spacing: 12) {
            chapterNavigationRow

            Rectangle()
                .fill(readerConfig.theme.textColor.opacity(0.12))
                .frame(height: 0.5)

            bottomActionRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            readerConfig.theme.backgroundColor
                .opacity(0.97)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Permanent Fixed Bottom Status Bar
    private var fixedBottomStatusBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // Chapter Name
            if !chapters.isEmpty && currentChapterIndex < chapters.count {
                Text(chapters[currentChapterIndex].title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(readerConfig.theme.textColor.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(book.name)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(readerConfig.theme.textColor.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            // Reading Percentage / Page Info
            if !chapters.isEmpty {
                let progressPercent = Double(currentChapterIndex + 1) / Double(chapters.count) * 100.0
                if readerConfig.pageMode == .pageByPage, let cur = currentLoadedChapter, !cur.pages.isEmpty {
                    Text("\(currentPageIndex + 1)/\(cur.pages.count) · \(String(format: "%.1f%%", progressPercent))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(readerConfig.theme.textColor.opacity(0.55))
                } else {
                    Text("\(currentChapterIndex + 1)/\(chapters.count) (\(String(format: "%.1f%%", progressPercent)))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(readerConfig.theme.textColor.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(height: 26)
        .background(readerConfig.theme.backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
    }

    private var chapterNavigationRow: some View {
        let isPageSliderMode = (readerConfig.prefs.progressBarBehavior == 0)
            && (readerConfig.pageMode == .pageByPage)
            && ((currentLoadedChapter?.pages.count ?? 0) > 1)
        let pageCount = max(1, currentLoadedChapter?.pages.count ?? 1)

        return HStack(spacing: 14) {
            Button(action: {
                previousChapter()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上一章")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(currentChapterIndex > 0 ? readerConfig.theme.textColor : readerConfig.theme.textColor.opacity(0.3))
            }
            .disabled(currentChapterIndex <= 0)

            if isPageSliderMode {
                Slider(
                    value: Binding(
                        get: { Double(min(currentPageIndex, pageCount - 1)) },
                        set: { newValue in
                            let target = Int(newValue.rounded())
                            if target != currentPageIndex && target >= 0 && target < pageCount {
                                currentPageIndex = target
                                updateReadingBlockIdFromCurrentPage()
                                saveCurrentProgress()
                            }
                        }
                    ),
                    in: 0...Double(max(1, pageCount - 1)),
                    step: 1
                )
                .accentColor(.accentColor)
            } else if chapters.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(currentChapterIndex) },
                        set: { newValue in
                            let target = Int(newValue.rounded())
                            if target != currentChapterIndex && target >= 0 && target < chapters.count {
                                jumpToChapter(target)
                            }
                        }
                    ),
                    in: 0...Double(chapters.count - 1),
                    step: 1
                )
                .accentColor(.accentColor)
            } else {
                Spacer()
            }

            Button(action: {
                nextChapter()
            }) {
                HStack(spacing: 4) {
                    Text("下一章")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(currentChapterIndex < chapters.count - 1 ? readerConfig.theme.textColor : readerConfig.theme.textColor.opacity(0.3))
            }
            .disabled(currentChapterIndex >= chapters.count - 1)
        }
    }

    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        let prevIndex = currentChapterIndex - 1
        jumpToChapter(prevIndex, toEnd: false)
    }

    private func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        let nextIndex = currentChapterIndex + 1
        jumpToChapter(nextIndex, toEnd: false)
    }

    private func jumpToChapter(_ targetIndex: Int, toEnd: Bool = false) {
        guard targetIndex >= 0 && targetIndex < chapters.count else { return }
        audioService.stop()
        currentChapterIndex = targetIndex
        currentPageIndex = 0
        currentReadingBlockId = 0
        scrollToChapterId = nil
        scrollTargetCharPos = toEnd ? Int.max : nil
        scrollSessionId = UUID()
        loadInitialChapter(at: targetIndex, targetPageIndex: toEnd ? -1 : 0, scrollToTargetEnd: toEnd)
    }

    private func handlePageModeChange(to newMode: PageMode) {
        guard let cur = currentLoadedChapter else { return }

        if newMode == .pageByPage {
            // 1. Switching from Continuous Scroll to Page-by-Page:
            var charPos = 0
            for block in cur.blocks {
                if block.id == currentReadingBlockId {
                    break
                }
                charPos += block.text.count
            }

            var accumulated = 0
            var targetPage = 0
            for (pIdx, page) in cur.pages.enumerated() {
                let pageCharCount = page.reduce(0) { $0 + $1.text.count }
                if accumulated + pageCharCount > charPos {
                    targetPage = pIdx
                    break
                }
                accumulated += pageCharCount
                targetPage = pIdx
            }
            currentPageIndex = min(targetPage, max(0, cur.pages.count - 1))
            updateReadingBlockIdFromCurrentPage()
        } else {
            // 2. Switching from Page-by-Page to Continuous Scroll:
            let charPos = currentChapterCharOffset()
            scrollTargetCharPos = charPos
            scrollSessionId = UUID()
        }
        saveCurrentProgress()
    }

    private var bottomActionRow: some View {
        HStack(spacing: 0) {
            readerBarButton(icon: "list.bullet", title: "目录") { showTOC = true }
            readerBarButton(icon: "magnifyingglass", title: "搜索") { showSearch = true }
            readerBarButton(
                icon: audioService.isPlaying ? "pause.circle.fill"
                     : (audioService.isPaused ? "play.circle.fill" : "headphones"),
                title: audioService.isPlaying ? "暂停" : (audioService.isPaused ? "继续" : "听书"),
                tinted: audioService.isActive
            ) {
                toggleAloud()
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    configureAudioContext()
                    openPanel(.aloud)
                }
            )
            readerBarButton(
                icon: "wand.and.stars",
                title: "净化",
                tinted: book.useReplaceRule ?? readerConfig.prefs.replaceEnableDefault
            ) {
                toggleReplaceRule()
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    showEffectiveReplaces = true
                }
            )
            readerBarButton(icon: "textformat.size", title: "界面") { openPanel(.style) }
            readerBarButton(icon: "slider.horizontal.3", title: "更多") { openPanel(.moreSettings) }
        }
    }

    @ViewBuilder
    private func readerBarButton(icon: String, title: String, tinted: Bool = false,
                                action: @escaping () -> Void) -> some View {
        let color = readerConfig.theme.textColor
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(tinted ? .accentColor : color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tinted ? .accentColor : color)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
        }
    }

    private var searchSheet: some View {
        ReaderSearchSheet(
            book: book,
            currentChapterIndex: currentChapterIndex,
            currentChapterTitle: (!chapters.isEmpty && currentChapterIndex < chapters.count) ? chapters[currentChapterIndex].title : "",
            currentContent: currentChapterContent,
            chapters: chapters,
            onSelectChapter: { targetIndex, _ in
                showSearch = false
                withAnimation {
                    showControls = false
                }
                if targetIndex != currentChapterIndex {
                    jumpToChapter(targetIndex)
                }
            }
        )
    }

    /// Separate view: inlined into the ZStack the body stops type-checking in time.
    private var aloudOverlayContent: some View {
        ReadAloudPanel(audio: audioService,
                           config: readerConfig,
                           canGoPrevious: currentChapterIndex > 0,
                           canGoNext: currentChapterIndex < chapters.count - 1,
                           onPreviousChapter: { moveAloudChapter(by: -1) },
                           onNextChapter: { moveAloudChapter(by: 1) },
                           onOpenToc: { closePanel(); showTOC = true },
                           onMainMenu: { closePanel() },
                           onGoBackground: { goBackgroundKeepingAudio() },
                           onOpenSettings: { openPanel(.moreSettings) })
    }

    private var tocSheet: some View {
        NavigationView {
            ChapterListView(
                bookUrl: book.bookUrl,
                chapters: chapters,
                currentChapterIndex: currentChapterIndex,
                showCloseButton: true,
                onSelectChapter: { index in
                    showTOC = false
                    jumpToChapter(index)
                }
            )
        }
    }

    // MARK: - Data Loading Pipeline

    /// Installs a chapter list and keeps the reader's index inside its bounds.
    private func apply(chapters newChapters: [BookChapter]) {
        var rebuilt = newChapters
        for i in 0..<rebuilt.count { rebuilt[i].index = i }
        chapters = rebuilt
        if currentChapterIndex >= rebuilt.count {
            currentChapterIndex = max(0, rebuilt.count - 1)
        }
    }

    /// Cache-first, like Android's `BookInfoViewModel.kt:105-113` (read the `chapters` table,
    /// crawl only when it is empty).
    ///
    /// Before this the TOC was re-crawled on every single open — the reason reading a book
    /// always cost a round trip, and the reason an offline book could not be opened at all
    /// even though its chapters were on disk.
    private func loadTOCAndStart() async {
        if book.isLocalBook {
            var localChapters = BookStore.shared.getChapters(for: book.bookUrl)
            if !localChapters.isEmpty {
                for i in 0..<localChapters.count {
                    localChapters[i].index = i
                }
                self.chapters = localChapters
                if currentChapterIndex >= localChapters.count {
                    currentChapterIndex = max(0, localChapters.count - 1)
                }
                loadInitialChapter(at: currentChapterIndex)
                return
            }
        }

        let cached = BookStore.shared.getChapters(for: book.bookUrl)
        if !cached.isEmpty {
            apply(chapters: cached)
            errorMessage = nil
            errorGuidance = nil
            loadInitialChapter(at: currentChapterIndex)
            // The cached list may be behind the site; reconcile quietly instead of blocking
            // the reader on it.
            if BookStore.shared.tocIsStale(bookUrl: book.bookUrl) {
                await refreshTOC(force: false, notice: .failuresOnly)
            }
            return
        }

        await crawlTOCFromNetwork()
    }

    /// The only path allowed to show the failure page: there is no cached TOC to fall back on.
    private func crawlTOCFromNetwork() async {
        guard let source = effectiveSource else {
            errorMessage = "未找到书籍关联的书源"
            errorGuidance = "这本书的书源已被删除或禁用。返回书架可在详情页换源，或到「设置 · 书源管理」恢复书源。"
            isLoadingInitial = false
            return
        }

        do {
            let result = try await BookContentService.shared.fetchBookDetailResult(book: book, source: source)
            guard !result.chapters.isEmpty else {
                if await tryAutoChangeSource() { return }
                self.errorMessage = "目录为空"
                self.errorGuidance = "该书源没有返回任何章节。可重试，或换源后再读。"
                self.isLoadingInitial = false
                return
            }
            apply(chapters: result.chapters)
            if result.complete {
                BookStore.shared.saveChapters(result.chapters, for: book.bookUrl)
                BookStore.shared.markTocFetched(bookUrl: book.bookUrl)
            } else {
                // Usable now, but never cached: a half-book TOC would later be compared against
                // as if the book had shrunk.
                showControlHint("目录过长只取到前 \(result.chapters.count) 章，本次不写入缓存")
            }
            loadInitialChapter(at: currentChapterIndex)
        } catch {
            if await tryAutoChangeSource() { return }
            self.errorMessage = "目录解析失败: \(error.localizedDescription)"
            self.errorGuidance = "目录需要联网抓取。请检查网络后重试；离线时无法打开未缓存过目录的书。"
            self.isLoadingInitial = false
        }
    }

    /// Re-crawls the TOC in the background and swaps it in only when it actually changed.
    ///
    /// Never touches `errorMessage`: when this runs we are already reading from the cached
    /// list, so a dead source must not tear the page away.
    /// How loudly a TOC refresh should report itself.
    private enum TocRefreshNotice {
        case silent        // background trigger while reading near the end
        case failuresOnly  // cache-first open: the user should learn they are offline
        case always        // explicit 「更新目录」
    }

    private func refreshTOC(force: Bool, notice: TocRefreshNotice) async {
        guard let source = effectiveSource else { return }
        if !force && !BookStore.shared.tocIsStale(bookUrl: book.bookUrl) { return }

        let previous = chapters
        let keepIndex = currentChapterIndex
        let keepTitle = keepIndex < previous.count ? previous[keepIndex].title : ""
        let keepPos = currentChapterCharOffset()

        do {
            let result = try await BookContentService.shared.fetchBookDetailResult(book: book, source: source)
            // A truncated crawl is not a TOC; caching it would make 追更 compare against a
            // half-book list later.
            guard result.complete, !result.chapters.isEmpty else {
                if notice == .always { showControlHint("目录未更新：抓取不完整或为空") }
                return
            }
            BookStore.shared.saveChapters(result.chapters, for: book.bookUrl)
            BookStore.shared.markTocFetched(bookUrl: book.bookUrl)

            let unchanged = TocCache.isSameList(result.chapters, previous)
            guard !unchanged else {
                if notice == .always { showControlHint("目录已是最新（\(previous.count) 章）") }
                return
            }

            // The content cache is keyed by chapter index. As long as the new list is only the
            // old one plus appended chapters, every cached body still belongs to its index; any
            // other shape means the indices now point at different chapters.
            if !TocCache.isAppendOnly(previous, result.chapters) {
                chapterCache.removeAll()
                BookContentService.shared.clearCache(for: book.bookUrl)
                if notice != .silent { showControlHint("目录结构变化，已清除旧的章节缓存") }
            }

            let titles = result.chapters.map { $0.title }
            let mapped = ChapterMatcher.mapChapter(oldIndex: keepIndex, oldTitle: keepTitle,
                                                   oldCount: previous.count, newTitles: titles)
            apply(chapters: result.chapters)
            let newIndex = min(mapped, max(0, result.chapters.count - 1))
            currentChapterIndex = newIndex
            loadInitialChapter(at: newIndex,
                               targetCharPos: newIndex == keepIndex ? keepPos : nil)
            if notice == .always {
                showControlHint("目录已更新：\(previous.count) → \(result.chapters.count) 章")
            }
        } catch {
            guard notice != .silent else { return }
            // This is the offline case that matters: the reader is showing a cached TOC, and
            // without a word about it a missing chapter looks like a broken book source.
            showControlHint("无法更新目录（\(error.localizedDescription)），当前显示缓存内容")
        }
    }

    /// 自动换源: when the current source cannot produce a usable TOC, move the book to the
    /// first other source that can, without interrupting reading. Off by default.
    private func tryAutoChangeSource() async -> Bool {
        guard readerConfig.prefs.autoChangeSource, !isAutoChangingSource else { return false }
        isAutoChangingSource = true
        defer { isAutoChangingSource = false }

        let target = book
        let sources = BookStore.shared.sources
        for await candidate in ChangeSourceService.shared.verifiedCandidates(book: target, sources: sources) {
            guard candidate.found.bookUrl != target.bookUrl else { continue }
            let probe = Book(bookUrl: candidate.found.bookUrl, name: candidate.found.name,
                             author: candidate.found.author, origin: candidate.source.bookSourceUrl,
                             originName: candidate.source.bookSourceName, tocUrl: candidate.found.bookUrl)
            guard let toc = try? await BookContentService.shared.fetchChapterList(book: probe,
                                                                                 source: candidate.source),
                  !toc.isEmpty else { continue }
            applySourceChange(candidate, toc)
            return true
        }
        return false
    }

    private func makeLoadedChapter(chapter: BookChapter, content: String) -> LoadedChapter {
        let usableWidth = readerConfig.contentSize(for: readerContainerSize).width
        let usableHeight = readerContainerSize.height
        let typo = TypographyEngine.typeset(
            chapter: chapter,
            content: content,
            containerWidth: usableWidth + readerConfig.paddingLeading + readerConfig.paddingTrailing,
            containerHeight: usableHeight,
            fontSize: readerConfig.fontSize,
            lineSpacing: readerConfig.lineSpacing,
            letterSpacing: readerConfig.letterSpacing,
            paragraphSpacing: readerConfig.paragraphSpacing,
            paddingLeading: readerConfig.paddingLeading,
            paddingTrailing: readerConfig.paddingTrailing,
            paddingTop: readerConfig.paddingTop,
            paddingBottom: readerConfig.paddingBottom,
            imageStyle: readerConfig.prefs.imageStyle,
            justify: readerConfig.prefs.textFullJustify
        )
        let blocks = parseContentBlocks(from: content)
        let pages = paginate(blocks: blocks, titleHeight: typo.titleTotalHeight)
        return LoadedChapter(
            chapter: chapter,
            content: content,
            typography: typo,
            blocks: blocks,
            pages: pages
        )
    }

    @MainActor
    private func getOrFetchChapter(at index: Int) async -> LoadedChapter? {
        guard index >= 0 && index < chapters.count else { return nil }
        if let cached = chapterCache[index] {
            return cached
        }
        let targetChapter = chapters[index]
        let context = processContext(for: targetChapter)
        do {
            let content = try await BookContentService.shared.fetchChapterContent(
                chapter: targetChapter, source: effectiveSource,
                nextChapterUrl: nextChapterUrl(after: index), context: context)
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               await tryAutoChangeSource() {
                return nil
            }
            let loaded = makeLoadedChapter(chapter: targetChapter, content: content)
            self.chapterCache[index] = loaded
            return loaded
        } catch {
            return nil
        }
    }

    private func preCacheNeighbors(around index: Int) {
        let source = effectiveSource
        // 1. In-memory pre-cache previous chapter
        if index > 0 && chapterCache[index - 1] == nil {
            let prevCh = chapters[index - 1]
            let prevNextUrl = chapters[index].url
            let prevContext = processContext(for: prevCh)
            Task { @MainActor in
                if let content = try? await BookContentService.shared.fetchChapterContent(
                    chapter: prevCh, source: source, nextChapterUrl: prevNextUrl, context: prevContext) {
                    let loaded = self.makeLoadedChapter(chapter: prevCh, content: content)
                    self.chapterCache[index - 1] = loaded
                }
            }
        }
        // 2. In-memory pre-cache next chapter
        if index < chapters.count - 1 && chapterCache[index + 1] == nil {
            let nextCh = chapters[index + 1]
            let afterNextUrl = index + 2 < chapters.count ? chapters[index + 2].url : nil
            let nextContext = processContext(for: nextCh)
            Task { @MainActor in
                if let content = try? await BookContentService.shared.fetchChapterContent(
                    chapter: nextCh, source: source, nextChapterUrl: afterNextUrl, context: nextContext) {
                    let loaded = self.makeLoadedChapter(chapter: nextCh, content: content)
                    self.chapterCache[index + 1] = loaded
                }
            }
        }
        // 3. Disk cache pre-download for 10 chapters around
        BookContentService.shared.preDownloadChapters(around: index, chapters: self.chapters, source: source)
    }

    /// URL of the chapter following `index`; lets a paginated chapter stop before it
    /// wanders into the next chapter.
    private func nextChapterUrl(after index: Int) -> String? {
        guard index + 1 < chapters.count else { return nil }
        return chapters[index + 1].url
    }

    /// The 净化 context for one chapter: book identity drives rule scope matching, style
    /// supplies the indent, prefs the conversion / replace switches.
    private func processContext(for chapter: BookChapter) -> ProcessContext {
        ProcessContext(bookName: book.name,
                       bookOrigin: book.origin,
                       chapterTitle: chapter.title,
                       useReplaceRule: book.useReplaceRule,
                       style: readerConfig.styleConfig,
                       prefs: readerConfig.prefs)
    }

    /// - Parameter targetCharPos: character offset to land on, e.g. from a bookmark. When
    ///   omitted, the position falls back to the book's own `durChapterPos` — but only for
    ///   the chapter that position belongs to.
    private func loadInitialChapter(at index: Int, targetPageIndex: Int = 0, scrollToTargetEnd: Bool = false,
                                    targetCharPos: Int? = nil) {
        guard !chapters.isEmpty, index < chapters.count else { return }
        let currentChapter = chapters[index]
        if loadedChapters.isEmpty {
            isLoadingInitial = true
        }
        errorMessage = nil
        errorGuidance = nil

        let source = effectiveSource

        Task { @MainActor in
            do {
                let loaded: LoadedChapter
                if let cached = self.chapterCache[index] {
                    loaded = cached
                } else {
                    let content = try await BookContentService.shared.fetchChapterContent(
                        chapter: currentChapter, source: source,
                        nextChapterUrl: nextChapterUrl(after: index),
                        context: processContext(for: currentChapter))
                    loaded = self.makeLoadedChapter(chapter: currentChapter, content: content)
                    self.chapterCache[index] = loaded
                }

                self.currentChapterIndex = index

                let restorePos = targetCharPos
                    ?? (index == self.book.durChapterIndex ? self.book.durChapterPos : 0)

                // Restore position if durChapterPos is saved and opening the current chapter
                if targetPageIndex == 0 && restorePos > 0 {
                    if self.readerConfig.pageMode == .pageByPage {
                        if let typo = loaded.typography {
                            self.currentPageIndex = typo.pageIndex(forCharOffset: restorePos)
                        } else {
                            var accumulated = 0
                            var targetPage = 0
                            for (pIdx, page) in loaded.pages.enumerated() {
                                let pageCount = page.reduce(0) { $0 + $1.text.count }
                                if accumulated + pageCount > restorePos {
                                    targetPage = pIdx
                                    break
                                }
                                accumulated += pageCount
                                targetPage = pIdx
                            }
                            self.currentPageIndex = min(targetPage, max(0, loaded.pages.count - 1))
                        }
                    } else {
                        self.scrollTargetCharPos = restorePos
                    }
                } else if targetPageIndex == -1 {
                    self.currentPageIndex = max(0, loaded.pages.count - 1)
                    if self.readerConfig.pageMode == .scroll && self.scrollToChapterId == nil {
                        self.scrollToChapterId = "chapter_end_\(index)"
                    }
                } else {
                    self.currentPageIndex = min(targetPageIndex, max(0, loaded.pages.count - 1))
                    if self.readerConfig.pageMode == .scroll && self.scrollToChapterId == nil {
                        self.scrollToChapterId = "chapter_\(index)"
                    }
                }

                if self.currentPageIndex < loaded.pages.count {
                    self.currentReadingBlockId = loaded.pages[self.currentPageIndex].first?.id ?? 0
                }

                self.loadedChapters = [loaded]

                self.isLoadingInitial = false
                let currentPos = self.currentChapterCharOffset()
                BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: index, chapterTitle: currentChapter.title, chapterPos: currentPos)
                self.preCacheNeighbors(around: index)
                // Android re-crawls the TOC once the reader gets near the end of a serialising
                // book (`ReadBook.upToc`), which is how new chapters show up without a manual
                // 「更新目录」。
                if index >= self.chapters.count - 3 {
                    Task { await self.refreshTOC(force: false, notice: .silent) }
                }

                if readerConfig.pageMode == .scroll && self.scrollToChapterId == nil {
                    self.scrollToChapterId = scrollToTargetEnd ? "chapter_end_\(index)" : "chapter_\(index)"
                }
            } catch {
                // Android renders the error as the page's text (`ReadBook.upMsg`) and keeps the
                // reader navigable; the iOS equivalent is a banner when something is already on
                // screen. Taking over the canvas here used to hide the previous chapter and, with
                // the tap zones gone, made the reader feel trapped.
                if self.hasReadableContent {
                    self.showControlHint("本章获取失败：\(error.localizedDescription)")
                } else {
                    self.errorMessage = "正文解析失败: \(error.localizedDescription)"
                    self.errorGuidance = "这一章还没有本地缓存，需要联网获取。可重试、跳到别的章节，或返回书架。"
                }
                self.isLoadingInitial = false
            }
        }
    }


    private func recomputePagination() {
        let charPos = currentChapterCharOffset()

        for i in 0..<loadedChapters.count {
            let ch = loadedChapters[i]
            loadedChapters[i] = makeLoadedChapter(chapter: ch.chapter, content: ch.content)
            chapterCache[ch.chapter.index] = loadedChapters[i]
        }

        if let cur = currentLoadedChapter {
            if let typo = cur.typography {
                currentPageIndex = typo.pageIndex(forCharOffset: charPos)
            } else if !cur.pages.isEmpty {
                var accumulated = 0
                var targetPage = 0
                for (pIdx, page) in cur.pages.enumerated() {
                    let pageCharCount = page.reduce(0) { $0 + $1.text.count }
                    if accumulated + pageCharCount > charPos {
                        targetPage = pIdx
                        break
                    }
                    accumulated += pageCharCount
                    targetPage = pIdx
                }
                currentPageIndex = min(targetPage, max(0, cur.pages.count - 1))
            }
            updateReadingBlockIdFromCurrentPage()
        }
    }

    // MARK: - Paragraph and Page Parser

    /// Turns already-sanitised, already-indented text into blocks.
    ///
    /// First-line indentation is applied by `ContentProcessor` (Android trims each line then
    /// re-adds the configured indent). Trimming again here would erase it, so only trailing
    /// whitespace is removed.
    private func parseContentBlocks(from text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentId = 0
        let regex = try? NSRegularExpression(pattern: "\\[image:(.*?)\\]")
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let paragraph = Self.trimTrailingWhitespace(line)
            if paragraph.isEmpty { continue }

            if let regex = regex {
                let nsLine = paragraph as NSString
                let matches = regex.matches(in: paragraph, range: NSRange(location: 0, length: nsLine.length))
                if !matches.isEmpty {
                    var lastIndex = 0
                    for match in matches {
                        if match.range.location > lastIndex {
                            let textBefore = Self.trimTrailingWhitespace(
                                nsLine.substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex)))
                            if !textBefore.isEmpty {
                                blocks.append(ContentBlock(id: currentId, isImage: false, text: textBefore, imageUrl: nil))
                                currentId += 1
                            }
                        }
                        if match.numberOfRanges > 1 {
                            let imgUrl = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                            if readerConfig.prefs.imageStyle != .textOnly {
                                blocks.append(ContentBlock(id: currentId, isImage: true, text: "", imageUrl: imgUrl))
                                currentId += 1
                            }
                        }
                        lastIndex = match.range.location + match.range.length
                    }
                    if lastIndex < nsLine.length {
                        let textAfter = nsLine.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !textAfter.isEmpty {
                            blocks.append(ContentBlock(id: currentId, isImage: false, text: textAfter, imageUrl: nil))
                            currentId += 1
                        }
                    }
                    continue
                }
            }

            blocks.append(ContentBlock(id: currentId, isImage: false, text: paragraph, imageUrl: nil))
            currentId += 1
        }
        return blocks
    }

    static func trimTrailingWhitespace(_ text: String) -> String {
        var slice = Substring(text)
        while let last = slice.last, last == " " || last == "\t" || last == "\r" || last == "\u{3000}" || last.isNewline {
            slice = slice.dropLast()
        }
        return String(slice)
    }

    private func currentChapterCharOffset() -> Int {
        guard let cur = currentLoadedChapter else { return 0 }
        if readerConfig.pageMode == .pageByPage {
            if let typo = cur.typography,
               currentPageIndex < typo.pageRanges.count {
                let range = typo.pageRanges[currentPageIndex]
                if range.lowerBound < typo.lines.count {
                    return typo.lines[range.lowerBound].charRange.lowerBound
                }
            }
            var offset = 0
            let limit = min(currentPageIndex, cur.pages.count)
            for p in 0..<limit {
                for block in cur.pages[p] {
                    offset += block.text.count
                }
            }
            return offset
        } else {
            return scrollReadingCharOffset
        }
    }

    private func saveCurrentProgress() {
        guard let cur = currentLoadedChapter else { return }
        let pos = currentChapterCharOffset()
        BookStore.shared.updateProgress(
            bookUrl: book.bookUrl,
            chapterIndex: currentChapterIndex,
            chapterTitle: cur.chapter.title,
            chapterPos: pos
        )
    }

    // MARK: - Bookmarks

    /// Text captured with a new bookmark: the current page when paging, or the paragraph the
    /// reader is on when scrolling.
    private func currentPageText() -> String {
        guard let chapter = currentLoadedChapter else { return "" }
        if readerConfig.pageMode == .pageByPage,
           currentPageIndex < chapter.pages.count {
            return chapter.pages[currentPageIndex]
                .map { $0.text }
                .filter { !$0.isEmpty && $0 != "p_end" }
                .joined(separator: "\n")
        }
        let start = chapter.blocks.firstIndex { $0.id == currentReadingBlockId } ?? 0
        let end = min(start + 4, chapter.blocks.count)
        guard start < end else { return "" }
        return chapter.blocks[start..<end]
            .map { $0.text }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func addBookmark() {
        guard currentChapterIndex < chapters.count else { return }
        let bookmark = Bookmark(
            bookName: book.name,
            bookAuthor: book.author,
            chapterIndex: currentChapterIndex,
            chapterPos: currentChapterCharOffset(),
            chapterName: chapters[currentChapterIndex].title,
            bookText: currentPageText()
        )
        bookmarkIsNew = true
        editingBookmark = bookmark
    }

    private func jumpToBookmark(_ bookmark: Bookmark) {
        guard bookmark.chapterIndex < chapters.count else { return }
        audioService.stop()
        currentChapterIndex = bookmark.chapterIndex
        currentPageIndex = 0
        loadInitialChapter(at: bookmark.chapterIndex, targetCharPos: bookmark.chapterPos)
    }

    // MARK: - 换源

    private func applySourceChange(_ candidate: ChangeSourceCandidate, _ toc: [BookChapter]) {
        let mapped = ChapterMatcher.mapChapter(oldIndex: book.durChapterIndex,
                                               oldTitle: book.durChapterTitle ?? "",
                                               oldCount: max(book.totalChapterNum, 1),
                                               newTitles: toc.map { $0.title })
        let updated = BookStore.shared.changeSource(oldBook: book, to: candidate.found,
                                                    source: candidate.source,
                                                    newChapters: toc,
                                                    mappedChapterIndex: mapped)
        book = updated
        currentSource = candidate.source
        chapters = toc
        currentChapterIndex = min(mapped, max(0, toc.count - 1))
        currentPageIndex = 0
        chapterCache.removeAll()
        loadedChapters.removeAll()
        audioService.stop()
        changeSourceMode = nil
        loadInitialChapter(at: currentChapterIndex, targetCharPos: updated.durChapterPos)
    }

    /// Single-chapter switch: the text is cached under the *current* book and chapter, which
    /// is exactly what Android does (there is no per-chapter source field).
    private func applyChapterText(_ text: String) {
        guard currentChapterIndex < chapters.count else { return }
        BookContentService.shared.saveCachedChapterContent(bookUrl: book.bookUrl,
                                                          chapterIndex: currentChapterIndex,
                                                          content: text)
        changeSourceMode = nil
        reloadCurrentChapter()
    }

    // MARK: - Read aloud

    /// Chapter stepping driven by the aloud panel, the tap zones and the lock screen. It
    /// loads the chapter itself so speech continues without a gap in the queue.
    private func moveAloudChapter(by delta: Int) {
        let target = currentChapterIndex + delta
        guard target >= 0, target < chapters.count else {
            audioService.stop()
            return
        }
        Task { @MainActor in
            guard let loaded = await getOrFetchChapter(at: target) else {
                audioService.stop()
                return
            }
            currentChapterIndex = target
            currentPageIndex = 0
            currentReadingBlockId = loaded.blocks.first?.id ?? 0
            if readerConfig.pageMode == .scroll {
                loadedChapters = [loaded]
            }
            saveCurrentProgress()
            configureAudioContext()
            audioService.load(chapterText: loaded.content, startCharPos: 0)
            preCacheNeighbors(around: target)
        }
    }

    private func toggleAloud() {
        configureAudioContext()
        if audioService.isActive {
            audioService.togglePlayPause()
        } else {
            audioService.load(chapterText: currentChapterContent,
                              startCharPos: currentAloudStartPos())
        }
    }

    /// Chapter-relative offset of the first character on screen, in `ReadAloudText`'s own
    /// counting basis (paragraph lengths plus the newline between them). Matching that basis is
    /// the point: the block-summing offset used for `durChapterPos` does not count newlines or
    /// image lines, so feeding it to the speech queue would land on the wrong paragraph.
    private func currentAloudStartPos() -> Int {
        guard let cur = currentLoadedChapter else { return 0 }
        let anchorText: String
        if readerConfig.pageMode == .pageByPage, currentPageIndex < cur.pages.count {
            anchorText = cur.pages[currentPageIndex].first { !$0.text.isEmpty }?.text ?? ""
        } else {
            anchorText = cur.blocks.first { $0.id == currentReadingBlockId }?.text ?? ""
        }
        let needle = anchorText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return 0 }

        let paragraphs = ReadAloudText.paragraphs(in: cur.content)
        guard let index = paragraphs.firstIndex(of: needle) else { return 0 }
        return ReadAloudText.offset(of: paragraphs, at: index)
    }

    // MARK: - Auto Page Turn Logic

    private func toggleAutoPageTurn() {
        if isAutoPageTurning {
            stopAutoPageTurn()
        } else {
            startAutoPageTurn()
        }
    }

    private func startAutoPageTurn() {
        isAutoPageTurning = true
        setControls(false)
        restartAutoTurnTimer()
    }

    private func stopAutoPageTurn() {
        autoTurnTask?.cancel()
        autoTurnTask = nil
        isAutoPageTurning = false
    }

    private func restartAutoTurnTimer() {
        autoTurnTask?.cancel()
        autoTurnTask = Task { @MainActor [weak readerConfig] in
            while !Task.isCancelled {
                let interval = UInt64(autoTurnIntervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                if readerConfig?.pageMode == .pageByPage {
                    turnPage(forward: true)
                } else {
                    nextChapter()
                }
            }
        }
    }

    // MARK: - Chapter Content Editing

    private func saveEditedChapter(newTitle: String, newContent: String) {
        guard currentChapterIndex < chapters.count else { return }
        chapters[currentChapterIndex].title = newTitle
        let loaded = makeLoadedChapter(chapter: chapters[currentChapterIndex], content: newContent)
        chapterCache[currentChapterIndex] = loaded
        if let idx = loadedChapters.firstIndex(where: { $0.chapter.index == currentChapterIndex }) {
            loadedChapters[idx] = loaded
        }
        BookContentService.shared.saveCachedChapterContent(
            bookUrl: book.bookUrl,
            chapterIndex: currentChapterIndex,
            content: newContent
        )
        showControlHint("章节内容已保存")
    }

    private func resetEditedChapter() {
        guard currentChapterIndex < chapters.count else { return }
        BookContentService.shared.clearCachedChapter(bookUrl: book.bookUrl, chapterIndex: currentChapterIndex)
        chapterCache[currentChapterIndex] = nil
        reloadCurrentChapter()
        showControlHint("已重置为书源原始内容")
    }

    // MARK: - WebDAV Progress Sync

    private func performProgressSync() {
        let config = WebDAVService.shared.loadConfig()
        guard !config.url.isEmpty, !config.username.isEmpty else {
            showControlHint("未配置 WebDAV，请先在设置中完成配置")
            return
        }
        showControlHint("正在同步云端进度...")
        Task { @MainActor in
            do {
                let remoteProg = try await WebDAVService.shared.downloadBookProgress(book: book, config: config)
                let localTime = max(book.durChapterTime, book.lastCheckTime)
                if let remote = remoteProg,
                   (remote.durChapterTime ?? 0) > localTime,
                   remote.durChapterIndex >= 0,
                   remote.durChapterIndex < chapters.count {
                    BookStore.shared.updateProgress(
                        bookUrl: book.bookUrl,
                        chapterIndex: remote.durChapterIndex,
                        chapterTitle: remote.durChapterTitle ?? chapters[remote.durChapterIndex].title,
                        chapterPos: remote.durChapterPos
                    )
                    book.durChapterIndex = remote.durChapterIndex
                    book.durChapterPos = remote.durChapterPos
                    book.durChapterTitle = remote.durChapterTitle
                    book.durChapterTime = remote.durChapterTime ?? Int64(Date().timeIntervalSince1970 * 1000)
                    currentChapterIndex = remote.durChapterIndex
                    currentPageIndex = 0
                    loadInitialChapter(at: remote.durChapterIndex, targetCharPos: remote.durChapterPos)
                    showControlHint("已拉取云端最新进度: \(remote.durChapterTitle ?? chapters[remote.durChapterIndex].title)")
                } else {
                    saveCurrentProgress()
                    if let updatedBook = BookStore.shared.bookshelf.first(where: { $0.bookUrl == book.bookUrl }) {
                        try await WebDAVService.shared.uploadBookProgress(book: updatedBook, config: config)
                    } else {
                        try await WebDAVService.shared.uploadBookProgress(book: book, config: config)
                    }
                    showControlHint("当前阅读进度已上传至云端")
                }
            } catch {
                showControlHint("进度同步失败: \(error.localizedDescription)")
            }
        }
    }


    // MARK: - Selected Text Action
    private func openDictForSelected(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedWordForDict = trimmed
    }

    private func configureAudioContext() {
        audioService.nowPlayingTitle = book.name
        audioService.nowPlayingSubtitle = currentChapterIndex < chapters.count
            ? chapters[currentChapterIndex].title : ""
    }

    /// "后台" leaves the reader but keeps speaking, which is why `onDisappear` must not
    /// stop the service in that case.
    private func goBackgroundKeepingAudio() {
        guard audioService.isActive else {
            closePanel()
            return
        }
        keepAloudInBackground = true
        closePanel()
        if let onDismiss = onDismiss {
            onDismiss()
        }
        dismiss()
    }

    /// The one way out of the reader. Also the only affordance on the failure page, which is
    /// why it must never depend on `showControls` or the canvas being rendered.
    private func exitReader() {
        audioService.stop()
        if let onDismiss = onDismiss {
            onDismiss()
        }
        dismiss()
    }

    /// Hands paragraph stepping to whichever control asked for it.
    private func wireAudioService() {
        audioService.onRequestChapter = { delta in
            Task { @MainActor in
                moveAloudChapter(by: delta)
            }
        }
    }

    /// Page capacity expressed as heights, so 段距 can be charged to the paragraph it
    /// follows instead of being averaged over a fixed line count.
    private func calculateLayoutMetrics(titleHeight: CGFloat? = nil) -> (lineHeight: CGFloat, pageHeight: CGFloat, firstPageHeight: CGFloat) {
        let height = max(400, readerContainerSize.height)

        let lineHeight = readerConfig.fontSize * 1.25 + readerConfig.lineSpacing
        let usableHeight = max(200, height - readerConfig.paddingTop - readerConfig.paddingBottom)

        // First page has chapter title (+ title padding)
        let computedTitleHeight = titleHeight ?? (((readerConfig.fontSize + 3) * 1.3 + readerConfig.lineSpacing) * 1.5 + 16.0)

        return (lineHeight: lineHeight,
                pageHeight: usableHeight,
                firstPageHeight: max(100, usableHeight - computedTitleHeight))
    }

    private func splitParagraphIntoLines(text: String, width: Double, fontSize: CGFloat) -> [(text: String, isParagraphEnd: Bool)] {
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        var attributes: [CFString: Any] = [kCTFontAttributeName: font]
        // Kerning changes how much fits on a line, so measurement and drawing have to agree.
        if readerConfig.letterSpacing != 0 {
            attributes[kCTKernAttributeName] = readerConfig.letterSpacing
        }
        guard let attrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else {
            return [(text, true)]
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attrString)
        var start = 0
        let textLen = CFStringGetLength(text as CFString)
        var result: [(text: String, isParagraphEnd: Bool)] = []
        let nsStr = text as NSString

        while start < textLen {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, width)
            if count <= 0 { break }
            let sub = nsStr.substring(with: NSRange(location: start, length: count))
            let isEnd = (start + count >= textLen)
            result.append((sub, isEnd))
            start += count
        }
        return result
    }

    private func buildPageBlocks(from lines: [(text: String, isParagraphEnd: Bool)], startingId: inout Int) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        for line in lines {
            blocks.append(ContentBlock(
                id: startingId,
                isImage: false,
                text: line.text,
                imageUrl: line.isParagraphEnd ? "p_end" : nil
            ))
            startingId += 1
        }
        return blocks
    }

    private func paginate(blocks: [ContentBlock], titleHeight: CGFloat? = nil) -> [[ContentBlock]] {
        let metrics = calculateLayoutMetrics(titleHeight: titleHeight)
        let usableWidth = Double(readerConfig.contentSize(for: readerContainerSize).width)
        let paragraphSpacing = readerConfig.paragraphSpacing

        var pages: [[ContentBlock]] = []
        var currentPageLines: [(text: String, isParagraphEnd: Bool)] = []
        var usedHeight: CGFloat = 0
        var pageHeight = metrics.firstPageHeight
        var blockIdCounter = 10000

        func flushPage() {
            guard !currentPageLines.isEmpty else { return }
            pages.append(buildPageBlocks(from: currentPageLines, startingId: &blockIdCounter))
            currentPageLines = []
            usedHeight = 0
            pageHeight = metrics.pageHeight
        }

        for block in blocks {
            if block.isImage {
                flushPage()
                pages.append([block])
                pageHeight = metrics.pageHeight
                usedHeight = 0
            } else {
                let pLines = splitParagraphIntoLines(text: block.text, width: usableWidth, fontSize: readerConfig.fontSize)
                for lineInfo in pLines {
                    currentPageLines.append(lineInfo)
                    usedHeight += metrics.lineHeight + (lineInfo.isParagraphEnd ? paragraphSpacing : 0)
                    // Always keep at least one line on a page, otherwise a paragraph gap
                    // taller than the page would spin forever.
                    if usedHeight >= pageHeight, currentPageLines.count > 1 {
                        flushPage()
                        pageHeight = metrics.pageHeight
                    }
                }
            }
        }

        if !currentPageLines.isEmpty {
            pages.append(buildPageBlocks(from: currentPageLines, startingId: &blockIdCounter))
        }

        return pages.isEmpty ? [[]] : pages
    }
}

// MARK: - Chapter Image Component with Anti-Hotlinking Headers & Cache
public struct ChapterImageView: View {
    public let urlString: String
    public let referer: String?

    @State private var imageData: Data? = nil
    @State private var isLoading: Bool = false
    @State private var loadFailed: Bool = false
    @State private var showFullScreen: Bool = false
    private static let imageCache = NSCache<NSString, NSData>()

    public init(urlString: String, referer: String? = nil) {
        self.urlString = urlString
        self.referer = referer
    }

    public var body: some View {
        Group {
            if let data = imageData, let img = platformImage(from: data) {
                img
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showFullScreen = true
                    }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载插图中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.vertical, 6)
            } else if loadFailed {
                Button(action: { Task { await loadImage() } }) {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                        Text("插图加载失败，点击重试")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task(id: urlString) {
            await loadImage()
        }
        .sheet(isPresented: $showFullScreen) {
            NavigationView {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let data = imageData, let img = platformImage(from: data) {
                        ScrollView([.horizontal, .vertical], showsIndicators: false) {
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .navigationTitle("图片预览")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showFullScreen = false }
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private func loadImage() async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Check in-memory cache
        if let cached = Self.imageCache.object(forKey: trimmed as NSString) {
            self.imageData = cached as Data
            self.isLoading = false
            self.loadFailed = false
            return
        }

        // 2. Check local file
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed), let data = try? Data(contentsOf: url) {
                Self.imageCache.setObject(data as NSData, forKey: trimmed as NSString)
                self.imageData = data
                return
            }
        }

        // 3. Remote URL with proper browser headers
        guard let url = URL(string: trimmed) else {
            self.loadFailed = true
            return
        }

        self.isLoading = true
        self.loadFailed = false

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

            // Determine Referer
            if let ref = referer, !ref.isEmpty {
                request.setValue(ref, forHTTPHeaderField: "Referer")
            } else if let host = url.host {
                request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 304), !data.isEmpty {
                Self.imageCache.setObject(data as NSData, forKey: trimmed as NSString)
                await MainActor.run {
                    self.imageData = data
                    self.isLoading = false
                    self.loadFailed = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.loadFailed = true
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.loadFailed = true
            }
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) {
            return Image(nsImage: ns)
        }
        #endif
        return nil
    }
}

// MARK: - Reader Search Sheet
public struct ReaderSearchSheet: View {
    let book: Book
    let currentChapterIndex: Int
    let currentChapterTitle: String
    let currentContent: String
    let chapters: [BookChapter]
    let onSelectChapter: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var searchScope: Int = 0 // 0: 本章内容, 1: 目录章节, 2: 查字典
    @State private var dictDefinition: String? = nil
    @State private var isSearchingDict: Bool = false
    @State private var selectedDictRuleName: String = ""

    public struct SearchItem: Identifiable {
        public let id = UUID()
        public let chapterIndex: Int
        public let title: String
        public let snippet: String
    }
    private var currentChapterMatches: [SearchItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [SearchItem] = []
        let lines = currentContent.components(separatedBy: "\n")
        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.localizedCaseInsensitiveContains(query) {
                results.append(SearchItem(
                    chapterIndex: currentChapterIndex,
                    title: "\(currentChapterTitle) (第 \(lineIdx + 1) 段)",
                    snippet: trimmed
                ))
            }
        }
        return results
    }

    private var tocMatches: [SearchItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return chapters.compactMap { ch in
            if ch.title.localizedCaseInsensitiveContains(query) {
                return SearchItem(
                    chapterIndex: ch.index,
                    title: "第 \(ch.index + 1) 章",
                    snippet: ch.title
                )
            }
            return nil
        }
    }
    private var activeResults: [SearchItem] {
        searchScope == 0 ? currentChapterMatches : tocMatches
    }

    private var enabledDictRules: [DictRule] {
        DictRuleStore.load().filter { $0.enabled }
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("搜索范围", selection: $searchScope) {
                    Text("本章正文").tag(0)
                    Text("目录搜索").tag(1)
                    Text("查字典").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if searchScope == 2 {
                    dictLookupView
                } else if searchText.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(searchScope == 0 ? "输入关键词搜索当前章节正文" : "输入关键词搜索目录章节")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if activeResults.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("未找到包含 “\(searchText)” 的内容")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(activeResults) { item in
                        Button(action: {
                            onSelectChapter(item.chapterIndex, item.snippet)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(item.snippet)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("查找")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: searchScope == 0 ? "搜索当前章节内容..." : "搜索章节名称...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var dictLookupView: some View {
        VStack(spacing: 10) {
            if enabledDictRules.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(enabledDictRules) { r in
                            let isSel = (selectedDictRuleName.isEmpty ? enabledDictRules.first?.name == r.name : selectedDictRuleName == r.name)
                            Button {
                                selectedDictRuleName = r.name
                                searchDict()
                            } label: {
                                Text(r.name)
                                    .font(.caption.weight(isSel ? .bold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSel ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(isSel ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if isSearchingDict {
                Spacer()
                ProgressView()
                Text("正在查询字典...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if let def = dictDefinition {
                ScrollView {
                    Text(def)
                        .font(.subheadline)
                        .lineSpacing(5)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("输入字词后回车即可联网查词")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .onAppear {
            if selectedDictRuleName.isEmpty {
                selectedDictRuleName = enabledDictRules.first?.name ?? ""
            }
        }
        .onSubmit(of: .search) {
            searchDict()
        }
    }

    private func searchDict() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let rule = enabledDictRules.first { $0.name == selectedDictRuleName } ?? enabledDictRules.first
        guard let r = rule else {
            dictDefinition = "暂无可用的字典规则，请在设置中配置"
            return
        }
        isSearchingDict = true
        dictDefinition = nil
        let renderedUrl = r.urlRule.replacingOccurrences(of: "{{key}}", with: query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
        Task {
            do {
                guard let parsed = NetworkClient.parseLegadoUrl(renderedUrl) else {
                    await MainActor.run {
                        isSearchingDict = false
                        dictDefinition = "无效的字典 URL 规则"
                    }
                    return
                }
                let resp = try await NetworkClient.shared.request(parsed: parsed)
                let body = resp.bodyString
                let resultText: String
                if !r.showRule.isEmpty {
                    let analyzer = RuleAnalyzer(content: body, baseUrl: renderedUrl)
                    resultText = analyzer.getString(r.showRule)
                } else {
                    resultText = BookContentService.cleanHtml(body)
                }
                await MainActor.run {
                    isSearchingDict = false
                    dictDefinition = resultText.isEmpty ? "未找到关于 “\(query)” 的释义" : resultText
                }
            } catch {
                await MainActor.run {
                    isSearchingDict = false
                    dictDefinition = "查词失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - CoreText Two-End Justified Page View (两端对齐与定高排版组件)
#if os(macOS)
import AppKit

public struct CoreTextPageView: NSViewRepresentable {
    public let lines: [String]
    public let isParagraphEnd: [Bool]
    public let fontSize: CGFloat
    public let lineSpacing: CGFloat
    public let textColor: Color
    public let width: CGFloat
    public let height: CGFloat
    public var letterSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var justify: Bool = true

    public func makeNSView(context: Context) -> CoreTextNSView {
        let view = CoreTextNSView()
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ nsView: CoreTextNSView, context: Context) {
        nsView.lines = lines
        nsView.isParagraphEnd = isParagraphEnd
        nsView.fontSize = fontSize
        nsView.lineSpacing = lineSpacing
        nsView.textColor = NSColor(textColor)
        nsView.containerWidth = width
        nsView.containerHeight = height
        nsView.letterSpacing = letterSpacing
        nsView.paragraphSpacing = paragraphSpacing
        nsView.justify = justify
        nsView.needsDisplay = true
    }
}

public class CoreTextNSView: NSView {
    public var lines: [String] = []
    public var isParagraphEnd: [Bool] = []
    public var fontSize: CGFloat = 18
    public var lineSpacing: CGFloat = 6
    public var textColor: NSColor = .textColor
    public var containerWidth: CGFloat = 340
    public var containerHeight: CGFloat = 600
    public var letterSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var justify: Bool = true

    public override var isFlipped: Bool { true }

    /// Cumulative 段距 contributed by every paragraph that ended above `index`.
    func paragraphGapBefore(_ index: Int) -> CGFloat {
        guard paragraphSpacing > 0, index > 0 else { return 0 }
        let ended = isParagraphEnd.prefix(index).filter { $0 }.count
        return CGFloat(ended) * paragraphSpacing
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, !lines.isEmpty else { return }

        let ctFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        let effectiveLineHeight = fontSize * 1.25 + lineSpacing
        let targetWidth = Double(max(100, containerWidth))

        for (index, lineText) in lines.enumerated() {
            guard !lineText.isEmpty else { continue }
            var attrs: [CFString: Any] = [
                kCTFontAttributeName: ctFont,
                kCTForegroundColorAttributeName: textColor.cgColor
            ]
            if letterSpacing != 0 { attrs[kCTKernAttributeName] = letterSpacing }
            guard let attrStr = CFAttributedStringCreate(nil, lineText as CFString, attrs as CFDictionary) else { continue }
            let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
            let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: lineText.count))

            let isEnd = (index < isParagraphEnd.count) ? isParagraphEnd[index] : false
            let finalLine: CTLine
            if justify && !isEnd && lineText.count > 5 {
                finalLine = CTLineCreateJustifiedLine(ctLine, 1.0, targetWidth) ?? ctLine
            } else {
                finalLine = ctLine
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(finalLine, &ascent, &descent, &leading)

            let baselineY = CGFloat(index) * effectiveLineHeight + paragraphGapBefore(index) + ascent

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: baselineY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(finalLine, ctx)
            ctx.restoreGState()
        }
    }
}
#endif

#if os(iOS)
import UIKit

public struct CoreTextPageView: UIViewRepresentable {
    public let lines: [String]
    public let isParagraphEnd: [Bool]
    public let fontSize: CGFloat
    public let lineSpacing: CGFloat
    public let textColor: Color
    public let width: CGFloat
    public let height: CGFloat
    public var letterSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var justify: Bool = true

    public func makeUIView(context: Context) -> CoreTextUIView {
        let view = CoreTextUIView()
        updateUIView(view, context: context)
        return view
    }

    public func updateUIView(_ uiView: CoreTextUIView, context: Context) {
        uiView.lines = lines
        uiView.isParagraphEnd = isParagraphEnd
        uiView.fontSize = fontSize
        uiView.lineSpacing = lineSpacing
        uiView.textColor = UIColor(textColor)
        uiView.containerWidth = width
        uiView.containerHeight = height
        uiView.letterSpacing = letterSpacing
        uiView.paragraphSpacing = paragraphSpacing
        uiView.justify = justify
        uiView.backgroundColor = .clear
        uiView.setNeedsDisplay()
    }
}

public class CoreTextUIView: UIView {
    public var lines: [String] = []
    public var isParagraphEnd: [Bool] = []
    public var fontSize: CGFloat = 18
    public var lineSpacing: CGFloat = 6
    public var textColor: UIColor = .label
    public var containerWidth: CGFloat = 340
    public var containerHeight: CGFloat = 600
    public var letterSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var justify: Bool = true

    /// Cumulative 段距 contributed by every paragraph that ended above `index`.
    func paragraphGapBefore(_ index: Int) -> CGFloat {
        guard paragraphSpacing > 0, index > 0 else { return 0 }
        let ended = isParagraphEnd.prefix(index).filter { $0 }.count
        return CGFloat(ended) * paragraphSpacing
    }

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !lines.isEmpty else { return }

        let ctFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        let effectiveLineHeight = fontSize * 1.25 + lineSpacing
        let targetWidth = Double(max(100, containerWidth))

        for (index, lineText) in lines.enumerated() {
            guard !lineText.isEmpty else { continue }
            var attrs: [CFString: Any] = [
                kCTFontAttributeName: ctFont,
                kCTForegroundColorAttributeName: textColor.cgColor
            ]
            if letterSpacing != 0 { attrs[kCTKernAttributeName] = letterSpacing }
            guard let attrStr = CFAttributedStringCreate(nil, lineText as CFString, attrs as CFDictionary) else { continue }
            let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
            let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: lineText.count))

            let isEnd = (index < isParagraphEnd.count) ? isParagraphEnd[index] : false
            let finalLine: CTLine
            if justify && !isEnd && lineText.count > 5 {
                finalLine = CTLineCreateJustifiedLine(ctLine, 1.0, targetWidth) ?? ctLine
            } else {
                finalLine = ctLine
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(finalLine, &ascent, &descent, &leading)

            let baselineY = CGFloat(index) * effectiveLineHeight + paragraphGapBefore(index) + ascent

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: baselineY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(finalLine, ctx)
            ctx.restoreGState()
        }
    }
}
#endif

// MARK: - ChapterRangeDownloadSheet (Android menu_download / CacheBook Counterpart)

public struct ChapterRangeDownloadSheet: View {
    let book: Book
    let chapters: [BookChapter]
    let source: BookSource?
    let currentChapterIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var startChapter: Int
    @State private var endChapter: Int
    @State private var isDownloading: Bool = false
    @State private var progressText: String = ""
    @State private var currentDownloaded: Int = 0
    @State private var totalToDownload: Int = 0
    @State private var resultSummary: String? = nil
    @State private var downloadTask: Task<Void, Never>? = nil

    public init(book: Book, chapters: [BookChapter], source: BookSource?, currentChapterIndex: Int) {
        self.book = book
        self.chapters = chapters
        self.source = source
        self.currentChapterIndex = currentChapterIndex
        let start = min(currentChapterIndex, max(0, chapters.count - 1))
        let end = min(start + 50, max(0, chapters.count - 1))
        self._startChapter = State(initialValue: start)
        self._endChapter = State(initialValue: end)
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("选择下载范围 (共 \(chapters.count) 章)")) {
                    HStack {
                        Text("起始章节")
                        Spacer()
                        Text("第 \(startChapter + 1) 章")
                            .foregroundColor(.secondary)
                    }
                    if chapters.count > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(startChapter) },
                                set: {
                                    let val = Int($0.rounded())
                                    startChapter = min(val, endChapter)
                                }
                            ),
                            in: 0...Double(max(1, chapters.count - 1)),
                            step: 1
                        )
                    }

                    HStack {
                        Text("结束章节")
                        Spacer()
                        Text("第 \(endChapter + 1) 章")
                            .foregroundColor(.secondary)
                    }
                    if chapters.count > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(endChapter) },
                                set: {
                                    let val = Int($0.rounded())
                                    endChapter = max(val, startChapter)
                                }
                            ),
                            in: 0...Double(max(1, chapters.count - 1)),
                            step: 1
                        )
                    }

                    HStack(spacing: 8) {
                        presetButton(title: "后续 50 章", delta: 50)
                        presetButton(title: "后续 100 章", delta: 100)
                        Button("全部下载") {
                            startChapter = 0
                            endChapter = max(0, chapters.count - 1)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                if isDownloading {
                    Section(header: Text("下载进度")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(currentDownloaded), total: Double(max(1, totalToDownload)))
                            Text(progressText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let summary = resultSummary {
                    Section(header: Text("下载结果")) {
                        Text(summary)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }

                Section {
                    Button(isDownloading ? "停止下载" : "开始下载 (\(endChapter - startChapter + 1) 章)") {
                        if isDownloading {
                            stopDownload()
                        } else {
                            startDownload()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(isDownloading ? .orange : .accentColor)
                    .font(.headline)
                }
            }
            .navigationTitle("离线缓存章节")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        stopDownload()
                        dismiss()
                    }
                }
            }
        }
    }

    private func presetButton(title: String, delta: Int) -> some View {
        Button(title) {
            startChapter = currentChapterIndex
            endChapter = min(currentChapterIndex + delta, max(0, chapters.count - 1))
        }
        .font(.caption)
    }

    private func stopDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }

    private func startDownload() {
        guard !chapters.isEmpty else { return }
        isDownloading = true
        resultSummary = nil
        currentDownloaded = 0
        totalToDownload = endChapter - startChapter + 1
        progressText = "准备开始下载..."

        downloadTask = Task {
            let res = await BookContentService.shared.downloadChaptersRange(
                book: book,
                chapters: chapters,
                source: source,
                startIndex: startChapter,
                endIndex: endChapter,
                onProgress: { cur, tot in
                    Task { @MainActor in
                        self.currentDownloaded = cur
                        self.totalToDownload = tot
                        self.progressText = "正在下载 (\(cur)/\(tot))..."
                    }
                }
            )
            await MainActor.run {
                self.isDownloading = false
                self.resultSummary = "下载完成：新增缓存 \(res.successCount) 章，已缓存跳过 \(res.skippedCount) 章" + (res.failedCount > 0 ? "，失败 \(res.failedCount) 章" : "")
            }
        }
    }
}

// MARK: - DictResultPopupView (Word lookup Sheet)

struct DictResultPopupView: View {
    let word: String
    @State private var definition: String? = nil
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(word)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Text("正在查询字典...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if let def = definition {
                ScrollView {
                    Text(def)
                        .font(.subheadline)
                        .lineSpacing(5)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                Text("未查询到释义")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("词典查词")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            fetchDefinition()
        }
    }

    private func fetchDefinition() {
        let rules = DictRuleStore.load().filter { $0.enabled }
        guard let r = rules.first else {
            isLoading = false
            definition = "未启用任何字典规则"
            return
        }
        let rendered = r.urlRule.replacingOccurrences(of: "{{key}}", with: word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)
        Task {
            do {
                guard let parsed = NetworkClient.parseLegadoUrl(rendered) else {
                    await MainActor.run {
                        isLoading = false
                        definition = "无效的字典请求"
                    }
                    return
                }
                let resp = try await NetworkClient.shared.request(parsed: parsed)
                let body = resp.bodyString
                let result: String
                if !r.showRule.isEmpty {
                    let a = RuleAnalyzer(content: body, baseUrl: rendered)
                    result = a.getString(r.showRule)
                } else {
                    result = BookContentService.cleanHtml(body)
                }
                await MainActor.run {
                    isLoading = false
                    definition = result.isEmpty ? "未找到关于 “\(word)” 的释义" : result
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    definition = "查询异常: \(error.localizedDescription)"
                }
            }
        }
    }
}

extension String: Identifiable {
    public var id: String { self }
}

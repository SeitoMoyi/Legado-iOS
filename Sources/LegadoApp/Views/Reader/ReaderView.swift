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
    public var blocks: [ContentBlock]
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
    @State private var isLoadingNextChapter: Bool = false
    @State private var scrollSessionId: UUID = UUID()
    @State private var scrollToChapterId: String? = nil
    @State private var errorMessage: String? = nil
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
        case .editContent, .syncProgress:
            // Enabled by P0-3 / P0-6; the zones are selectable now so the layout work does
            // not have to be redone later.
            break
        }
    }

    private func jumpChapter(by delta: Int) {
        let target = currentChapterIndex + delta
        guard target >= 0, target < chapters.count else { return }
        audioService.stop()
        currentChapterIndex = target
        currentPageIndex = 0
        loadInitialChapter(at: target)
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

                volumeKeyLayer

                controlsLayer

                panelLayer(maxHeight: outerGeo.size.height)
            }
            .onAppear {
                let readingHeight = max(200, outerGeo.size.height - 26)
                updateContainerSizeIfNeeded(CGSize(width: outerGeo.size.width, height: readingHeight))
                applyIdleTimerPreference()
                wireAudioService()
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
        .statusBar(hidden: readerConfig.prefs.hideStatusBar || !(showControls || panel != .none))
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
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") {
                loadInitialChapter(at: currentChapterIndex)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    /// Volume keys as page turns. Disabled while a panel is open, matching Android's
    /// `if (menuLayoutIsVisible) return super.onKeyDown(...)`.
    private var volumeKeyLayer: some View {
        VolumeKeyObserver(isEnabled: readerConfig.prefs.volumeKeyPage && panel == .none,
                          ignoreWhilePlaying: !readerConfig.prefs.volumeKeyPageOnPlay,
                          isPlaying: audioService.isPlaying,
                          continuousWhilePressed: readerConfig.prefs.keyPageOnLongPress) { forward in
            turnPage(forward: forward)
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
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    GeometryReader { probeGeo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: probeGeo.frame(in: .named("readerScrollCoordinate")).minY
                        )
                    }
                    .frame(height: 0)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(loadedChapters) { loadedCh in
                            VStack(alignment: .leading, spacing: readerConfig.lineSpacing) {
                                // Chapter Title
                                Text(loadedCh.chapter.title)
                                    .font(.system(size: readerConfig.fontSize + 4, weight: .bold))
                                    .foregroundColor(readerConfig.theme.textColor)
                                    .padding(.horizontal, readerConfig.paddingLeading)
                                    .padding(.top, readerConfig.paddingTop)
                                    .padding(.bottom, 10)
                                    .id("chapter_\(loadedCh.chapter.index)")
                                    .onAppear {
                                        if currentChapterIndex != loadedCh.chapter.index {
                                            currentChapterIndex = loadedCh.chapter.index
                                            BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: currentChapterIndex, chapterTitle: loadedCh.chapter.title, chapterPos: currentChapterCharOffset())
                                            preCacheNeighbors(around: currentChapterIndex)
                                        }
                                    }

                                // Chapter Paragraphs and Images
                                ForEach(loadedCh.blocks) { block in
                                    if block.isImage, let urlStr = block.imageUrl {
                                        ChapterImageView(urlString: urlStr, referer: effectiveSource?.bookSourceUrl)
                                            .padding(.horizontal, 20)
                                            .id("block_\(loadedCh.chapter.index)_\(block.id)")
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear
                                                        .preference(
                                                            key: ReaderScrollPreferenceKey.self,
                                                            value: [BlockFrameInfo(
                                                                chapterIndex: loadedCh.chapter.index,
                                                                blockId: block.id,
                                                                minY: geo.frame(in: .named("readerScrollCoordinate")).minY,
                                                                maxY: geo.frame(in: .named("readerScrollCoordinate")).maxY
                                                            )]
                                                        )
                                                }
                                            )
                                    } else {
                                        Text(block.text)
                                            .font(.system(size: readerConfig.fontSize))
                                            .lineSpacing(readerConfig.lineSpacing)
                                            .kerningWhenAvailable(readerConfig.letterSpacing)
                                            .foregroundColor(readerConfig.theme.textColor)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, readerConfig.lineSpacing / 3)
                                            .id("block_\(loadedCh.chapter.index)_\(block.id)")
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear
                                                        .preference(
                                                            key: ReaderScrollPreferenceKey.self,
                                                            value: [BlockFrameInfo(
                                                                chapterIndex: loadedCh.chapter.index,
                                                                blockId: block.id,
                                                                minY: geo.frame(in: .named("readerScrollCoordinate")).minY,
                                                                maxY: geo.frame(in: .named("readerScrollCoordinate")).maxY
                                                            )]
                                                        )
                                                }
                                            )
                                    }
                                }

                                // Empty space between chapters (pure blank space, no lines or text prompts)
                                Color.clear
                                    .frame(height: 64)
                                    .id("chapter_end_\(loadedCh.chapter.index)")
                                    .onAppear {
                                        if loadedCh.chapter.index < chapters.count - 1 {
                                            loadNextChapterForInfiniteScroll(after: loadedCh.chapter.index)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "readerScrollCoordinate")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { minY in
                let scrollY = -minY
                handleScrollOffsetChanged(scrollY: scrollY)
            }
            .onPreferenceChange(ReaderScrollPreferenceKey.self) { frames in
                handleBlockFramesChanged(frames)
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification)) { notification in
                guard readerConfig.pageMode == .scroll else { return }
                if let clipView = notification.object as? NSClipView {
                    let scrollY = clipView.documentVisibleRect.origin.y
                    handleScrollOffsetChanged(scrollY: scrollY)
                }
            }
            #endif
            .id(scrollSessionId)
            .refreshable {
                if let first = loadedChapters.first, first.chapter.index > 0 {
                    let prevIndex = first.chapter.index - 1
                    if let prevLoaded = await getOrFetchChapter(at: prevIndex) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            loadedChapters.insert(prevLoaded, at: 0)
                            currentChapterIndex = prevIndex
                            scrollToChapterId = "chapter_end_\(prevIndex)"
                        }
                        BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: prevIndex, chapterTitle: prevLoaded.chapter.title)
                        preCacheNeighbors(around: prevIndex)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // A nine-zone overlay would steal the touches the ScrollView needs, so
                // scrolling honours the configured centre action only.
                handleTapAction(scrollTapAction)
            }
            .onAppear {
                if let target = scrollToChapterId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        let anchor: UnitPoint = target.hasPrefix("chapter_end") ? .center : .top
                        proxy.scrollTo(target, anchor: anchor)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            proxy.scrollTo(target, anchor: anchor)
                            scrollToChapterId = nil
                        }
                    }
                }
            }
            .onChange(of: scrollToChapterId) { target in
                if let target = target {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        let anchor: UnitPoint = target.hasPrefix("chapter_end") ? .center : .top
                        proxy.scrollTo(target, anchor: anchor)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            proxy.scrollTo(target, anchor: anchor)
                            scrollToChapterId = nil
                        }
                    }
                }
            }
        }
    }

    private func handleBlockFramesChanged(_ frames: [BlockFrameInfo]) {
        guard !frames.isEmpty else { return }
        if let active = frames.first(where: { $0.minY <= 140 && $0.maxY >= 20 }) ??
                        frames.min(by: { abs($0.minY - 50) < abs($1.minY - 50) }) {
            if self.currentChapterIndex != active.chapterIndex {
                self.currentChapterIndex = active.chapterIndex
                self.preCacheNeighbors(around: active.chapterIndex)
            }
            self.currentReadingBlockId = active.blockId
        }
    }

    private func handleScrollOffsetChanged(scrollY: CGFloat) {
        guard scrollY > 0, !loadedChapters.isEmpty else { return }
        let width = max(240, readerContainerSize.width)
        let usableWidth = max(200, width - 40)
        let charsPerLine = max(10, Int(usableWidth / readerConfig.fontSize))
        let lineHeight = readerConfig.fontSize * 1.25 + readerConfig.lineSpacing
        let titleHeight = (readerConfig.fontSize + 4) * 1.3 + 30.0

        let targetY = scrollY + 60.0
        var currentY: CGFloat = 0

        for loadedCh in loadedChapters {
            currentY += titleHeight

            for block in loadedCh.blocks {
                let blockH: CGFloat
                if block.isImage {
                    blockH = 260.0
                } else {
                    let lines = max(1, Int(ceil(Double(block.text.count) / Double(charsPerLine))))
                    blockH = CGFloat(lines) * lineHeight + (readerConfig.lineSpacing * 2.0 / 3.0)
                }

                if targetY >= currentY && targetY < currentY + blockH {
                    if self.currentChapterIndex != loadedCh.chapter.index {
                        self.currentChapterIndex = loadedCh.chapter.index
                        self.preCacheNeighbors(around: loadedCh.chapter.index)
                    }
                    self.currentReadingBlockId = block.id
                    return
                }
                currentY += blockH
            }

            currentY += 64.0
            if targetY < currentY {
                if self.currentChapterIndex != loadedCh.chapter.index {
                    self.currentChapterIndex = loadedCh.chapter.index
                }
                return
            }
        }
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
                            Text(cur.chapter.title)
                                .font(.system(size: readerConfig.fontSize + 3, weight: .bold))
                                .foregroundColor(readerConfig.theme.textColor)
                                .padding(.bottom, 8)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Page Content
                        if pageBlocks.first?.isImage == true, let urlStr = pageBlocks.first?.imageUrl {
                            ChapterImageView(urlString: urlStr, referer: effectiveSource?.bookSourceUrl)
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
            Button(action: {
                audioService.stop()
                if let onDismiss = onDismiss {
                    onDismiss()
                }
                dismiss()
            }) {
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
            .frame(maxWidth: 240)

            Spacer()

            // Overflow menu. Android puts 换源/刷新/离线缓存 on the bar itself; those
            // arrive with the cache export, so the menu starts with what works today.
            HStack(spacing: 14) {
                Menu {
                    Section("书签") {
                        Button("添加书签", action: addBookmark)
                        Button("书签 (\(BookStore.shared.bookmarks(for: book).count))") { showBookmarks = true }
                    }

                    Section("正文") {
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

                    Section("本章") {
                        Button("刷新本章") { reloadCurrentChapter() }
                        Button("更新目录") { Task { await loadTOCAndStart() } }
                        Button("清理本书缓存") { clearBookCache() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                }
            }
            .foregroundColor(readerConfig.theme.textColor)
            .frame(width: 96, alignment: .trailing)
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
        HStack(spacing: 14) {
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

            if chapters.count > 1 {
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

        if readerConfig.pageMode == .scroll {
            if loadedChapters.contains(where: { $0.chapter.index == prevIndex }) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollToChapterId = "chapter_end_\(prevIndex)"
                }
            } else if let first = loadedChapters.first, first.chapter.index == currentChapterIndex {
                Task {
                    if let prevLoaded = await getOrFetchChapter(at: prevIndex) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.loadedChapters.insert(prevLoaded, at: 0)
                            self.currentChapterIndex = prevIndex
                            self.scrollToChapterId = "chapter_end_\(prevIndex)"
                        }
                        BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: prevIndex, chapterTitle: prevLoaded.chapter.title)
                        self.preCacheNeighbors(around: prevIndex)
                    }
                }
            } else {
                jumpToChapter(prevIndex, toEnd: true)
            }
        } else {
            jumpToChapter(prevIndex, toEnd: true)
        }
    }

    private func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        let nextIndex = currentChapterIndex + 1

        if readerConfig.pageMode == .scroll {
            if loadedChapters.contains(where: { $0.chapter.index == nextIndex }) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollToChapterId = "chapter_\(nextIndex)"
                }
            } else {
                jumpToChapter(nextIndex, toEnd: false)
            }
        } else {
            jumpToChapter(nextIndex, toEnd: false)
        }
    }

    private func jumpToChapter(_ targetIndex: Int, toEnd: Bool = false) {
        guard targetIndex >= 0 && targetIndex < chapters.count else { return }
        audioService.stop()
        currentChapterIndex = targetIndex
        currentPageIndex = 0
        currentReadingBlockId = 0
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
            scrollSessionId = UUID()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                scrollToChapterId = "block_\(currentChapterIndex)_\(targetBlockId)"
            }
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
            List(chapters) { ch in
                Button(action: {
                    showTOC = false
                    jumpToChapter(ch.index)
                }) {
                    HStack {
                        Text(ch.title)
                            .foregroundColor(ch.index == currentChapterIndex ? .accentColor : .primary)
                        Spacer()
                        if ch.index == currentChapterIndex {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("目录 (\(chapters.count)章)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { showTOC = false }
                }
            }
        }
    }

    // MARK: - Data Loading Pipeline
    private func loadTOCAndStart() async {
        if book.origin == "local" {
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

        guard let source = effectiveSource else {
            errorMessage = "未找到书籍关联的书源"
            isLoadingInitial = false
            return
        }

        do {
            var fetchedChapters = try await BookContentService.shared.fetchChapterList(book: book, source: source)
            for i in 0..<fetchedChapters.count {
                fetchedChapters[i].index = i
            }
            guard !fetchedChapters.isEmpty else {
                if await tryAutoChangeSource() { return }
                self.errorMessage = "目录为空"
                self.isLoadingInitial = false
                return
            }
            self.chapters = fetchedChapters
            if currentChapterIndex >= fetchedChapters.count {
                currentChapterIndex = max(0, fetchedChapters.count - 1)
            }
            loadInitialChapter(at: currentChapterIndex)
        } catch {
            if await tryAutoChangeSource() { return }
            self.errorMessage = "目录解析失败: \(error.localizedDescription)"
            self.isLoadingInitial = false
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
            let blocks = parseContentBlocks(from: content)
            let pages = paginate(blocks: blocks)
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               await tryAutoChangeSource() {
                return nil
            }
            let loaded = LoadedChapter(chapter: targetChapter, content: content, blocks: blocks, pages: pages)
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
                    let blocks = parseContentBlocks(from: content)
                    let pages = paginate(blocks: blocks)
                    let loaded = LoadedChapter(chapter: prevCh, content: content, blocks: blocks, pages: pages)
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
                    let blocks = parseContentBlocks(from: content)
                    let pages = paginate(blocks: blocks)
                    let loaded = LoadedChapter(chapter: nextCh, content: content, blocks: blocks, pages: pages)
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
                    let blocks = parseContentBlocks(from: content)
                    let pages = paginate(blocks: blocks)
                    loaded = LoadedChapter(chapter: currentChapter, content: content, blocks: blocks, pages: pages)
                    self.chapterCache[index] = loaded
                }

                self.currentChapterIndex = index

                let restorePos = targetCharPos
                    ?? (index == self.book.durChapterIndex ? self.book.durChapterPos : 0)

                // Restore position if durChapterPos is saved and opening the current chapter
                if targetPageIndex == 0 && restorePos > 0 {
                    if self.readerConfig.pageMode == .pageByPage {
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
                    } else {
                        var accumulated = 0
                        var targetBlock = loaded.blocks.first?.id ?? 0
                        for block in loaded.blocks {
                            if accumulated + block.text.count > restorePos {
                                targetBlock = block.id
                                break
                            }
                            accumulated += block.text.count
                            targetBlock = block.id
                        }
                        self.currentReadingBlockId = targetBlock
                        self.scrollToChapterId = "block_\(index)_\(targetBlock)"
                    }
                } else if targetPageIndex == -1 {
                    self.currentPageIndex = max(0, loaded.pages.count - 1)
                } else {
                    self.currentPageIndex = min(targetPageIndex, max(0, loaded.pages.count - 1))
                }

                if self.currentPageIndex < loaded.pages.count {
                    self.currentReadingBlockId = loaded.pages[self.currentPageIndex].first?.id ?? 0
                }

                // If jumping to end in continuous scroll, also attach the next chapter right below it if available!
                if readerConfig.pageMode == .scroll && scrollToTargetEnd && index < self.chapters.count - 1 {
                    let nextIndex = index + 1
                    if let nextCached = self.chapterCache[nextIndex] {
                        self.loadedChapters = [loaded, nextCached]
                    } else {
                        self.loadedChapters = [loaded]
                        Task {
                            if let nextLoaded = await self.getOrFetchChapter(at: nextIndex) {
                                if !self.loadedChapters.contains(where: { $0.chapter.index == nextIndex }) {
                                    self.loadedChapters.append(nextLoaded)
                                }
                            }
                        }
                    }
                } else {
                    self.loadedChapters = [loaded]
                }

                self.isLoadingInitial = false
                let currentPos = self.currentChapterCharOffset()
                BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: index, chapterTitle: currentChapter.title, chapterPos: currentPos)
                self.preCacheNeighbors(around: index)

                if readerConfig.pageMode == .scroll && self.scrollToChapterId == nil {
                    self.scrollToChapterId = scrollToTargetEnd ? "chapter_end_\(index)" : "chapter_\(index)"
                }
            } catch {
                self.errorMessage = "正文解析失败: \(error.localizedDescription)"
                self.isLoadingInitial = false
            }
        }
    }

    private func loadNextChapterForInfiniteScroll(after index: Int) {
        let nextIndex = index + 1
        guard nextIndex < chapters.count else { return }
        if loadedChapters.contains(where: { $0.chapter.index == nextIndex }) || isLoadingNextChapter {
            return
        }

        if let cached = chapterCache[nextIndex] {
            self.loadedChapters.append(cached)
            self.preCacheNeighbors(around: nextIndex)
            return
        }

        let nextChapter = chapters[nextIndex]
        let nextStopUrl = nextChapterUrl(after: nextIndex)
        let nextContext = processContext(for: nextChapter)
        isLoadingNextChapter = true
        let source = effectiveSource

        Task { @MainActor in
            do {
                let content = try await BookContentService.shared.fetchChapterContent(
                    chapter: nextChapter, source: source,
                    nextChapterUrl: nextStopUrl, context: nextContext)
                let blocks = parseContentBlocks(from: content)
                let pages = paginate(blocks: blocks)
                let loaded = LoadedChapter(chapter: nextChapter, content: content, blocks: blocks, pages: pages)

                self.loadedChapters.append(loaded)
                self.chapterCache[nextIndex] = loaded
                self.isLoadingNextChapter = false
                self.preCacheNeighbors(around: nextIndex)
            } catch {
                print("[ReaderView] ⚠️ Failed to preload chapter \(nextIndex): \(error)")
                self.isLoadingNextChapter = false
            }
        }
    }

    private func recomputePagination() {
        let charPos = currentChapterCharOffset()

        for i in 0..<loadedChapters.count {
            loadedChapters[i].pages = paginate(blocks: loadedChapters[i].blocks)
        }

        if let cur = currentLoadedChapter, !cur.pages.isEmpty {
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
                            blocks.append(ContentBlock(id: currentId, isImage: true, text: "", imageUrl: imgUrl))
                            currentId += 1
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
            var offset = 0
            let limit = min(currentPageIndex, cur.pages.count)
            for p in 0..<limit {
                for block in cur.pages[p] {
                    offset += block.text.count
                }
            }
            return offset
        } else {
            var offset = 0
            for block in cur.blocks {
                if block.id == currentReadingBlockId {
                    break
                }
                offset += block.text.count
            }
            return offset
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
            audioService.load(chapterText: loaded.content,
                              startCharPos: readerConfig.prefs.readAloudByPage ? 0 : 0)
            preCacheNeighbors(around: target)
        }
    }

    private func toggleAloud() {
        configureAudioContext()
        if audioService.isActive {
            audioService.togglePlayPause()
        } else {
            audioService.load(chapterText: currentChapterContent)
        }
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
    private func calculateLayoutMetrics() -> (lineHeight: CGFloat, pageHeight: CGFloat, firstPageHeight: CGFloat) {
        let height = max(400, readerContainerSize.height)

        let lineHeight = readerConfig.fontSize * 1.25 + readerConfig.lineSpacing
        let usableHeight = max(200, height - readerConfig.paddingTop - readerConfig.paddingBottom)

        // First page has chapter title (+ title padding)
        let titleLineHeight = (readerConfig.fontSize + 3) * 1.3 + readerConfig.lineSpacing
        let titleHeight = titleLineHeight * 1.5 + 16.0

        return (lineHeight: lineHeight,
                pageHeight: usableHeight,
                firstPageHeight: max(100, usableHeight - titleHeight))
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

    private func paginate(blocks: [ContentBlock]) -> [[ContentBlock]] {
        let metrics = calculateLayoutMetrics()
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
    @State private var searchScope: Int = 0 // 0: 本章内容, 1: 目录章节

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

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("搜索范围", selection: $searchScope) {
                    Text("当前章节正文").tag(0)
                    Text("目录章节搜索").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if searchText.isEmpty {
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


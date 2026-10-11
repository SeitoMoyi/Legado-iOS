import SwiftUI
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

public struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var readerConfig = ReaderConfig.shared
    @StateObject private var audioService = AudioBookService.shared

    let book: Book
    let source: BookSource?

    private var effectiveSource: BookSource? {
        source ?? BookStore.shared.findSource(for: book)
    }

    @State private var chapters: [BookChapter] = []
    @State private var currentChapterIndex: Int = 0
    @State private var loadedChapters: [LoadedChapter] = []
    @State private var currentPageIndex: Int = 0

    @State private var isLoadingInitial: Bool = true
    @State private var isLoadingNextChapter: Bool = false
    @State private var isLoadingPrevChapter: Bool = false
    @State private var scrollToChapterId: String? = nil
    @State private var errorMessage: String? = nil

    @State private var showTOC: Bool = false
    @State private var showSettings: Bool = false
    @State private var showSearch: Bool = false
    @State private var showControls: Bool = false

    public init(book: Book, source: BookSource?, initialChapterIndex: Int? = nil) {
        self.book = book
        self.source = source
        self._currentChapterIndex = State(initialValue: initialChapterIndex ?? book.durChapterIndex)
    }

    private var currentLoadedChapter: LoadedChapter? {
        loadedChapters.first(where: { $0.chapter.index == currentChapterIndex }) ?? loadedChapters.first
    }

    private var currentChapterContent: String {
        currentLoadedChapter?.content ?? ""
    }

    public var body: some View {
        ZStack {
            readerConfig.theme.backgroundColor
                .ignoresSafeArea()

            // 1. Reading Canvas + Permanent Fixed Bottom Status Bar
            VStack(spacing: 0) {
                // Main Reader Body
                if isLoadingInitial {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("正在加载章节内容...")
                            .font(.subheadline)
                            .foregroundColor(readerConfig.theme.textColor.opacity(0.7))
                    }
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
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
                    }
                    Spacer()
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

                // Fixed Permanent Status Bar (Always Visible at bottom of reading face)
                fixedBottomStatusBar
            }

            // 2. Dismiss Backdrop (when controls are open, tapping anywhere outside bars dismisses them)
            if showControls {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showControls = false
                        }
                    }
                    .ignoresSafeArea()
            }

            // 3. Top Navigation Bar Overlay (Sliding down from top)
            if showControls {
                VStack(spacing: 0) {
                    topNavigationBar
                    Spacer()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            // 4. Bottom Control Panel Overlay (Sliding up from bottom)
            if showControls {
                VStack(spacing: 0) {
                    Spacer()
                    bottomControlPanel
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        .statusBar(hidden: !showControls)
        #endif
        .sheet(isPresented: $showTOC) {
            tocSheet
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showSearch) {
            searchSheet
        }
        .task {
            await loadTOCAndStart()
        }
        .onDisappear {
            audioService.stop()
        }
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

            // Reading Percentage vs Whole Book
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
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(height: 22)
        .background(readerConfig.theme.backgroundColor.opacity(0.96))
    }

    // MARK: - Mode 1: Infinite Scroll Down (连续滚动)
    // MARK: - Mode 1: Infinite Scroll Down (连续滚动)
    private var infiniteScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Previous Chapter Trigger / Header (Top of list)
                    if let firstLoaded = loadedChapters.first, firstLoaded.chapter.index > 0 {
                        VStack(spacing: 8) {
                            if isLoadingPrevChapter {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("正在加载上一章: \(chapters[firstLoaded.chapter.index - 1].title)...")
                                        .font(.caption)
                                        .foregroundColor(readerConfig.theme.textColor.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            } else {
                                Button(action: {
                                    loadPreviousChapterForInfiniteScroll(before: firstLoaded.chapter.index)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.circle")
                                            .font(.system(size: 13))
                                        Text("上滑或轻点加载上一章 · \(chapters[firstLoaded.chapter.index - 1].title)")
                                            .font(.system(size: 12))
                                    }
                                    .foregroundColor(readerConfig.theme.textColor.opacity(0.55))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                }
                                .onAppear {
                                    loadPreviousChapterForInfiniteScroll(before: firstLoaded.chapter.index)
                                }
                            }

                            Rectangle()
                                .fill(readerConfig.theme.textColor.opacity(0.12))
                                .frame(height: 1)
                                .padding(.horizontal, 50)
                        }
                        .id("top_prev_loader")
                    }

                    ForEach(loadedChapters) { loadedCh in
                        VStack(alignment: .leading, spacing: readerConfig.lineSpacing) {
                            // Chapter Title
                            Text(loadedCh.chapter.title)
                                .font(.system(size: readerConfig.fontSize + 4, weight: .bold))
                                .foregroundColor(readerConfig.theme.textColor)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 10)
                                .id("chapter_\(loadedCh.chapter.index)")
                                .onAppear {
                                    if scrollToChapterId == nil && currentChapterIndex != loadedCh.chapter.index {
                                        currentChapterIndex = loadedCh.chapter.index
                                        BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: currentChapterIndex, chapterTitle: loadedCh.chapter.title)
                                    }
                                }

                            // Chapter Paragraphs and Images
                            ForEach(loadedCh.blocks) { block in
                                if block.isImage, let urlStr = block.imageUrl {
                                    ChapterImageView(urlString: urlStr, referer: effectiveSource?.bookSourceUrl)
                                        .padding(.horizontal, 20)
                                } else {
                                    Text(block.text)
                                        .font(.system(size: readerConfig.fontSize))
                                        .lineSpacing(readerConfig.lineSpacing)
                                        .foregroundColor(readerConfig.theme.textColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, readerConfig.lineSpacing / 3)
                                }
                            }

                            // Empty space between chapters
                            if loadedCh.chapter.index < chapters.count - 1 {
                                VStack(spacing: 12) {
                                    Rectangle()
                                        .fill(readerConfig.theme.textColor.opacity(0.12))
                                        .frame(height: 1)
                                        .padding(.horizontal, 50)

                                    Text("第 \(loadedCh.chapter.index + 1) 章 完 · 下滑进入下一章")
                                        .font(.system(size: 12))
                                        .foregroundColor(readerConfig.theme.textColor.opacity(0.45))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 110) // Generous empty space divider between chapters
                                .onAppear {
                                    loadNextChapterForInfiniteScroll(after: loadedCh.chapter.index)
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Rectangle()
                                        .fill(readerConfig.theme.textColor.opacity(0.12))
                                        .frame(height: 1)
                                        .padding(.horizontal, 50)
                                    Text("全书完")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(readerConfig.theme.textColor.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                            }
                        }
                    }

                    if isLoadingNextChapter {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在加载下一章...")
                                .font(.caption)
                                .foregroundColor(readerConfig.theme.textColor.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
            }
            .onChange(of: scrollToChapterId) { newTarget in
                if let target = newTarget {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if scrollToChapterId == target {
                            scrollToChapterId = nil
                        }
                    }
                }
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
                    VStack(alignment: .leading, spacing: readerConfig.lineSpacing) {
                        // If it's page 0, display Chapter Title at top
                        if currentPageIndex == 0, let cur = currentLoadedChapter {
                            Text(cur.chapter.title)
                                .font(.system(size: readerConfig.fontSize + 3, weight: .bold))
                                .foregroundColor(readerConfig.theme.textColor)
                                .padding(.bottom, 8)
                        }

                        // Page Content
                        ForEach(pageBlocks) { block in
                            if block.isImage, let urlStr = block.imageUrl {
                                ChapterImageView(urlString: urlStr, referer: effectiveSource?.bookSourceUrl)
                            } else {
                                Text(block.text)
                                    .font(.system(size: readerConfig.fontSize))
                                    .lineSpacing(readerConfig.lineSpacing)
                                    .foregroundColor(readerConfig.theme.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, readerConfig.lineSpacing / 3)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .id("page_\(currentChapterIndex)_\(currentPageIndex)")
                }

                // Three-Zone Tap Controller & Drag Gesture
                HStack(spacing: 0) {
                    // Left 30%: Previous Page
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.3)
                        .onTapGesture {
                            turnPage(forward: false)
                        }

                    // Middle 40%: Toggle Controls
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.4)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }

                    // Right 30%: Next Page
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.3)
                        .onTapGesture {
                            turnPage(forward: true)
                        }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            turnPage(forward: true)
                        } else if value.translation.width > 40 {
                            turnPage(forward: false)
                        }
                    }
            )
        }
    }

    // MARK: - Page Turn Handler (Once chapter ends, next chapter starts next page)
    private func turnPage(forward: Bool) {
        guard let current = currentLoadedChapter else { return }
        let totalPages = current.pages.count

        if forward {
            if currentPageIndex < totalPages - 1 {
                withAnimation(.easeInOut(duration: 0.18)) {
                    currentPageIndex += 1
                }
            } else {
                // Chapter ended! Once one chapter ends, the new chapter starts the next page!
                if currentChapterIndex < chapters.count - 1 {
                    audioService.stop()
                    let nextIdx = currentChapterIndex + 1
                    currentChapterIndex = nextIdx
                    currentPageIndex = 0
                    loadInitialChapter(at: nextIdx, targetPageIndex: 0)
                }
            }
        } else {
            if currentPageIndex > 0 {
                withAnimation(.easeInOut(duration: 0.18)) {
                    currentPageIndex -= 1
                }
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

    // MARK: - Navigation Bars & Toolbars (Apple Books Layout)
    private var topNavigationBar: some View {
        HStack(alignment: .center) {
            // Exit button
            Button(action: {
                audioService.stop()
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

            // Title & Chapter Info in Center
            VStack(spacing: 2) {
                Text(book.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(readerConfig.theme.textColor)
                    .lineLimit(1)
                if !chapters.isEmpty && currentChapterIndex < chapters.count {
                    Text(chapters[currentChapterIndex].title)
                        .font(.system(size: 11))
                        .foregroundColor(readerConfig.theme.textColor.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 240)

            Spacer()

            // Balanced placeholder so center title remains perfectly centered
            Color.clear
                .frame(width: 54, height: 32)
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
        VStack(spacing: 14) {
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
        jumpToChapter(currentChapterIndex - 1)
    }

    private func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        jumpToChapter(currentChapterIndex + 1)
    }

    private func jumpToChapter(_ targetIndex: Int) {
        guard targetIndex >= 0 && targetIndex < chapters.count else { return }
        audioService.stop()
        currentChapterIndex = targetIndex
        currentPageIndex = 0

        if readerConfig.pageMode == .scroll {
            if loadedChapters.contains(where: { $0.chapter.index == targetIndex }) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollToChapterId = "chapter_\(targetIndex)"
                }
                BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: targetIndex, chapterTitle: chapters[targetIndex].title)
            } else {
                loadInitialChapter(at: targetIndex, targetPageIndex: 0, scrollToTarget: true)
            }
        } else {
            loadInitialChapter(at: targetIndex, targetPageIndex: 0)
        }
    }

    private var bottomActionRow: some View {
        HStack(spacing: 0) {
            // Contents Table (目录)
            Button(action: { showTOC = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                    Text("目录")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(readerConfig.theme.textColor)
                .frame(maxWidth: .infinity)
            }

            // Text Search (搜索)
            Button(action: { showSearch = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                    Text("搜索")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(readerConfig.theme.textColor)
                .frame(maxWidth: .infinity)
            }

            // TTS (听书)
            Button(action: {
                audioService.togglePlayPause(text: currentChapterContent)
            }) {
                VStack(spacing: 4) {
                    Image(systemName: audioService.isPlaying ? "pause.circle.fill" : (audioService.isPaused ? "play.circle.fill" : "headphones"))
                        .font(.system(size: 20))
                        .foregroundColor(audioService.isPlaying ? .accentColor : readerConfig.theme.textColor)
                    Text(audioService.isPlaying ? "暂停" : (audioService.isPaused ? "继续" : "听书"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(audioService.isPlaying ? .accentColor : readerConfig.theme.textColor)
                }
                .foregroundColor(readerConfig.theme.textColor)
                .frame(maxWidth: .infinity)
            }

            // Interface Settings (界面设置)
            Button(action: { showSettings = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 20))
                    Text("界面")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(readerConfig.theme.textColor)
                .frame(maxWidth: .infinity)
            }
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

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section("翻页模式") {
                    Picker("阅读模式", selection: $readerConfig.pageMode) {
                        ForEach(PageMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("字号设置") {
                    HStack {
                        Text("A-")
                            .font(.body)
                        Slider(value: $readerConfig.fontSize, in: 12...32, step: 1)
                            .onChange(of: readerConfig.fontSize) { _ in
                                recomputePagination()
                            }
                        Text("A+")
                            .font(.title3)
                        Text("\(Int(readerConfig.fontSize)) pt")
                            .foregroundColor(.secondary)
                    }
                }

                Section("阅读主题") {
                    Picker("背景颜色", selection: $readerConfig.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("阅读设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSettings = false }
                }
            }
        }
    }

    // MARK: - Data Loading Pipeline
    private func loadTOCAndStart() async {
        if book.origin == "local" {
            let localChapters = BookStore.shared.getChapters(for: book.bookUrl)
            if !localChapters.isEmpty {
                self.chapters = localChapters
                if currentChapterIndex >= localChapters.count {
                    currentChapterIndex = 0
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
            let fetchedChapters = try await BookContentService.shared.fetchChapterList(book: book, source: source)
            self.chapters = fetchedChapters
            if currentChapterIndex >= fetchedChapters.count {
                currentChapterIndex = 0
            }
            loadInitialChapter(at: currentChapterIndex)
        } catch {
            self.errorMessage = "目录解析失败: \(error.localizedDescription)"
            self.isLoadingInitial = false
        }
    }

    private func loadInitialChapter(at index: Int, targetPageIndex: Int = 0, scrollToTarget: Bool = false) {
        guard !chapters.isEmpty, index < chapters.count else { return }
        let currentChapter = chapters[index]
        if loadedChapters.isEmpty {
            isLoadingInitial = true
        }
        errorMessage = nil

        let source = effectiveSource

        Task { @MainActor in
            do {
                let content = try await BookContentService.shared.fetchChapterContent(chapter: currentChapter, source: source)
                let blocks = parseContentBlocks(from: content)
                let pages = paginate(blocks: blocks)
                let loaded = LoadedChapter(chapter: currentChapter, content: content, blocks: blocks, pages: pages)

                self.loadedChapters = [loaded]
                self.currentChapterIndex = index

                if targetPageIndex == -1 {
                    self.currentPageIndex = max(0, pages.count - 1)
                } else {
                    self.currentPageIndex = min(targetPageIndex, max(0, pages.count - 1))
                }

                self.isLoadingInitial = false
                BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: index, chapterTitle: currentChapter.title)

                if scrollToTarget || readerConfig.pageMode == .scroll {
                    self.scrollToChapterId = "chapter_\(index)"
                }
            } catch {
                self.errorMessage = "正文解析失败: \(error.localizedDescription)"
                self.isLoadingInitial = false
            }
        }
    }

    private func loadPreviousChapterForInfiniteScroll(before index: Int) {
        let prevIndex = index - 1
        guard prevIndex >= 0 else { return }
        if loadedChapters.contains(where: { $0.chapter.index == prevIndex }) || isLoadingPrevChapter {
            return
        }

        let prevChapter = chapters[prevIndex]
        isLoadingPrevChapter = true
        let source = effectiveSource

        Task { @MainActor in
            do {
                let content = try await BookContentService.shared.fetchChapterContent(chapter: prevChapter, source: source)
                let blocks = parseContentBlocks(from: content)
                let pages = paginate(blocks: blocks)
                let loaded = LoadedChapter(chapter: prevChapter, content: content, blocks: blocks, pages: pages)

                self.loadedChapters.insert(loaded, at: 0)
                self.isLoadingPrevChapter = false
            } catch {
                print("[ReaderView] ⚠️ Failed to load previous chapter \(prevIndex): \(error)")
                self.isLoadingPrevChapter = false
            }
        }
    }

    private func loadNextChapterForInfiniteScroll(after index: Int) {
        let nextIndex = index + 1
        guard nextIndex < chapters.count else { return }
        // If already loaded or currently loading, return
        if loadedChapters.contains(where: { $0.chapter.index == nextIndex }) || isLoadingNextChapter {
            return
        }

        let nextChapter = chapters[nextIndex]
        isLoadingNextChapter = true
        let source = effectiveSource

        Task { @MainActor in
            do {
                let content = try await BookContentService.shared.fetchChapterContent(chapter: nextChapter, source: source)
                let blocks = parseContentBlocks(from: content)
                let pages = paginate(blocks: blocks)
                let loaded = LoadedChapter(chapter: nextChapter, content: content, blocks: blocks, pages: pages)

                self.loadedChapters.append(loaded)
                self.isLoadingNextChapter = false
            } catch {
                print("[ReaderView] ⚠️ Failed to preload chapter \(nextIndex): \(error)")
                self.isLoadingNextChapter = false
            }
        }
    }

    private func recomputePagination() {
        for i in 0..<loadedChapters.count {
            loadedChapters[i].pages = paginate(blocks: loadedChapters[i].blocks)
        }
        if let cur = currentLoadedChapter {
            if currentPageIndex >= cur.pages.count {
                currentPageIndex = max(0, cur.pages.count - 1)
            }
        }
    }

    // MARK: - Paragraph and Page Parser
    private func parseContentBlocks(from text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentId = 0
        let regex = try? NSRegularExpression(pattern: "\\[image:(.*?)\\]")
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let regex = regex {
                let nsLine = trimmed as NSString
                let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsLine.length))
                if !matches.isEmpty {
                    var lastIndex = 0
                    for match in matches {
                        if match.range.location > lastIndex {
                            let textBefore = nsLine.substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex)).trimmingCharacters(in: .whitespaces)
                            if !textBefore.isEmpty {
                                let indent = (textBefore.hasPrefix("　") || textBefore.hasPrefix("    ")) ? "" : "　　"
                                blocks.append(ContentBlock(id: currentId, isImage: false, text: indent + textBefore, imageUrl: nil))
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
                        let textAfter = nsLine.substring(with: NSRange(location: lastIndex, length: nsLine.length - lastIndex)).trimmingCharacters(in: .whitespaces)
                        if !textAfter.isEmpty {
                            let indent = (textAfter.hasPrefix("　") || textAfter.hasPrefix("    ")) ? "" : "　　"
                            blocks.append(ContentBlock(id: currentId, isImage: false, text: indent + textAfter, imageUrl: nil))
                            currentId += 1
                        }
                    }
                    continue
                }
            }

            let indent = (trimmed.hasPrefix("　") || trimmed.hasPrefix("    ")) ? "" : "　　"
            blocks.append(ContentBlock(id: currentId, isImage: false, text: indent + trimmed, imageUrl: nil))
            currentId += 1
        }
        return blocks
    }

    private func paginate(blocks: [ContentBlock]) -> [[ContentBlock]] {
        let approxCharsPerPage = max(200, Int(7000 / readerConfig.fontSize))
        var pages: [[ContentBlock]] = []
        var currentPage: [ContentBlock] = []
        var currentCount = 0

        for block in blocks {
            if block.isImage {
                if currentCount > 120 {
                    pages.append(currentPage)
                    currentPage = []
                    currentCount = 0
                }
                currentPage.append(block)
                currentCount += 240
                if currentCount >= approxCharsPerPage {
                    pages.append(currentPage)
                    currentPage = []
                    currentCount = 0
                }
            } else {
                let count = block.text.count
                if currentCount > 0 && (currentCount + count > approxCharsPerPage) {
                    pages.append(currentPage)
                    currentPage = []
                    currentCount = 0
                }
                currentPage.append(block)
                currentCount += count
                if currentCount >= approxCharsPerPage {
                    pages.append(currentPage)
                    currentPage = []
                    currentCount = 0
                }
            }
        }
        if !currentPage.isEmpty {
            pages.append(currentPage)
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
                        Image(systemName: "photo.badge.exclamationmark")
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


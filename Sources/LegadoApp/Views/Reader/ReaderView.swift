import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

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
    @State private var chapterContent: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    @State private var showTOC: Bool = false
    @State private var showSettings: Bool = false

    @State private var showControls: Bool = true

    public init(book: Book, source: BookSource?, initialChapterIndex: Int? = nil) {
        self.book = book
        self.source = source
        self._currentChapterIndex = State(initialValue: initialChapterIndex ?? book.durChapterIndex)
    }

    public var body: some View {
        ZStack {
            readerConfig.theme.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showControls {
                    topNavigationBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isLoading {
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
                            loadCurrentChapter()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: readerConfig.lineSpacing) {
                            if !chapters.isEmpty && currentChapterIndex < chapters.count {
                                Text(chapters[currentChapterIndex].title)
                                    .font(.system(size: readerConfig.fontSize + 4, weight: .bold))
                                    .foregroundColor(readerConfig.theme.textColor)
                                    .padding(.bottom, 8)
                            }

                            ForEach(contentBlocks) { block in
                                if block.isImage, let urlStr = block.imageUrl {
                                    ChapterImageView(urlString: urlStr, referer: effectiveSource?.bookSourceUrl)
                                } else {
                                    Text(block.text)
                                        .font(.system(size: readerConfig.fontSize))
                                        .lineSpacing(readerConfig.lineSpacing)
                                        .foregroundColor(readerConfig.theme.textColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
                }

                if showControls {
                    bottomToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .task {
            await loadTOCAndChapter()
        }
        .onDisappear {
            audioService.stop()
        }
    }

    private var topNavigationBar: some View {
        HStack {
            Button(action: {
                audioService.stop()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(readerConfig.theme.textColor)
                    .frame(width: 44, height: 44, alignment: .leading)
            }

            Spacer()

            // TTS Play/Pause
            Button(action: {
                audioService.togglePlayPause(text: chapterContent)
            }) {
                Image(systemName: audioService.isPlaying ? "pause.circle.fill" : (audioService.isPaused ? "play.circle.fill" : "play.circle"))
                    .font(.system(size: 20))
                    .foregroundColor(readerConfig.theme.textColor)
                    .frame(width: 36, height: 44)
            }

            // Table of contents
            Button(action: { showTOC = true }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18))
                    .foregroundColor(readerConfig.theme.textColor)
                    .frame(width: 36, height: 44)
            }

            // Typography & Theme settings
            Button(action: { showSettings = true }) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 18))
                    .foregroundColor(readerConfig.theme.textColor)
                    .frame(width: 36, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(readerConfig.theme.backgroundColor.opacity(0.98))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.15)), alignment: .bottom)
    }

    private var bottomToolbar: some View {
        HStack {
            Button("上一章") {
                if currentChapterIndex > 0 {
                    audioService.stop()
                    currentChapterIndex -= 1
                    loadCurrentChapter()
                }
            }
            .disabled(currentChapterIndex <= 0)

            Spacer()

            if !chapters.isEmpty {
                Text("\(currentChapterIndex + 1) / \(chapters.count)")
                    .font(.footnote)
                    .foregroundColor(readerConfig.theme.textColor.opacity(0.8))
            }

            Spacer()

            Button("下一章") {
                if currentChapterIndex < chapters.count - 1 {
                    audioService.stop()
                    currentChapterIndex += 1
                    loadCurrentChapter()
                }
            }
            .disabled(currentChapterIndex >= chapters.count - 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(readerConfig.theme.backgroundColor.opacity(0.95))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)), alignment: .top)
    }

    private var tocSheet: some View {
        NavigationView {
            List(chapters) { ch in
                Button(action: {
                    audioService.stop()
                    currentChapterIndex = ch.index
                    showTOC = false
                    loadCurrentChapter()
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
                Section("字号设置") {
                    HStack {
                        Text("A-")
                            .font(.body)
                        Slider(value: $readerConfig.fontSize, in: 12...32, step: 1)
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

    private func loadTOCAndChapter() async {
        if book.origin == "local" {
            let localChapters = BookStore.shared.getChapters(for: book.bookUrl)
            if !localChapters.isEmpty {
                self.chapters = localChapters
                if currentChapterIndex >= localChapters.count {
                    currentChapterIndex = 0
                }
                loadCurrentChapter()
                return
            }
        }

        let effectiveSource = source ?? BookStore.shared.findSource(for: book)
        guard let source = effectiveSource else {
            errorMessage = "未找到书籍关联的书源"
            isLoading = false
            return
        }

        do {
            let fetchedChapters = try await BookContentService.shared.fetchChapterList(book: book, source: source)
            self.chapters = fetchedChapters
            if currentChapterIndex >= fetchedChapters.count {
                currentChapterIndex = 0
            }
            loadCurrentChapter()
        } catch {
            self.errorMessage = "目录解析失败: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    private func loadCurrentChapter() {
        guard !chapters.isEmpty, currentChapterIndex < chapters.count else { return }
        let currentChapter = chapters[currentChapterIndex]
        isLoading = true
        errorMessage = nil

        let effectiveSource = source ?? BookStore.shared.findSource(for: book)

        Task { @MainActor in
            do {
                let content = try await BookContentService.shared.fetchChapterContent(chapter: currentChapter, source: effectiveSource)
                self.chapterContent = content
                self.isLoading = false
                BookStore.shared.updateProgress(bookUrl: book.bookUrl, chapterIndex: currentChapterIndex, chapterTitle: currentChapter.title)
            } catch {
                self.errorMessage = "正文解析失败: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private var contentBlocks: [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentId = 0
        let regex = try? NSRegularExpression(pattern: "\\[image:(.*?)\\]")
        let lines = chapterContent.components(separatedBy: "\n")

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
}

public struct ContentBlock: Identifiable {
    public let id: Int
    public let isImage: Bool
    public let text: String
    public let imageUrl: String?
}

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

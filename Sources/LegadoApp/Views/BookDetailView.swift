import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
public struct BookDetailView: View {
    @ObservedObject var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    let initialBook: Book
    let source: BookSource?

    @State private var currentBook: Book
    @State private var chapters: [BookChapter] = []
    @State private var isLoadingDetails: Bool = false
    @State private var errorMessage: String? = nil

    @State private var navigateToTOC: Bool = false
    @State private var isIntroExpanded: Bool = false
    @State private var isReading: Bool = false
    @State private var selectedChapterIndex: Int = 0
    @State private var showActionAlert: Bool = false
    @State private var showBookQRShare: Bool = false
    @State private var actionAlertMessage: String = ""
    @State private var showChangeSource: Bool = false
    @State private var showGroupDialog: Bool = false
    @State private var showEditBookSheet: Bool = false
    @State private var showBookVariableDialog: Bool = false
    @State private var showSourceVariableDialog: Bool = false
    @State private var showTxtRuleSheet: Bool = false
    public init(book: Book, source: BookSource? = nil) {
        self.initialBook = book
        self.source = source
        self._currentBook = State(initialValue: book)
        self._selectedChapterIndex = State(initialValue: book.durChapterIndex)
    }

    public init(searchBook: SearchBook, source: BookSource? = nil) {
        let b = Book(
            bookUrl: searchBook.bookUrl,
            name: searchBook.name,
            author: searchBook.author,
            kind: searchBook.kind,
            coverUrl: searchBook.coverUrl,
            intro: searchBook.intro,
            origin: searchBook.origin,
            originName: searchBook.originName,
            wordCount: searchBook.wordCount,
            latestChapterTitle: searchBook.latestChapterTitle
        )
        self.init(book: b, source: source)
    }

    private var isInBookshelf: Bool {
        bookStore.bookshelf.contains(where: { $0.bookUrl == currentBook.bookUrl })
    }

    private var currentBookshelfBook: Book {
        bookStore.bookshelf.first(where: { $0.bookUrl == currentBook.bookUrl }) ?? currentBook
    }

    private var tags: [String] {
        guard let kind = currentBook.kind, !kind.isEmpty else { return [] }
        var seen = Set<String>()
        return kind
            .components(separatedBy: CharacterSet(charactersIn: ",，/| "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var displayIntro: String? {
        guard let intro = currentBookshelfBook.displayIntro, !intro.isEmpty else { return nil }
        let cleaned = BookContentService.cleanHtml(intro)
        return cleaned.isEmpty ? nil : cleaned
    }

    public var body: some View {
        ZStack {
            // ignoresSafeArea(bottom)：TabBar 隐藏后其占位安全区不一定即时回收，
            // 直接把容器铺到物理底部，按钮栏自管 Home 指示条避让。
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Header: 居中封面 + 书名 + kind 标签 + 信息行（Android activity_book_info 同构）
                        headerCard
                            .padding(.horizontal)
                            .padding(.top, 12)

                        // Intro section (Real story synopsis)
                        introSection
                            .padding(.horizontal)

                        Spacer(minLength: 24)
                    }
                }

                // Fixed Bottom Action Bar (放入书架/删除书籍 + 阅读, Android fl_action 同构)
                bottomActionBar
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("书籍详情")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(TabBarHiddenModifier())
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEditBookSheet = true
                        } label: {
                            Label("编辑书籍信息", systemImage: "pencil")
                        }

                        if isInBookshelf {
                            Button {
                                bookStore.pinBook(bookUrl: currentBook.bookUrl)
                                actionAlertMessage = "已将「\(currentBook.name)」置顶到书架最前"
                                showActionAlert = true
                            } label: {
                                Label("置顶本书", systemImage: "pin")
                            }
                        }

                        if currentBook.origin != "local" {
                            Button {
                                showChangeSource = true
                            } label: {
                                Label("换源", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        Button {
                            Task {
                                chapters = []
                                await loadBookDetails(runPreUpdateJs: true)
                                actionAlertMessage = "目录与详情已刷新"
                                showActionAlert = true
                            }
                        } label: {
                            Label("刷新目录与详情", systemImage: "arrow.clockwise")
                        }

                        Button {
                            copyStringToClipboard(currentBook.bookUrl)
                            actionAlertMessage = "已拷贝书籍 URL 至剪贴板"
                            showActionAlert = true
                        } label: {
                            Label("拷贝书籍 URL", systemImage: "link")
                        }

                        Button {
                            showBookQRShare = true
                        } label: {
                            Label("生成分享二维码", systemImage: "qrcode")
                        }

                        if !currentBook.tocUrl.isEmpty {
                            Button {
                                copyStringToClipboard(currentBook.tocUrl)
                                actionAlertMessage = "已拷贝目录 URL 至剪贴板"
                                showActionAlert = true
                            } label: {
                                Label("拷贝目录 URL", systemImage: "list.bullet.rectangle")
                            }
                        }

                        Button {
                            showBookVariableDialog = true
                        } label: {
                            Label("设置书籍变量", systemImage: "text.badge.star")
                        }

                        if currentBook.origin != "local" {
                            Button {
                                showSourceVariableDialog = true
                            } label: {
                                Label("设置书源变量", systemImage: "gearshape")
                            }
                        }

                        if currentBook.origin == "local" && currentBook.bookUrl.hasPrefix("txt://") {
                            Button {
                                showTxtRuleSheet = true
                            } label: {
                                Label("TXT 目录规则", systemImage: "text.book.closed")
                            }
                        }
                        Button(role: .destructive) {
                            let count = BookContentService.shared.getCacheCount(for: currentBook.bookUrl)
                            BookContentService.shared.clearCache(for: currentBook.bookUrl)
                            actionAlertMessage = "已清除本书缓存章节" + (count > 0 ? " (\(count)章)" : "")
                            showActionAlert = true
                        } label: {
                            Label("清除缓存", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showGroupDialog) {
                BookGroupSelectionSheet(bookURLs: [currentBook.bookUrl])
            }
            .alert(actionAlertMessage, isPresented: $showActionAlert) {
                Button("确定", role: .cancel) {}
            }
            .sheet(isPresented: $showBookQRShare) {
                QRCodeShareView(content: currentBook.bookUrl,
                                title: "「\(currentBook.name)」· 用 Legado 扫码按网址添加")
            }
            .background(
                NavigationLink(
                    isActive: $navigateToTOC,
                    destination: {
                        ChapterListView(
                            bookUrl: currentBook.bookUrl,
                            chapters: chapters,
                            currentChapterIndex: currentBookshelfBook.durChapterIndex,
                            initialReverse: currentBookshelfBook.reverseToc,
                            onReverseChanged: { value in
                                currentBook.setReaderSetting("reverseToc", value: .bool(value))
                                if let index = bookStore.bookshelf.firstIndex(where: { $0.bookUrl == currentBook.bookUrl }) {
                                    bookStore.bookshelf[index].setReaderSetting("reverseToc", value: .bool(value))
                                    bookStore.saveBookshelf()
                                }
                            },
                            onSelectChapter: { index in
                                selectedChapterIndex = index
                                isReading = true
                            }
                        )
                    },
                    label: { EmptyView() }
                )
                .hidden()
                .frame(width: 0, height: 0)
            )

            #if !os(iOS)
            if isReading {
                readerCoverView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .transition(.opacity)
                    .zIndex(999)
            }
            #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isReading) {
            readerCoverView
        }
        #endif
        .sheet(isPresented: $showChangeSource) {
            ChangeSourceSheet(
                book: currentBookshelfBook,
                mode: .wholeBook,
                chapterTitle: currentBookshelfBook.durChapterTitle ?? "",
                onApply: { candidate, toc in
                    let active = currentBookshelfBook
                    let mapped = ChapterMatcher.mapChapter(
                        oldIndex: active.durChapterIndex,
                        oldTitle: active.durChapterTitle ?? "",
                        oldCount: max(active.totalChapterNum, max(chapters.count, 1)),
                        newTitles: toc.map { $0.title }
                    )
                    let updated = bookStore.changeSource(
                        oldBook: active,
                        to: candidate.found,
                        source: candidate.source,
                        newChapters: toc,
                        mappedChapterIndex: mapped
                    )
                    currentBook = updated
                    chapters = toc
                    selectedChapterIndex = updated.durChapterIndex
                    showChangeSource = false
                },
                onApplyChapterText: { _ in }
            )
        }
        .sheet(isPresented: $showEditBookSheet) {
            BookInfoEditSheet(book: currentBookshelfBook) { name, author, coverUrl, intro in
                if !isInBookshelf {
                    _ = bookStore.saveOrUpdateBook(currentBook)
                }
                if let updated = bookStore.updateBookMetadata(
                    bookUrl: currentBook.bookUrl,
                    name: name,
                    author: author,
                    coverUrl: coverUrl,
                    intro: intro
                ) {
                    currentBook = updated
                }
            }
        }
        .sheet(isPresented: $showBookVariableDialog) {
            VariableEditorSheet(
                title: "设置书籍变量",
                comment: "为本书自定义存储变量参数（如动态 Cookie、Token、附加参数等）：",
                initialValue: currentBookshelfBook.variable ?? ""
            ) { savedValue in
                if !isInBookshelf {
                    _ = bookStore.saveOrUpdateBook(currentBook)
                }
                var b = currentBookshelfBook
                b.variable = savedValue.isEmpty ? nil : savedValue
                currentBook = bookStore.saveOrUpdateBook(b)
                actionAlertMessage = "书籍变量已保存"
                showActionAlert = true
            }
        }
        .sheet(isPresented: $showSourceVariableDialog) {
            let resolvedSource = source ?? bookStore.findSource(for: currentBook)
            VariableEditorSheet(
                title: "设置书源变量",
                comment: resolvedSource?.variableComment ?? "为书源「\(resolvedSource?.bookSourceName ?? "")」设置全局持久化变量参数：",
                initialValue: resolvedSource?.variable ?? (UserDefaults.standard.string(forKey: "legado_source_var_\(resolvedSource?.bookSourceUrl ?? "")") ?? "")
            ) { savedValue in
                guard let src = resolvedSource else { return }
                var updated = src
                updated.variable = savedValue.isEmpty ? nil : savedValue
                bookStore.updateSource(originalSource: src, newSource: updated)
                UserDefaults.standard.set(savedValue, forKey: "legado_source_var_\(src.bookSourceUrl)")
                actionAlertMessage = "书源变量已保存"
                showActionAlert = true
            }
        }
        .sheet(isPresented: $showTxtRuleSheet) {
            NavigationView {
                List {
                    Section(header: Text("选择用于重新拆分本 TXT 小说的目录规则")) {
                        ForEach(TxtTocRuleStore.load().filter { $0.enable }) { r in
                            Button {
                                reSplitTxtChapters(with: r.rule)
                                showTxtRuleSheet = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(r.rule)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("选择 TXT 目录规则")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showTxtRuleSheet = false }
                    }
                }
            }
        }
        .task {
            await loadBookDetails()
        }
    }

    @ViewBuilder
    private var readerCoverView: some View {
        let activeBook = isInBookshelf ? currentBookshelfBook : currentBook
        let resolvedSource = source ?? bookStore.findSource(for: activeBook)
        if resolvedSource?.bookSourceType == 1 || activeBook.isAudioBook {
            AudioPlayView(
                book: activeBook,
                source: resolvedSource,
                initialChapterIndex: selectedChapterIndex,
                onDismiss: { isReading = false }
            )
        } else {
            NavigationView {
                ReaderView(book: activeBook, source: resolvedSource, initialChapterIndex: selectedChapterIndex, onDismiss: {
                    isReading = false
                })
            }
        }
    }

    // MARK: - Header Card

    /// Android `activity_book_info` 同构头部：居中大封面 → 居中书名 → 居中 kind 标签流 →
    /// 竖排图标信息行（作者 / 来源+换源 / 最新 / 分组+设置分组 / 目录+查看目录）。
    private var headerCard: some View {
        VStack(spacing: 10) {
            coverImage
                .frame(width: 110, height: 160)
                .cornerRadius(5)
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                .padding(.top, 4)

            Text(currentBook.name)
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !tags.isEmpty {
                tagsFlow
            }

            VStack(alignment: .leading, spacing: 0) {
                infoRow(icon: "person", text: authorText)
                infoRow(icon: "globe", text: "来源：\(currentBook.originName.isEmpty ? currentBook.origin : currentBook.originName)") {
                    if currentBook.origin != "local" {
                        accentChip("换源") { showChangeSource = true }
                    }
                }
                if let latest = latestText {
                    infoRow(icon: "book", text: latest)
                }
                if isInBookshelf {
                    infoRow(icon: "folder", text: "分组：\(groupName)") {
                        accentChip("设置分组") { showGroupDialog = true }
                    }
                }
                infoRow(icon: "list.bullet", text: "目录：共 \(chapters.isEmpty ? (currentBook.totalChapterNum) : chapters.count) 章") {
                    accentChip("查看目录") { navigateToTOC = true }
                }
            }
            .padding(.top, 6)
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "book.closed")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    private var coverImage: some View {
        Group {
            if let coverUrlStr = currentBookshelfBook.displayCoverURL, let url = URL(string: coverUrlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .clipped()
    }

    private var authorText: String {
        if !currentBook.author.isEmpty && currentBook.author != "未知作者" {
            return currentBook.author
        }
        if isLoadingDetails { return "正在获取作者..." }
        return "佚名"
    }

    private var latestText: String? {
        if isLoadingDetails && currentBook.latestChapterTitle == nil { return "最新：正在获取..." }
        guard let latest = currentBook.latestChapterTitle, !latest.isEmpty else { return nil }
        return "最新：\(latest)"
    }

    private var groupName: String {
        let gid = currentBookshelfBook.group
        if gid == 0 { return "未分组" }
        if !bookStore.usesGroupBitmasks {
            return BookGroupStore.load().first { $0.groupId == gid }?.groupName ?? "未分组"
        }
        let names = BookGroupStore.load().filter { $0.groupId > 0 && gid & $0.groupId != 0 }.map(\.groupName)
        return names.isEmpty ? "未分组" : names.joined(separator: "、")
    }

    /// 信息行：18pt 图标 + 13sp 次级文本 + 尾部 accent 小按钮（AccentBgTextView 对应物）。
    private func infoRow<Trailing: View>(icon: String, text: String,
                                         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.vertical, 3)
    }

    private func accentChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor)
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }

    /// kind 标签：单行横向滚动条（Android `LabelsBar` 即 HorizontalScrollView 同构）。
    /// 数据完整性由 `getStringList` 解析保证（此前 getString 只取首个才是显示不全的根因）。
    private var tagsFlow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tags Section

    // MARK: - Intro Section

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("内容简介")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if let intro = displayIntro, intro.count > 100 {
                    Button(action: {
                        withAnimation {
                            isIntroExpanded.toggle()
                        }
                    }) {
                        Text(isIntroExpanded ? "收起" : "展开")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            if let intro = displayIntro {
                Text(intro)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .lineLimit(isIntroExpanded ? nil : 4)
            } else if isLoadingDetails {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在加载作品简介与详情...")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.vertical, 4)
            } else {
                Text("暂无简介")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Bottom Action Bar

    /// 按钮与屏幕物理底边的视觉净距：仅在有 Home 指示条的设备上留出小间距（指示条压在
    /// 按钮背景上而非文字上），无 Home 条设备（SE 等）完全贴底。设备特征推导，非写死。
    private var bottomClearance: CGFloat {
        #if os(iOS)
        let hasHomeIndicator = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first.map { $0.safeAreaInsets.bottom > 0 } ?? false
        return hasHomeIndicator ? 8 : 0
        #else
        return 0
        #endif
    }

    /// Android `fl_action` 同构底部操作栏：左侧「放入书架/删除书籍」纯文本按钮 +
    /// 右侧「阅读」accent 实心按钮，等宽平铺。
    private var bottomActionBar: some View {
        HStack(spacing: 0) {
            Button(action: { toggleShelf() }) {
                Text(isInBookshelf ? "删除书籍" : "放入书架")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.plain)

            Button(action: {
                if !isInBookshelf {
                    _ = bookStore.saveOrUpdateBook(currentBook)
                }
                selectedChapterIndex = currentBookshelfBook.durChapterIndex
                isReading = true
            }) {
                Text("阅读")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, bottomClearance)
        .background(
            Group {
                #if os(iOS)
                Color(UIColor.systemBackground)
                #else
                Color.primary.colorInvert()
                #endif
            }
        )
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.secondary.opacity(0.2)), alignment: .top)
    }

    // MARK: - Helper Actions

    private func toggleShelf() {
        if isInBookshelf {
            bookStore.removeBook(bookUrl: currentBook.bookUrl)
        } else {
            _ = bookStore.saveOrUpdateBook(currentBook)
        }
    }

    private func loadBookDetails(runPreUpdateJs: Bool = false) async {
        guard chapters.isEmpty else { return }

        // If local book, load local chapters from BookStore
        if currentBook.isLocalBook {
            let localChapters = bookStore.getChapters(for: currentBook.bookUrl)
            if !localChapters.isEmpty {
                await MainActor.run {
                    self.chapters = localChapters
                    self.currentBook.totalChapterNum = localChapters.count
                    if let last = localChapters.last {
                        self.currentBook.latestChapterTitle = last.title
                    }
                }
                return
            }
        }

        let resolvedSource = source ?? bookStore.findSource(for: currentBook)

        guard let src = resolvedSource else { return }

        isLoadingDetails = true
        errorMessage = nil

        do {
            let originalURL = currentBook.bookUrl
            let wasOnShelf = isInBookshelf
            let (detailedBook, fetchedChapters) = try await BookContentService.shared.fetchBookDetail(book: currentBook, source: src, runPreUpdateJs: runPreUpdateJs)
            try await MainActor.run {
                let installed = wasOnShelf ? try self.bookStore.applyRefreshedBook(detailedBook, replacing: originalURL) : nil
                self.currentBook = installed ?? detailedBook
                self.chapters = fetchedChapters
                self.isLoadingDetails = false

            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoadingDetails = false
            }
        }
    }

    private func copyStringToClipboard(_ str: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = str
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        #endif
    }

    private func reSplitTxtChapters(with pattern: String) {
        let bookId = CryptoUtils.md5(currentBook.bookUrl)
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let txtBookDir = docsDir.appendingPathComponent("Books/TXT/\(bookId)")
        var fullText = ""
        let cachedChapters = bookStore.getChapters(for: currentBook.bookUrl)
        for ch in cachedChapters {
            if let fileUrl = URL(string: ch.url), let t = try? String(contentsOf: fileUrl) {
                fullText += (ch.title + "\n\n" + t + "\n\n")
            }
        }
        guard !fullText.isEmpty else { return }
        let nsString = fullText as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let matches = regex.matches(in: fullText, range: NSRange(location: 0, length: nsString.length))
        guard matches.count > 1 else {
            actionAlertMessage = "未能使用该规则匹配到多个章节"
            showActionAlert = true
            return
        }

        var newChapters: [BookChapter] = []
        for i in 0..<matches.count {
            let match = matches[i]
            let title = nsString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let startPos = match.range.location
            let endPos = (i + 1 < matches.count) ? matches[i + 1].range.location : nsString.length
            let chapterText = nsString.substring(with: NSRange(location: startPos, length: endPos - startPos))

            let chFile = txtBookDir.appendingPathComponent("chapter_\(i).txt")
            try? chapterText.write(to: chFile, atomically: true, encoding: .utf8)

            newChapters.append(BookChapter(
                bookUrl: currentBook.bookUrl,
                url: chFile.absoluteString,
                title: title,
                index: i
            ))
        }
        chapters = newChapters
        currentBook.totalChapterNum = newChapters.count
        if let last = newChapters.last {
            currentBook.latestChapterTitle = last.title
        }
        bookStore.saveChapters(newChapters, for: currentBook.bookUrl)
        _ = bookStore.saveOrUpdateBook(currentBook)
        actionAlertMessage = "重新切章完成，共得到 \(newChapters.count) 章！"
        showActionAlert = true
    }
}

// MARK: - ChapterListView

struct ChapterListView: View {
    @Environment(\.dismiss) private var dismiss
    var bookUrl: String = ""
    let chapters: [BookChapter]
    let currentChapterIndex: Int
    var showCloseButton: Bool = false
    var initialReverse: Bool = false
    var onReverseChanged: ((Bool) -> Void)? = nil
    let onSelectChapter: (Int) -> Void

    @State private var searchKeyword: String = ""
    @State private var isReversed: Bool = false

    private var filteredChapters: [(index: Int, chapter: BookChapter)] {
        let enumerated = chapters.enumerated().map { (index: $0.offset, chapter: $0.element) }
        let base = isReversed ? Array(enumerated.reversed()) : enumerated
        if searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        return base.filter { $0.chapter.title.localizedCaseInsensitiveContains(searchKeyword) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Search filter + Reverse toggle
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索章节标题...", text: $searchKeyword)
                        if !searchKeyword.isEmpty {
                            Button(action: { searchKeyword = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(8)

                    Button {
                        isReversed.toggle()
                        onReverseChanged?(isReversed)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(isReversed ? "倒序" : "正序")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                List(filteredChapters, id: \.index) { item in
                    let isCached = !bookUrl.isEmpty && BookContentService.shared.hasCachedChapter(bookUrl: bookUrl, chapterIndex: item.index)
                    Button(action: {
                        onSelectChapter(item.index)
                    }) {
                        HStack(spacing: 8) {
                            Text(item.chapter.title)
                                .font(.subheadline)
                                .foregroundColor(item.index == currentChapterIndex ? .accentColor : .primary)
                                .lineLimit(1)

                            Spacer()

                            if isCached {
                                Text("已缓存")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }

                            if item.index == currentChapterIndex {
                                Text("当前")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .id(item.index)
                }
                .listStyle(.plain)
                .onAppear {
                    isReversed = initialReverse
                    if currentChapterIndex >= 0 && currentChapterIndex < chapters.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(currentChapterIndex, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("目录 (\(chapters.count) 章)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            if currentChapterIndex >= 0 && currentChapterIndex < chapters.count {
                                withAnimation {
                                    proxy.scrollTo(currentChapterIndex, anchor: .center)
                                }
                            }
                        } label: {
                            Image(systemName: "location")
                        }
                        if showCloseButton {
                            Button("关闭") { dismiss() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - BookInfoEditSheet (Android BookInfoEditActivity Counterpart)

struct BookInfoEditSheet: View {
    let book: Book
    let onSave: (String, String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var author: String
    @State private var coverUrl: String
    @State private var intro: String

    init(book: Book, onSave: @escaping (String, String, String?, String?) -> Void) {
        self.book = book
        self.onSave = onSave
        self._name = State(initialValue: book.name)
        self._author = State(initialValue: book.author)
        self._coverUrl = State(initialValue: book.displayCoverURL ?? "")
        self._intro = State(initialValue: book.displayIntro ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    HStack {
                        Text("书名")
                            .frame(width: 70, alignment: .leading)
                        TextField("必填", text: $name)
                    }
                    HStack {
                        Text("作者")
                            .frame(width: 70, alignment: .leading)
                        TextField("选填", text: $author)
                    }
                    HStack {
                        Text("封面链接")
                            .frame(width: 70, alignment: .leading)
                        TextField("https://...", text: $coverUrl)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }
                }

                Section(header: Text("内容简介")) {
                    TextEditor(text: $intro)
                        .frame(minHeight: 140)
                        .font(.subheadline)
                }
            }
            .navigationTitle("编辑书籍信息")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cUrl = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                        let iText = intro.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(
                            name,
                            author,
                            cUrl.isEmpty ? nil : cUrl,
                            iText.isEmpty ? nil : iText
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - VariableEditorSheet (Android VariableDialog Counterpart)

public struct VariableEditorSheet: View {
    let title: String
    let comment: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    public init(title: String, comment: String = "", initialValue: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.comment = comment
        self.onSave = onSave
        self._text = State(initialValue: initialValue)
    }

    public var body: some View {
        NavigationView {
            Form {
                if !comment.isEmpty {
                    Section(header: Text("说明")) {
                        Text(comment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("变量内容 (文本或 JSON)")) {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.system(.subheadline, design: .monospaced))
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}

#if os(iOS)
/// 详情页置顶期间隐藏 TabBar。还原不放在 onDisappear（那要等 pop 转场结束才触发，
/// 正是「返回书架半秒后才出现 tabbar」的来源），而是由每个能推入详情页的来源页在自己的
/// onAppear（pop 开始瞬间触发）调用 `TabBarVisibility.setHidden(false)` 立即恢复。
struct TabBarHiddenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear { TabBarVisibility.setHidden(true) }
    }
}
#endif


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
    @State private var actionAlertMessage: String = ""
    @State private var showChangeSource: Bool = false
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
        return kind
            .components(separatedBy: CharacterSet(charactersIn: ",，/| "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var displayIntro: String? {
        guard let intro = currentBook.intro, !intro.isEmpty else { return nil }
        // Filter out debug/search metadata that is not real story synopsis
        if intro.hasPrefix("源站：") || intro.contains("最近同步：") {
            return nil
        }
        let cleaned = BookContentService.cleanHtml(intro)
        return cleaned.isEmpty ? nil : cleaned
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Header: Cover + Title + Author + Badges
                        headerCard
                            .padding(.horizontal)
                            .padding(.top, 12)

                        // Tags flow
                        if !tags.isEmpty {
                            tagsSection
                                .padding(.horizontal)
                        }

                        // Directory / TOC preview card
                        tocPreviewCard
                            .padding(.horizontal)

                        // Intro section (Real story synopsis)
                        introSection
                            .padding(.horizontal)

                        Spacer(minLength: 24)
                    }
                }

                // Fixed Bottom Action Bar (Add to shelf + Read Now)
                bottomActionBar
            }
            .navigationTitle("书籍详情")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
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
                                await loadBookDetails()
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
            .alert(actionAlertMessage, isPresented: $showActionAlert) {
                Button("确定", role: .cancel) {}
            }
            .background(
                NavigationLink(
                    isActive: $navigateToTOC,
                    destination: {
                        ChapterListView(
                            bookUrl: currentBook.bookUrl,
                            chapters: chapters,
                            currentChapterIndex: currentBookshelfBook.durChapterIndex,
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
        if resolvedSource?.bookSourceType == 1 || (activeBook.kind?.contains("音频") ?? false) {
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

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            // Book Cover Image
            if let coverUrlStr = currentBook.coverUrl, let url = URL(string: coverUrlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        coverPlaceholder
                    }
                }
                .frame(width: 100, height: 138)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                .clipped()
            } else {
                coverPlaceholder
                    .frame(width: 100, height: 138)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(currentBook.name)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Image(systemName: "person")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !currentBook.author.isEmpty && currentBook.author != "未知作者" {
                        Text(currentBook.author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if isLoadingDetails {
                        Text("正在获取作者...")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.6))
                    } else {
                        Text("佚名")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    // Source Name Badge
                    Text(currentBook.originName.isEmpty ? "网络书源" : currentBook.originName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)

                    if currentBook.origin != "local" {
                        Button {
                            showChangeSource = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("换源")
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.14))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    if let wordCount = currentBook.wordCount, !wordCount.isEmpty {
                        Text(wordCount)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                    }
                }

                if currentBookshelfBook.durChapterIndex > 0,
                   let durTitle = currentBookshelfBook.durChapterTitle {
                    Text("上次读至：\(durTitle)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.15))
            .overlay(
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
            )
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
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
        }
    }

    // MARK: - TOC Preview Card

    private var tocPreviewCard: some View {
        Button(action: {
            navigateToTOC = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet")
                    .font(.headline)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("目录")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        if isLoadingDetails {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if !chapters.isEmpty {
                            Text("共 \(chapters.count) 章")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let latest = currentBook.latestChapterTitle, !latest.isEmpty {
                        Text("最新：\(latest)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if !chapters.isEmpty {
                        Text("最新：\(chapters.last?.title ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if isLoadingDetails {
                        Text("正在拉取目录...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let error = errorMessage {
                        Text("拉取目录失败: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

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

    private var bottomActionBar: some View {
        HStack(spacing: 14) {
            // Add to Shelf Button
            Button(action: {
                toggleShelf()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isInBookshelf ? "checkmark.circle.fill" : "plus.circle")
                    Text(isInBookshelf ? "移出书架" : "加入书架")
                }
                .font(.subheadline.bold())
                .foregroundColor(isInBookshelf ? .secondary : .accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // Read Now Button
            Button(action: {
                if !isInBookshelf {
                    _ = bookStore.saveOrUpdateBook(currentBook)
                }
                selectedChapterIndex = currentBookshelfBook.durChapterIndex
                isReading = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                    Text(currentBookshelfBook.durChapterIndex > 0 ? "继续阅读" : "立即阅读")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(
            Group {
                #if os(iOS)
                Color(UIColor.systemBackground)
                #else
                Color.primary.colorInvert()
                #endif
            }
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: -2)
        )
    }

    // MARK: - Helper Actions

    private func toggleShelf() {
        if isInBookshelf {
            bookStore.removeBook(bookUrl: currentBook.bookUrl)
        } else {
            _ = bookStore.saveOrUpdateBook(currentBook)
        }
    }

    private func loadBookDetails() async {
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
            let (detailedBook, fetchedChapters) = try await BookContentService.shared.fetchBookDetail(book: currentBook, source: src)
            await MainActor.run {
                self.currentBook = detailedBook
                self.chapters = fetchedChapters
                self.isLoadingDetails = false

                // If this book is already on the shelf, persist its fetched author, intro and chapters count
                if self.isInBookshelf {
                    _ = self.bookStore.saveOrUpdateBook(detailedBook)
                }
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
        self._coverUrl = State(initialValue: book.customCoverUrl ?? book.coverUrl ?? "")
        self._intro = State(initialValue: book.intro ?? "")
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

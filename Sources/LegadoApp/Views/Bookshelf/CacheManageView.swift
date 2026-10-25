import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Cache Manage View (Plan 第一批 书架二级菜单 ①: CacheActivity 同构)
//
// Android's `CacheActivity` lists every shelf book with its offline footprint and the two
// actions that matter: **全本缓存** (one tap = download every chapter of that book, with
// progress + stop) and 清除. Export (TXT/EPUB/书单) rides on top of the same rows. The
// download itself is `BookContentService.downloadChaptersRange` — sequential, 60ms-paced,
// already-cached chapters are skipped and `Task.isCancelled` stops it cleanly.

public struct CacheManageView: View {
    @ObservedObject private var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var exportTarget: ExportTarget? = nil
    @State private var exportedURL: URL? = nil
    @State private var shareItems: [Any]? = nil
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var isExportingAll: Bool = false

    // 一键缓存状态：bookUrl → (已完成章数, 总章数)；任务表用于停止。
    @State private var cachingProgress: [String: (done: Int, total: Int)] = [:]
    @State private var cachingTasks: [String: Task<Void, Never>] = [:]
    @State private var cacheAllTask: Task<Void, Never>? = nil
    // 目录抓取中的书籍（未读过的书源书籍第一次缓存前要先抓目录）。
    @State private var fetchingTocUrls: [String] = []

    private enum CacheError: LocalizedError {
        case noSource
        case emptyToc

        var errorDescription: String? {
            switch self {
            case .noSource: return "未找到这本书关联的书源（可能已被删除或禁用）"
            case .emptyToc: return "书源返回了空目录"
            }
        }
    }

    /// One book row in the export flow: the book plus its cached chapter list snapshot.
    private struct ExportTarget: Identifiable {
        let book: Book
        let chapters: [BookChapter]
        var id: String { book.bookUrl }
    }

    private struct Row: Identifiable {
        let book: Book
        let cachedCount: Int
        let sizeBytes: Int64
        let chapterCount: Int
        var id: String { book.bookUrl }

        /// 本地书籍判定与 `Book.isLocalBook` 一致；网络书籍一律可缓存（目录未抓取的
        /// 会在点缓存时先抓目录）。
        var isLocal: Bool { book.isLocalBook }
        var hasToc: Bool { chapterCount > 0 }
    }

    private var rows: [Row] {
        bookStore.bookshelf.map { book in
            Row(book: book,
                cachedCount: BookContentService.shared.getCacheCount(for: book.bookUrl),
                sizeBytes: BookContentService.shared.cacheSize(for: book.bookUrl),
                chapterCount: bookStore.getChapters(for: book.bookUrl).count)
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public init() {}

    public var body: some View {
        NavigationView {
            Group {
                if rows.isEmpty {
                    emptyView
                } else {
                    list
                }
            }
            .navigationTitle("缓存管理")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            toggleCacheAll()
                        } label: {
                            Label(cacheAllTask == nil ? "一键缓存全部书籍" : "停止全部缓存",
                                  systemImage: cacheAllTask == nil ? "icloud.and.arrow.down" : "stop.circle")
                        }
                        .disabled(rows.filter { !$0.isLocal }.isEmpty)

                        Button("导出所有书籍 (TXT)") {
                            exportAll(format: .txt)
                        }
                        .disabled(isExportingAll || rows.isEmpty)

                        Menu("TXT 导出编码") {
                            ForEach(BookExportService.TextEncoding.allCases) { enc in
                                Button(enc.rawValue) { exportAll(format: .txt, encoding: enc) }
                            }
                        }
                        .disabled(isExportingAll || rows.isEmpty)

                        Button("导出所有书籍 (EPUB)") {
                            exportAll(format: .epub)
                        }
                        .disabled(isExportingAll || rows.isEmpty)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $exportTarget) { target in
                exportOptionsSheet(target)
            }
            .sheet(isPresented: Binding(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )) {
                if let items = shareItems {
                    ActivityShareSheet(items: items)
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var list: some View {
        List {
            Section(footer: Text("点击右侧 ⬇ 一键缓存该书全部章节（已缓存章节自动跳过，可中途停止）。导出内容为已离线缓存的章节正文（未净化原文）；可选范围的离线下载在阅读器菜单「离线下载章节」。")) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }

            if isExportingAll {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在导出全部书籍...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text("书架还没有任何缓存")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowView(_ row: Row) -> some View {
        Button {
            exportTarget = ExportTarget(book: row.book,
                                        chapters: bookStore.getChapters(for: row.book.bookUrl))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .foregroundColor(row.cachedCount > 0 ? .accentColor : .secondary.opacity(0.4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.book.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    subtitle(for: row)
                }
                Spacer()
                cacheButton(for: row)
                if row.cachedCount > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Row subtitle: download progress while caching, TOC crawl status, or the cached summary.
    @ViewBuilder
    private func subtitle(for row: Row) -> some View {
        if let progress = cachingProgress[row.book.bookUrl] {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("缓存中 \(progress.done)/\(progress.total) 章")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        } else if fetchingTocUrls.contains(row.book.bookUrl) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("正在获取目录...")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        } else if row.isLocal {
            Text("本地书籍 · \(row.cachedCount) 章 · \(Self.byteCount(row.sizeBytes))")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if !row.hasToc {
            Text("已缓存 0 章 · 目录未获取，点 ⬇ 一键缓存")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Text("已缓存 \(row.cachedCount)/\(row.chapterCount) 章 · \(Self.byteCount(row.sizeBytes))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Trailing action: one-tap 全本缓存, tap again to stop. Only local books show nothing.
    @ViewBuilder
    private func cacheButton(for row: Row) -> some View {
        if !row.isLocal {
            if cachingProgress[row.book.bookUrl] != nil {
                Button {
                    stopCaching(row.book.bookUrl)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            } else if fetchingTocUrls.contains(row.book.bookUrl) {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    startCaching(book: row.book)
                } label: {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Per-book export options: one-tap cache, range download entry, export, clear.
    private func exportOptionsSheet(_ target: ExportTarget) -> some View {
        NavigationView {
            Form {
                if !target.book.isLocalBook {
                    Section(header: Text(target.chapters.isEmpty
                                         ? "离线缓存（目录未获取，将先抓取目录）"
                                         : "离线缓存（共 \(target.chapters.count) 章，已缓存 \(BookContentService.shared.getCacheCount(for: target.book.bookUrl)) 章）")) {
                        Button {
                            startCaching(book: target.book)
                            exportTarget = nil
                        } label: {
                            Label("一键缓存全本", systemImage: "icloud.and.arrow.down")
                        }
                    }
                }
                Section(header: Text("整书导出")) {
                    Menu {
                        ForEach(BookExportService.TextEncoding.allCases) { enc in
                            Button(enc.rawValue) {
                                exportOne(target, format: .txt, encoding: enc)
                            }
                        }
                    } label: {
                        Label("导出 TXT", systemImage: "doc.plaintext")
                    }
                    Button {
                        exportOne(target, format: .epub, encoding: .utf8)
                    } label: {
                        Label("导出 EPUB", systemImage: "book.closed")
                    }
                }
                Section(header: Text("缓存")) {
                    Button(role: .destructive) {
                        stopCaching(target.book.bookUrl)
                        BookContentService.shared.clearCache(for: target.book.bookUrl)
                        exportTarget = nil
                        alertTitle = "已清除"
                        alertMessage = "「\(target.book.name)」的离线章节缓存已全部删除"
                        showAlert = true
                    } label: {
                        Label("清除本书缓存", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(target.book.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { exportTarget = nil }
                }
            }
        }
    }

    // MARK: - 一键缓存

    private enum ExportFormat { case txt, epub }

    /// One-tap 全本缓存. Network books without a fetched TOC crawl the目录 first
    /// (progress shows 正在获取目录), then download every chapter, skipping what is
    /// already on disk. Tapping the stop icon cancels the task.
    private func startCaching(book: Book) {
        guard cachingTasks[book.bookUrl] == nil,
              !fetchingTocUrls.contains(book.bookUrl) else { return }
        let chapters = bookStore.getChapters(for: book.bookUrl)
        if !chapters.isEmpty {
            beginDownload(book: book, chapters: chapters)
            return
        }
        // 目录未抓取（没打开过详情的书源书籍）：先抓目录。
        guard !book.isLocalBook else {
            alertTitle = "无法缓存"
            alertMessage = "「\(book.name)」是本地书籍且没有目录"
            showAlert = true
            return
        }
        guard let source = bookStore.findSource(for: book) else {
            alertTitle = "无法缓存"
            alertMessage = CacheError.noSource.errorDescription ?? "未找到书源"
            showAlert = true
            return
        }
        setTocFetching(book.bookUrl, true)
        Task {
            do {
                let result = try await BookContentService.shared.fetchBookDetailResult(book: book,
                                                                                       source: source)
                var toc = result.chapters
                guard !toc.isEmpty else { throw CacheError.emptyToc }
                for i in 0..<toc.count { toc[i].index = i }
                await MainActor.run {
                    bookStore.saveChapters(toc, for: book.bookUrl)
                    bookStore.markTocFetched(bookUrl: book.bookUrl)
                    setTocFetching(book.bookUrl, false)
                    beginDownload(book: book, chapters: toc)
                }
            } catch {
                await MainActor.run {
                    setTocFetching(book.bookUrl, false)
                    alertTitle = "获取目录失败"
                    alertMessage = "「\(book.name)」：\(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    /// Kicks off the full-book download task for a book that already has its TOC.
    private func beginDownload(book: Book, chapters: [BookChapter]) {
        guard cachingTasks[book.bookUrl] == nil else { return }
        let source = bookStore.findSource(for: book)
        cachingProgress[book.bookUrl] = (0, chapters.count)
        cachingTasks[book.bookUrl] = Task {
            let result = await BookContentService.shared.downloadChaptersRange(
                book: book, chapters: chapters, source: source,
                startIndex: 0, endIndex: chapters.count - 1,
                onProgress: { done, total in
                    Task { @MainActor in
                        self.setProgress(done: done, total: total, for: book.bookUrl)
                    }
                }
            )
            await MainActor.run {
                // A manual stop removes the task first; only natural completion reports.
                if cachingTasks[book.bookUrl] != nil {
                    alertTitle = "缓存完成"
                    alertMessage = "「\(book.name)」新增缓存 \(result.successCount) 章，已缓存跳过 \(result.skippedCount) 章"
                        + (result.failedCount > 0 ? "，失败 \(result.failedCount) 章" : "")
                    showAlert = true
                }
                var tasks = cachingTasks
                tasks[book.bookUrl] = nil
                cachingTasks = tasks
                var progress = cachingProgress
                progress[book.bookUrl] = nil
                cachingProgress = progress
            }
        }
    }

    /// Dictionary/Set writes across actor-boundary closures must go through a whole-value
    /// assignment, so progress / TOC-fetch state is updated via these MainActor helpers.
    @MainActor
    private func setProgress(done: Int, total: Int, for bookUrl: String) {
        var progress = cachingProgress
        progress[bookUrl] = (done, total)
        cachingProgress = progress
    }

    @MainActor
    private func setTocFetching(_ bookUrl: String, _ fetching: Bool) {
        var current = fetchingTocUrls
        if fetching {
            if !current.contains(bookUrl) { current.append(bookUrl) }
        } else {
            current.removeAll { $0 == bookUrl }
        }
        fetchingTocUrls = current
    }

    private func stopCaching(_ bookUrl: String) {
        cachingTasks[bookUrl]?.cancel()
        cachingTasks[bookUrl] = nil
        cachingProgress[bookUrl] = nil
    }

    /// 一键缓存全部书籍：sequential queue (one book at a time keeps the 60ms pacing honest),
    /// progress shown on the active row. Snapshots are taken on the main thread first; books
    /// without a TOC crawl it inside the queue before downloading.
    private func toggleCacheAll() {
        if let task = cacheAllTask {
            task.cancel()
            cacheAllTask = nil
            cachingProgress.removeAll()
            fetchingTocUrls.removeAll()
            return
        }
        let targets: [(book: Book, source: BookSource?, chapters: [BookChapter])] =
            rows.filter { !$0.isLocal }.map { row in
                (row.book, bookStore.findSource(for: row.book),
                 bookStore.getChapters(for: row.book.bookUrl))
            }
        guard !targets.isEmpty else {
            alertTitle = "没有可缓存的书籍"
            alertMessage = "书架中没有网络书籍"
            showAlert = true
            return
        }
        cacheAllTask = Task {
            for target in targets {
                guard !Task.isCancelled else { break }
                var chapters = target.chapters
                if chapters.isEmpty {
                    // 未读过的书：先抓目录再入队。
                    guard let source = target.source else { continue }
                    await MainActor.run { self.setTocFetching(target.book.bookUrl, true) }
                    do {
                        let result = try await BookContentService.shared.fetchBookDetailResult(
                            book: target.book, source: source)
                        var toc = result.chapters
                        guard !toc.isEmpty else { continue }
                        for i in 0..<toc.count { toc[i].index = i }
                        await MainActor.run {
                            bookStore.saveChapters(toc, for: target.book.bookUrl)
                            bookStore.markTocFetched(bookUrl: target.book.bookUrl)
                            self.setTocFetching(target.book.bookUrl, false)
                        }
                        chapters = toc
                    } catch {
                        await MainActor.run { self.setTocFetching(target.book.bookUrl, false) }
                        continue
                    }
                }
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.setProgress(done: 0, total: chapters.count, for: target.book.bookUrl)
                }
                _ = await BookContentService.shared.downloadChaptersRange(
                    book: target.book, chapters: chapters, source: target.source,
                    startIndex: 0, endIndex: chapters.count - 1,
                    onProgress: { done, total in
                        Task { @MainActor in
                            self.setProgress(done: done, total: total, for: target.book.bookUrl)
                        }
                    }
                )
                await MainActor.run {
                    var progress = self.cachingProgress
                    progress[target.book.bookUrl] = nil
                    self.cachingProgress = progress
                }
            }
            await MainActor.run {
                cacheAllTask = nil
                alertTitle = "批量缓存结束"
                alertMessage = Task.isCancelled ? "已停止剩余书籍的缓存" : "全部书籍缓存完毕"
                showAlert = true
            }
        }
    }

    // MARK: - Export

    private func exportOne(_ target: ExportTarget, format: ExportFormat, encoding: BookExportService.TextEncoding) {
        let book = target.book
        let chapters = target.chapters
        do {
            let url: URL
            switch format {
            case .txt:
                url = try BookExportService.exportTXT(book: book, chapters: chapters,
                                                      contentProvider: contentProvider(book),
                                                      encoding: encoding)
            case .epub:
                url = try BookExportService.exportEPUB(book: book, chapters: chapters,
                                                       contentProvider: contentProvider(book))
            }
            exportTarget = nil
            shareItems = [url]
        } catch {
            exportTarget = nil
            alertTitle = "导出失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func exportAll(format: ExportFormat, encoding: BookExportService.TextEncoding = .utf8) {
        isExportingAll = true
        let targets: [(Book, [BookChapter])] = bookStore.bookshelf.map { book in
            (book, bookStore.getChapters(for: book.bookUrl))
        }
        Task {
            var urls: [URL] = []
            for (book, chapters) in targets {
                let provider = contentProvider(book)
                do {
                    switch format {
                    case .txt:
                        urls.append(try BookExportService.exportTXT(book: book, chapters: chapters,
                                                                    contentProvider: provider, encoding: encoding))
                    case .epub:
                        urls.append(try BookExportService.exportEPUB(book: book, chapters: chapters,
                                                                     contentProvider: provider))
                    }
                } catch BookExportService.ExportError.noCachedContent {
                    continue
                } catch {
                    continue
                }
            }
            await MainActor.run {
                isExportingAll = false
                if urls.isEmpty {
                    alertTitle = "没有可导出的内容"
                    alertMessage = "书架中的书籍都没有已缓存的章节"
                    showAlert = true
                } else {
                    shareItems = urls
                }
            }
        }
    }

    private func contentProvider(_ book: Book) -> (Int) -> String? {
        let service = BookContentService.shared
        let bookUrl = book.bookUrl
        return { index in
            service.getCachedChapterContent(bookUrl: bookUrl, chapterIndex: index)
        }
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Share Sheet (system share bridge)

#if os(iOS)
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
/// macOS stand-in: there is no shared activity controller; surface the file paths instead.
struct ActivityShareSheet: View {
    let items: [Any]

    var body: some View {
        VStack(spacing: 12) {
            Text("已导出到临时目录")
                .font(.headline)
            ForEach(items.compactMap { $0 as? URL }, id: \.absoluteString) { url in
                Text(url.path)
                    .font(.caption.monospaced())
                    .lineLimit(2)
            }
            Button("拷贝路径") {
                #if os(macOS)
                let paths = items.compactMap { ($0 as? URL)?.path }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
                #endif
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
#endif

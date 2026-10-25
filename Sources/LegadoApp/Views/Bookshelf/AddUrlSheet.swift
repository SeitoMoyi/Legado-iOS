import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

// MARK: - Add URL Sheet (Plan 第一批 书架二级菜单 ③: 添加网址)
//
// Android `SourceManageDialog`/添加网址: paste a chapter URL, resolve the owning book source
// via `bookUrlPattern` / host match, crawl the detail+TOC and put the book on the shelf.
// The iOS flow keeps every step visible: match → crawl → add → open.

public struct AddUrlSheet: View {
    @ObservedObject private var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    let initialURL: String
    var onAdded: ((Book) -> Void)? = nil

    @State private var urlString: String = ""
    @State private var phase: Phase = .input
    @State private var matchedSource: BookSource? = nil
    @State private var addedBook: Book? = nil
    @State private var errorMessage: String = ""

    enum Phase: Equatable {
        case input
        case matching
        case crawling
        case failed
    }

    public init(url: String = "", onAdded: ((Book) -> Void)? = nil) {
        self.initialURL = url
        self.onAdded = onAdded
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("书籍网址 (章节页或书籍详情页 URL)")) {
                    TextField("https://example.com/book/1.html", text: $urlString)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        #endif
                }

                if phase == .matching {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在按书源匹配网址...")
                                .foregroundColor(.secondary)
                        }
                    }
                } else if phase == .crawling {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在抓取书籍信息与目录...")
                                .foregroundColor(.secondary)
                        }
                    }
                } else if phase == .failed {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        start()
                    } label: {
                        Text(phase == .input ? "添加到书架" : "重试")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && matchedSource == nil)
                }

                if let source = matchedSource, phase != .matching {
                    Section(header: Text("匹配书源")) {
                        Text(source.bookSourceName)
                        Text(source.bookSourceUrl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("添加网址")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if urlString.isEmpty && !initialURL.isEmpty {
                    urlString = initialURL
                }
            }
        }
    }

    private func start() {
        let target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        phase = .matching
        errorMessage = ""
        Task {
            // 1. Resolve the owning source.
            guard let match = BookUrlMatcher.match(url: target, sources: bookStore.sources) else {
                await MainActor.run {
                    phase = .failed
                    errorMessage = "没有书源能处理这个网址。请确认已导入对应书源，或尝试书籍详情页地址。"
                }
                return
            }
            await MainActor.run {
                matchedSource = match.source
                phase = .crawling
            }

            // 2. Crawl detail + TOC with a probe book carrying the pasted URL.
            let probe = Book(bookUrl: target, name: "", author: "",
                             origin: match.source.bookSourceUrl,
                             originName: match.source.bookSourceName)
            do {
                let result = try await BookContentService.shared.fetchBookDetailResult(book: probe,
                                                                                       source: match.source)
                guard !result.chapters.isEmpty else {
                    await MainActor.run {
                        phase = .failed
                        errorMessage = "书源返回了空目录，无法添加。"
                    }
                    return
                }
                var book = result.book
                if book.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    book.name = URL(string: target)?.host ?? "未命名"
                }
                book.origin = match.source.bookSourceUrl
                book.originName = match.source.bookSourceName
                let saved = bookStore.saveOrUpdateBook(book)
                bookStore.saveChapters(result.chapters, for: saved.bookUrl)
                bookStore.markTocFetched(bookUrl: saved.bookUrl)
                await MainActor.run {
                    addedBook = saved
                    onAdded?(saved)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    phase = .failed
                    errorMessage = "抓取失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Shelf Group Display Sheet (Plan 第一批 书架二级菜单 ⑤: 书架管理)
//
// Android's 书架管理 toggles per-group visibility; `BookGroup.show` already drives the
// shelf's group pill bar, so this page is the missing editor for it.

public struct ShelfGroupDisplaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [BookGroup] = []

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("显示在书架分组栏"),
                        footer: Text("关闭的分组不会出现在书架顶部分组胶囊栏，但分组内的书籍仍在「全部」中可见。")) {
                    ForEach($groups) { $group in
                        Toggle(isOn: Binding(
                            get: { group.show },
                            set: { newValue in
                                group.show = newValue
                                BookGroupStore.save(groups)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.groupName)
                                Text("\(bookCount(for: group)) 本")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("书架管理")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                groups = BookGroupStore.load()
            }
        }
    }

    private func bookCount(for group: BookGroup) -> Int {
        ShelfFilter.books(BookStore.shared.bookshelf, inGroup: group.groupId).count
    }
}

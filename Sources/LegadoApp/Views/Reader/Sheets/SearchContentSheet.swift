import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// 书内全书多章并发搜索 (Plan Phase 1 Part 5) — the Android `SearchContentActivity` counterpart.
///
/// Keyword or regex across every chapter: cached chapters are searched offline, misses are
/// fetched with bounded concurrency, and results stream in chapter order. Tapping a hit jumps
/// the reader to the exact chapter and character offset.
struct SearchContentSheet: View {
    let book: Book
    let chapters: [BookChapter]
    /// Jump callback: (chapterIndex, charPosInChapter).
    let onJump: (Int, Int) -> Void
    /// Supplies the 净化 context per chapter so the searched text matches what the reader
    /// paginates (hits' char offsets are only meaningful on that basis).
    var processContext: ((BookChapter) -> ProcessContext)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var isRegex: Bool = false
    @State private var includeUncached: Bool = true
    @State private var hits: [BookContentSearchService.Hit] = []
    @State private var isSearching: Bool = false
    @State private var searchedCount: Int = 0
    @State private var invalidRegex: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    private var source: BookSource? {
        BookStore.shared.findSource(for: book)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                Divider()
                if isSearching && hits.isEmpty {
                    Spacer()
                    ProgressView()
                    Text("正在搜索 \(searchedCount)/\(chapters.count) 章…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                    Spacer()
                } else if hits.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(searchedCount > 0 ? "未找到匹配内容" : "输入关键字搜索全书正文")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !includeUncached {
                            Text("（仅搜索已缓存章节）")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    Spacer()
                } else {
                    resultList
                }
            }
            .navigationTitle("全书搜索")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        searchTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField(isRegex ? "正则表达式…" : "关键字…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit { startSearch() }
                    #endif

                Button(isSearching ? "停止" : "搜索") {
                    if isSearching {
                        searchTask?.cancel()
                    } else {
                        startSearch()
                    }
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSearching ? Color.orange : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            HStack(spacing: 14) {
                Toggle("正则", isOn: $isRegex)
                Toggle("含未缓存章节 (联网)", isOn: $includeUncached)
                Spacer()
                if !hits.isEmpty {
                    Text("\(hits.count) 处 · \(searchedCount)/\(chapters.count) 章")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)

            if invalidRegex {
                Text("正则表达式无效，请检查语法")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    private var resultList: some View {
        List(hits) { hit in
            Button {
                dismiss()
                onJump(hit.chapterIndex, hit.charPosition)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("第 \(hit.chapterIndex + 1) 章")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        Text(hit.chapterTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    highlightedSnippet(hit)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        #if os(iOS)
        .listStyle(.plain)
        #endif
    }

    /// One-line snippet with the matched span emphasised.
    private func highlightedSnippet(_ hit: BookContentSearchService.Hit) -> Text {
        guard !hit.matchedText.isEmpty,
              let range = hit.snippet.range(of: hit.matchedText) else {
            return Text(hit.snippet)
        }
        // Case-sensitive splice is fine: the snippet was cut around the exact match text.
        return Text(hit.snippet[..<range.lowerBound])
            + Text(hit.matchedText).bold().foregroundColor(.accentColor)
            + Text(hit.snippet[range.upperBound...])
    }

    // MARK: - Driver

    private func startSearch() {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        // Validate regex up-front instead of failing silently mid-search.
        if isRegex {
            guard (try? NSRegularExpression(pattern: raw)) != nil else {
                invalidRegex = true
                return
            }
        }
        invalidRegex = false

        searchTask?.cancel()
        hits = []
        searchedCount = 0
        isSearching = true

        let stream = BookContentSearchService.shared.search(
            book: book,
            source: source,
            chapters: chapters,
            query: raw,
            isRegex: isRegex,
            includeUncached: includeUncached,
            context: processContext
        )

        searchTask = Task {
            for await event in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    switch event {
                    case .progress(let p):
                        searchedCount = p.chaptersSearched
                    case .hit(let hit):
                        hits.append(hit)
                    case .finished:
                        isSearching = false
                    }
                }
            }
            await MainActor.run { isSearching = false }
        }
    }
}

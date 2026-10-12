import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// 换源 — replaces the current book with the same title on another source, or borrows one
/// chapter's text from it.
///
/// Two modes share the candidate list because Android's two dialogs share a view model:
/// - `.wholeBook` rewrites the shelf entry and remaps the reading position.
/// - `.singleChapter(book, chapterIndex:)` writes text fetched elsewhere into the current
///   chapter's cache, leaving the book's own source untouched — there is no per-chapter
///   source override in the data model, which is also true on Android.
struct ChangeSourceSheet: View {
    enum Mode {
        case wholeBook
        case singleChapter(chapterIndex: Int)
    }

    let book: Book
    let mode: Mode
    /// Title of the chapter being replaced; `ChapterMatcher` uses it to find the counterpart.
    var chapterTitle: String = ""
    /// Called with the picked candidate and its freshly fetched TOC (whole-book mode), or the
    /// replacement text for the current chapter (single-chapter mode).
    let onApply: (ChangeSourceCandidate, [BookChapter]) -> Void
    let onApplyChapterText: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookStore = BookStore.shared

    @State private var candidates: [ChangeSourceCandidate] = []
    @State private var isSearching = false
    @State private var searchGeneration = 0
    @State private var keyword = ""
    @State private var checkAuthor = true
    @State private var loadToc = false
    @State private var applyingId: String?
    @State private var message: String?
    @State private var showMessage = false

    private var visible: [ChangeSourceCandidate] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return candidates }
        return candidates.filter {
            $0.found.name.localizedCaseInsensitiveContains(needle)
                || $0.found.author.localizedCaseInsensitiveContains(needle)
                || $0.source.bookSourceName.localizedCaseInsensitiveContains(needle)
                || $0.source.bookSourceGroup?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("当前：\(book.originName.isEmpty ? book.bookUrl : book.originName)")) {
                    Toggle("校验作者", isOn: $checkAuthor)
                    Toggle("加载目录以预估章节", isOn: $loadToc)
                    Button(isSearching ? "停止搜索" : "重新搜索", action: toggleSearch)
                        .foregroundColor(isSearching ? .orange : .accentColor)
                }

                if candidates.isEmpty && !isSearching {
                    Text("还没有候选书源，或全部源都没有搜到同名书。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                ForEach(visible) { candidate in
                    row(candidate)
                }
            }
            .listStyle(.plain)
            .searchable(text: $keyword, prompt: "筛选结果")
            .navigationTitle(mode.navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay {
                if isSearching && candidates.isEmpty {
                    ProgressView("正在搜索所有书源…")
                }
            }
            .alert("换源", isPresented: $showMessage) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .task { startSearch() }
            .onDisappear { isSearching = false }
        }
    }

    @ViewBuilder
    private func row(_ candidate: ChangeSourceCandidate) -> some View {
        Button {
            apply(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.source.bookSourceName)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    if applyingId == candidate.id {
                        ProgressView()
                    } else if let count = candidate.chapterCount {
                        Text("\(count) 章")
                    }
                }
                Text("\(candidate.found.author) · \(candidate.found.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let group = candidate.source.displayGroup, !group.isEmpty {
                    Text(group)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(applyingId != nil)
    }

    private func toggleSearch() {
        if isSearching {
            isSearching = false
            searchGeneration += 1
        } else {
            startSearch()
        }
    }

    /// `searchGeneration` makes "停止" stick: the stream keeps producing until the loop
    /// notices the generation changed, so cancelling the task alone is not enough.
    @MainActor
    private func startSearch() {
        guard !isSearching else { return }
        isSearching = true
        candidates = []
        searchGeneration += 1
        let generation = searchGeneration
        let sources = bookStore.sources
        let check = checkAuthor
        let target = book

        Task { @MainActor in
            for await candidate in ChangeSourceService.shared.candidates(book: target, sources: sources,
                                                                        checkAuthor: check) {
                guard isSearching, generation == searchGeneration else { return }
                candidates.append(candidate)
                guard loadToc else { continue }
                let enriched = await ChangeSourceService.shared.enrich(candidate, book: target)
                guard generation == searchGeneration,
                      let index = candidates.firstIndex(where: { $0.id == enriched.id }) else { continue }
                candidates[index] = enriched
            }
            if generation == searchGeneration { isSearching = false }
        }
    }

    private func apply(_ candidate: ChangeSourceCandidate) {
        applyingId = candidate.id
        let book = self.book
        Task {
            defer { DispatchQueue.main.async { applyingId = nil } }
            let chapters = (try? await BookContentService.shared.fetchChapterList(
                book: Book(bookUrl: candidate.found.bookUrl, name: candidate.found.name,
                          author: candidate.found.author, origin: candidate.source.bookSourceUrl,
                          originName: candidate.source.bookSourceName, tocUrl: candidate.found.bookUrl),
                source: candidate.source)) ?? []

            guard !chapters.isEmpty else {
                await MainActor.run {
                    message = "该书源取不到目录"
                    showMessage = true
                }
                return
            }

            switch mode {
            case .wholeBook:
                await MainActor.run { onApply(candidate, chapters) }
            case .singleChapter(let chapterIndex):
                let mapped = ChapterMatcher.mapChapter(oldIndex: chapterIndex,
                                                      oldTitle: chapterTitle,
                                                      oldCount: max(book.totalChapterNum, 1),
                                                      newTitles: chapters.map { $0.title })
                guard mapped < chapters.count else { return }
                let text = (try? await BookContentService.shared.fetchChapterContent(
                    chapter: chapters[mapped], source: candidate.source)) ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run {
                        message = "该书源这一章没有正文"
                        showMessage = true
                    }
                    return
                }
                await MainActor.run { onApplyChapterText(text) }
            }
        }
    }
}

extension ChangeSourceSheet.Mode: Identifiable {
    public var id: String {
        switch self {
        case .wholeBook: return "wholeBook"
        case .singleChapter(let index): return "chapter-\(index)"
        }
    }
}

private extension ChangeSourceSheet.Mode {
    var navigationTitle: String {
        switch self {
        case .wholeBook: return "整书换源"
        case .singleChapter: return "本章换源"
        }
    }
}

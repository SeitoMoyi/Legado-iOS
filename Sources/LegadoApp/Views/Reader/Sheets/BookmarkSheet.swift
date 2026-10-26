import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Bookmark list for one book. Tap jumps, long-press deletes, and the trailing button edits
/// the note. Mirrors Android's `BookmarkFragment`.
struct BookmarkSheet: View {
    let book: Book
    let onJump: (Bookmark) -> Void

    @ObservedObject var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var editing: Bookmark?

    private var results: [Bookmark] {
        bookStore.searchBookmarks(book: book, keyword: keyword)
    }

    var body: some View {
        NavigationView {
            Group {
                if results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text(keyword.isEmpty ? "这本书还没有书签" : "没有匹配的书签")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(results) { bookmark in
                            row(bookmark)
                        }
                        .onDelete { offsets in
                            let times = offsets.map { results[$0].time }
                            for time in times { bookStore.deleteBookmark(time: time) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $keyword, prompt: "搜索书签")
            .navigationTitle("书签 (\(results.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(item: $editing) { bookmark in
            BookmarkEditorSheet(bookmark: bookmark, isNew: false) { saved in
                bookStore.updateBookmark(saved)
            } onDelete: { removed in
                bookStore.deleteBookmark(time: removed.time)
            }
        }
    }

    private func row(_ bookmark: Bookmark) -> some View {
        Button {
            onJump(bookmark)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.chapterName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                if !bookmark.bookText.isEmpty {
                    Text(bookmark.bookText)
                        .font(.system(size: 13))
                        .lineLimit(3)
                }
                if !bookmark.content.isEmpty {
                    Text(bookmark.content)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(bookmark.time) / 1000)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.vertical, 3)
        }
        .contextMenu {
            Button("编辑") { editing = bookmark }
            Button("删除", role: .destructive) { bookStore.deleteBookmark(time: bookmark.time) }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

/// Add/edit dialog. `chapterName` is fixed to where the bookmark was taken, matching
/// Android's read-only 章节名 row.
struct BookmarkEditorSheet: View {
    @State var bookmark: Bookmark
    let isNew: Bool
    let onSave: (Bookmark) -> Void
    var onDelete: ((Bookmark) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("章节")) {
                    Text(bookmark.chapterName.isEmpty ? "未命名章节" : bookmark.chapterName)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("原文")) {
                    TextField("书签所在段落", text: $bookmark.bookText)
                }

                Section(header: Text("备注")) {
                    TextField("笔记、感想…", text: $bookmark.content)
                }

                // A destructive row rather than a toolbar item: ToolbarContentBuilder has no
                // conditional content before macOS 13.
                if !isNew {
                    Button("删除此书签", role: .destructive) {
                        onDelete?(bookmark)
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle(isNew ? "添加书签" : "编辑书签")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        onSave(bookmark)
                        dismiss()
                    }
                }
            }
        }
    }
}

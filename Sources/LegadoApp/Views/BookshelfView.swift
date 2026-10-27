import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif
import UniformTypeIdentifiers

public enum BookshelfSortOrder: Int, CaseIterable {
    case recentRead = 0
    case recentUpdate = 1
    case name = 2
    case author = 3
    case manual = 4

    public var label: String {
        switch self {
        case .recentRead: return "按最近阅读"
        case .recentUpdate: return "按最近更新"
        case .name: return "按书名排序"
        case .author: return "按作者排序"
        case .manual: return "手动排序（可拖拽）"
        }
    }
}

public struct BookshelfView: View {
    @ObservedObject var bookStore = BookStore.shared
    @AppStorage("legado_bookshelf_grid_mode") private var isGridMode: Bool = false
    @AppStorage("legado_bookshelf_sort_order") private var sortOrderRaw: Int = BookshelfSortOrder.recentRead.rawValue

    @State private var selectedBook: Book? = nil
    @State private var navigateToDetailBook: Book? = nil
    @State private var isSearchActive: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var importErrorMessage: String? = nil
    @State private var showImportAlert: Bool = false

    // Multi-select batch state
    @State private var isSelecting: Bool = false
    @State private var selectedBookUrls: Set<String> = []
    @State private var showBatchDeleteConfirm: Bool = false
    @State private var selectedGroupId: Int64 = BookGroup.idAll
    @State private var showMoveGroupDialog: Bool = false
    @ObservedObject private var launchRouter = LaunchRouter.shared
    @State private var showGroupManageSheet: Bool = false

    // 书架二级菜单 (Plan 第一批): 缓存/导出、书单导出、添加网址、远程书籍、书架管理
    @State private var showCacheManage: Bool = false
    @State private var showRemoteBooks: Bool = false
    @State private var showAddUrl: Bool = false
    @State private var showShelfManage: Bool = false
    @State private var showShelfImport = false
    @State private var shelfShareItems: [Any]? = nil
    @State private var shelfAlertTitle: String = ""
    @State private var shelfAlertMessage: String = ""
    @State private var showShelfAlert: Bool = false

    public init() {}

    private var bookGroups: [BookGroup] {
        BookGroupStore.load().filter { $0.show }
    }

    private var currentGroupFilteredBooks: [Book] {
        ShelfFilter.books(bookStore.bookshelf, inGroup: selectedGroupId, groups: BookGroupStore.load(), legacyAssignments: !bookStore.usesGroupBitmasks)
    }
    private var sortOrder: BookshelfSortOrder {
        BookshelfSortOrder(rawValue: sortOrderRaw) ?? .recentRead
    }

    private var sortedBookshelf: [Book] {
        currentGroupFilteredBooks.sorted { b1, b2 in
            switch sortOrder {
            case .manual:
                // Stable: ties keep arrival order (an unset `order` is 0 for everyone)
                return b1.order < b2.order
            case .recentRead:
                let t1 = max(b1.durChapterTime, b1.lastCheckTime)
                let t2 = max(b2.durChapterTime, b2.lastCheckTime)
                return t1 > t2
            case .recentUpdate:
                return b1.lastCheckTime > b2.lastCheckTime
            case .name:
                return b1.name.localizedCompare(b2.name) == .orderedAscending
            case .author:
                return b1.author.localizedCompare(b2.author) == .orderedAscending
            }
        }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    // Group filter pills bar
                    if !bookStore.bookshelf.isEmpty && !bookGroups.isEmpty {
                        groupTabBar
                    }

                    Group {
                        if bookStore.bookshelf.isEmpty {
                            emptyShelfView
                        } else if isGridMode {
                            ScrollView {
                                LazyVGrid(columns: gridColumns, spacing: 16) {
                                    ForEach(sortedBookshelf) { book in
                                        BookGridCell(
                                            book: book,
                                            isSelecting: isSelecting,
                                            isSelected: selectedBookUrls.contains(book.bookUrl)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if isSelecting {
                                                toggleSelection(for: book.bookUrl)
                                            } else {
                                                selectedBook = book
                                            }
                                        }
                                        .onLongPressGesture {
                                            if !isSelecting {
                                                navigateToDetailBook = book
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .refreshable {
                                await refreshVisibleBooks()
                            }
                        } else {
                            List {
                                ForEach(sortedBookshelf) { book in
                                    HStack(spacing: 12) {
                                        if isSelecting {
                                            Image(systemName: selectedBookUrls.contains(book.bookUrl) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedBookUrls.contains(book.bookUrl) ? .accentColor : .secondary)
                                                .font(.system(size: 20))
                                        }
                                        BookRow(book: book)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelecting {
                                            toggleSelection(for: book.bookUrl)
                                        } else {
                                            selectedBook = book
                                        }
                                    }
                                    .onLongPressGesture {
                                        if !isSelecting {
                                            navigateToDetailBook = book
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    let urls = indexSet.map { sortedBookshelf[$0].bookUrl }
                                    for url in urls { bookStore.removeBook(bookUrl: url) }
                                }
                                .onMove { source, destination in
                                    var reordered = sortedBookshelf
                                    reordered.move(fromOffsets: source, toOffset: destination)
                                    bookStore.applyManualOrder(reordered)
                                }
                            }
                            .deleteDisabled(sortOrder == .manual)
                            .modifier(ManualSortEditMode(isActive: sortOrder == .manual))
                            .refreshable {
                                await refreshVisibleBooks()
                            }
                            #if os(iOS)
                            .listStyle(.insetGrouped)
                            #else
                            .listStyle(.inset)
                            #endif
                        }
                    }

                    if isSelecting {
                        batchActionBar
                    }
                }
                .background(
                    Group {
                        // Programmatic push to SearchBookView
                        NavigationLink(
                            isActive: $isSearchActive,
                            destination: { SearchBookView() },
                            label: { EmptyView() }
                        )

                        // Programmatic push to BookDetailView on long press
                        NavigationLink(
                            isActive: Binding(
                                get: { navigateToDetailBook != nil },
                                set: { if !$0 { navigateToDetailBook = nil } }
                            ),
                            destination: {
                                if let b = navigateToDetailBook {
                                    let source = bookStore.findSource(for: b)
                                    BookDetailView(book: b, source: source)
                                } else {
                                    EmptyView()
                                }
                            },
                            label: { EmptyView() }
                        )
                    }
                    .hidden()
                    .frame(width: 0, height: 0)
                )
                .navigationTitle("书架")
                #if os(iOS)
                .onAppear { TabBarVisibility.setHidden(false) }
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if isSelecting {
                            Button("完成") {
                                withAnimation {
                                    isSelecting = false
                                    selectedBookUrls.removeAll()
                                }
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button(action: { isSearchActive = true }) {
                                    Image(systemName: "magnifyingglass")
                                }

                                Menu {
                                    // 顺序对齐 Android main_bookshelf.xml：更新目录 → 添加本地 →
                                    // 分组管理 → 书架布局（视图+排序）→ 选择/导出（iOS 已有项）
                                    Button {
                                        Task { await bookStore.refreshAllBooks() }
                                    } label: {
                                        Label("更新目录", systemImage: "arrow.triangle.2.circlepath")
                                    }

                                    Button {
                                        showFileImporter = true
                                    } label: {
                                        Label("添加本地 (EPUB/TXT)", systemImage: "doc.badge.plus")
                                    }

                                    Button {
                                        showAddUrl = true
                                    } label: {
                                        Label("添加网址", systemImage: "link.badge.plus")
                                    }

                                    Button {
                                        showRemoteBooks = true
                                    } label: {
                                        Label("远程书籍 (WebDAV)", systemImage: "icloud.and.arrow.down")
                                    }

                                    Button {
                                        showCacheManage = true
                                    } label: {
                                        Label("缓存 / 导出", systemImage: "internaldrive")
                                    }

                                    Button {
                                        exportShelfJSON()
                                    } label: {
                                        Label("导出书单", systemImage: "square.and.arrow.up.on.square")
                                    }
                                    Button { showShelfImport = true } label: {
                                        Label("导入书单", systemImage: "square.and.arrow.down")
                                    }

                                    Button {
                                        showGroupManageSheet = true
                                    } label: {
                                        Label("分组管理", systemImage: "folder.badge.gearshape")
                                    }

                                    Button {
                                        showShelfManage = true
                                    } label: {
                                        Label("书架管理", systemImage: "square.grid.2x2")
                                    }

                                    Menu("书架布局") {
                                        Button {
                                            withAnimation { isGridMode.toggle() }
                                        } label: {
                                            Label(isGridMode ? "列表视图" : "三列网格视图",
                                                  systemImage: isGridMode ? "list.bullet" : "square.grid.3x2")
                                        }

                                        Menu("排序方式 (\(sortOrder.label))") {
                                            ForEach(BookshelfSortOrder.allCases, id: \.rawValue) { order in
                                                Button {
                                                    sortOrderRaw = order.rawValue
                                                } label: {
                                                    if sortOrder == order {
                                                        Label(order.label, systemImage: "checkmark")
                                                    } else {
                                                        Text(order.label)
                                                    }
                                                }
                                            }
                                        }
                                    } // 书架布局

                                    Button {
                                        withAnimation { isSelecting = true }
                                    } label: {
                                        Label("选择", systemImage: "checkmark.circle")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showGroupManageSheet) {
                    BookGroupManageSheet()
                }
                .sheet(isPresented: $showCacheManage) {
                    CacheManageView()
                }
                .sheet(isPresented: $showShelfImport) { ShelfImportView(bookStore: bookStore, groupID: max(0, selectedGroupId)) }
                .sheet(isPresented: $showRemoteBooks) {
                    RemoteBooksView { imported in
                        showRemoteBooks = false
                        selectedBook = imported
                    }
                }
                .sheet(isPresented: $showAddUrl) {
                    AddUrlSheet { added in
                        shelfAlertTitle = "已加入书架"
                        shelfAlertMessage = "「\(added.name)」已通过网址添加到书架"
                        showShelfAlert = true
                    }
                }
                .sheet(isPresented: $showShelfManage) {
                    ShelfGroupDisplaySheet()
                }
                .sheet(isPresented: Binding(
                    get: { shelfShareItems != nil },
                    set: { if !$0 { shelfShareItems = nil } }
                )) {
                    if let items = shelfShareItems {
                        ActivityShareSheet(items: items)
                    }
                }
                .alert(shelfAlertTitle, isPresented: $showShelfAlert) {
                    Button("确定", role: .cancel) {}
                } message: {
                    Text(shelfAlertMessage)
                }
                .sheet(isPresented: $showMoveGroupDialog) {
                    BookGroupSelectionSheet(bookURLs: selectedBookUrls, onSaved: {
                        selectedBookUrls.removeAll()
                        isSelecting = false
                    })
                }
                .confirmationDialog("确认从书架移除选中的 \(selectedBookUrls.count) 本书籍？", isPresented: $showBatchDeleteConfirm, titleVisibility: .visible) {
                    Button("移除 (\(selectedBookUrls.count))", role: .destructive) {
                        bookStore.removeBooks(bookUrls: selectedBookUrls)
                        selectedBookUrls.removeAll()
                        isSelecting = false
                    }
                    Button("取消", role: .cancel) {}
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.epub, .plainText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        let canAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if canAccess { url.stopAccessingSecurityScopedResource() }
                        }
                        do {
                            let imported = try bookStore.importFile(from: url)
                            selectedBook = imported
                        } catch {
                            importErrorMessage = "导入失败: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    case .failure(let error):
                        importErrorMessage = "打开文件失败: \(error.localizedDescription)"
                        showImportAlert = true
                    }
                }
                .alert(importErrorMessage ?? "", isPresented: $showImportAlert) {
                    Button("确定", role: .cancel) {}
                }
                #if os(iOS)
                .fullScreenCover(item: $selectedBook) { book in
                    readerCoverView(for: book)
                }
                #endif
            }
            #if !os(iOS)
            if let book = selectedBook {
                readerCoverView(for: book)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .transition(.opacity)
                    .zIndex(999)
            }
            #endif
        }
        .onAppear { consumePendingBook() }
        .onChange(of: bookGroups.map(\.groupId)) { ids in
            if !ids.contains(selectedGroupId) { selectedGroupId = BookGroup.idAll }
        }
        .onChange(of: launchRouter.pendingBook) { _ in consumePendingBook() }
    }

    /// Opens the book a 「继续阅读」 quick action resolved to. The router parks it rather than
    /// presenting the reader itself, because the reader lives in this view's state.
    private func consumePendingBook() {
        guard let book = launchRouter.pendingBook else { return }
        launchRouter.pendingBook = nil
        selectedGroupId = BookGroup.idAll
        selectedBook = book
    }

    @MainActor
    private func refreshVisibleBooks() async {
        guard BookGroupStore.load().first(where: { $0.groupId == selectedGroupId })?.enableRefresh != false else { return }
        await bookStore.refreshAllBooks(bookURLs: Set(currentGroupFilteredBooks.map(\.bookUrl)))
    }

    private func toggleSelection(for url: String) {
        if selectedBookUrls.contains(url) {
            selectedBookUrls.remove(url)
        } else {
            selectedBookUrls.insert(url)
        }
    }

    /// 导出书单: the same `bookshelf.json` shape the WebDAV backup writes.
    private func exportShelfJSON() {
        do {
            let url = try BookExportService.exportBookshelfJSON(books: bookStore.bookshelf)
            shelfShareItems = [url]
        } catch {
            shelfAlertTitle = "导出失败"
            shelfAlertMessage = error.localizedDescription
            showShelfAlert = true
        }
    }

    private var batchActionBar: some View {
        let allUrls = Set(sortedBookshelf.map { $0.bookUrl })
        let allSelected = !allUrls.isEmpty && allUrls.isSubset(of: selectedBookUrls)

        return HStack(spacing: 16) {
            Button(allSelected ? "取消全选" : "全选") {
                if allSelected {
                    selectedBookUrls.removeAll()
                } else {
                    selectedBookUrls = allUrls
                }
            }
            .font(.caption.weight(.medium))

            Button("反选") {
                for u in allUrls {
                    if selectedBookUrls.contains(u) {
                        selectedBookUrls.remove(u)
                    } else {
                        selectedBookUrls.insert(u)
                    }
                }
            }
            .font(.caption.weight(.medium))

            Spacer()

            Button("清理缓存") {
                var clearedChapters = 0
                for u in selectedBookUrls {
                    clearedChapters += BookContentService.shared.getCacheCount(for: u)
                    BookContentService.shared.clearCache(for: u)
                }
                importErrorMessage = "已清理所选 \(selectedBookUrls.count) 本书的离线缓存（共 \(clearedChapters) 章）"
                showImportAlert = true
            }
            .font(.caption.weight(.medium))
            .disabled(selectedBookUrls.isEmpty)

            Button("分组") {
                showMoveGroupDialog = true
            }
            .font(.caption.weight(.medium))
            .disabled(selectedBookUrls.isEmpty)

            Button("移除(\(selectedBookUrls.count))") {
                showBatchDeleteConfirm = true
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.red)
            .disabled(selectedBookUrls.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.12))
    }

    private var groupTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bookGroups) { g in
                    let isSelected = (selectedGroupId == g.groupId)
                    Button {
                        selectedGroupId = g.groupId
                    } label: {
                        Text(g.groupName)
                            .font(.caption.weight(isSelected ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func readerCoverView(for book: Book) -> some View {
        let source = bookStore.findSource(for: book)
        if source?.bookSourceType == 1 || book.isAudioBook {
            AudioPlayView(book: book, source: source, onDismiss: {
                selectedBook = nil
            })
        } else {
            NavigationView {
                ReaderView(book: book, source: source, onDismiss: {
                    selectedBook = nil
                })
            }
        }
    }

    private var emptyShelfView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            Text("书架空空如也")
                .font(.headline)
            Text("可点击右上角放大镜搜索网络小说，或点击“+”导入本地书籍")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: { isSearchActive = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("前往全网搜索")
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - BookRow (Legado Android Style)

struct BookRow: View {
    let book: Book

    private var unreadCount: Int {
        guard book.totalChapterNum > 0 else { return 0 }
        let readCount = book.durChapterTitle != nil ? (book.durChapterIndex + 1) : 0
        return max(0, book.totalChapterNum - readCount)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Book cover with Unread Red Badge
            ZStack(alignment: .topTrailing) {
                if let coverUrlStr = book.displayCoverURL, let url = URL(string: coverUrlStr) {
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
                    .frame(width: 54, height: 74)
                    .cornerRadius(6)
                    .clipped()
                } else {
                    coverPlaceholder
                }

                // Red dot / badge indicating unread chapters count
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }

            // Info column: Title, Author, Latest Chapter, Read Progress (No source)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if !book.author.isEmpty && book.author != "未知作者" {
                    Text(book.author)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let latest = book.latestChapterTitle, !latest.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "book")
                            .font(.system(size: 10))
                        Text(latest)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                HStack {
                    if let chapter = book.durChapterTitle, !chapter.isEmpty {
                        Text("已读: \(chapter)")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    } else {
                        Text("未读")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 54, height: 74)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor.opacity(0.8))
            )
    }
}

// MARK: - BookGridCell (3-Column Cover Grid Item)

struct BookGridCell: View {
    let book: Book
    var isSelecting: Bool = false
    var isSelected: Bool = false

    private var unreadCount: Int {
        guard book.totalChapterNum > 0 else { return 0 }
        let readCount = book.durChapterTitle != nil ? (book.durChapterIndex + 1) : 0
        return max(0, book.totalChapterNum - readCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let coverUrlStr = book.displayCoverURL, let url = URL(string: coverUrlStr) {
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
                    .frame(height: 132)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                    .clipped()
                } else {
                    coverPlaceholder
                }

                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .accentColor : .white.opacity(0.85))
                        .background(Circle().fill(Color.black.opacity(0.35)))
                        .padding(6)
                } else if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }

            Text(book.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(book.durChapterTitle ?? "未读")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.12))
            .frame(height: 132)
            .frame(maxWidth: .infinity)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.title)
                    .foregroundColor(.accentColor.opacity(0.8))
            )
    }
}

// MARK: - BookGroupManageSheet (Android GroupManageDialog Counterpart)

struct BookGroupManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = BookStore.shared
    @State private var groups: [BookGroup] = []
    @State private var editing: BookGroup?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("书架分组列表")) {
                    ForEach(groups) { group in
                        Button { editing = group } label: {
                            HStack {
                                Text(group.groupName).font(.subheadline.bold())
                                Spacer()
                                Text(group.groupId > 0 ? "自定义分组" : "系统内置").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { indexes in
                        store.deleteBookGroups(Set(indexes.map { groups[$0].groupId }))
                        groups = BookGroupStore.load()
                    }
                }
                if let issue = store.groupMigrationIssue { Text(issue).foregroundColor(.secondary) }
            }
            .navigationTitle("分组管理")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = BookGroup(groupId: 0) } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing, onDismiss: { groups = BookGroupStore.load() }) { group in
                BookGroupNameEditor(group: group)
            }
            .onAppear { groups = BookGroupStore.load() }
        }
    }
}


/// Drag handles only materialise when a List is in edit mode; `\.editMode` is iOS-only,
/// so the manual-sort shelf wraps it (macOS falls back to normal reorder controls).
struct ManualSortEditMode: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content.environment(\.editMode, .constant(isActive ? .active : .inactive))
        #else
        content
        #endif
    }
}

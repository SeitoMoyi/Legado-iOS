import SwiftUI
import WebKit
#if canImport(LegadoCore)
import LegadoCore
#endif

// MARK: - RssSourceListView (订阅首页：订阅源列表、分类聚合与收藏)

public struct RssSourceListView: View {
    @State private var sources: [RssSource] = []
    @State private var searchText: String = ""
    @State private var selectedSourceForArticles: RssSource? = nil
    @State private var showFavorites: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var editingSource: RssSource? = nil
    @State private var showDebugSheet: Bool = false
    @State private var debuggingSource: RssSource? = nil
    @State private var showImportSheet: Bool = false
    @State private var importText: String = ""
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init() {}

    private var filteredSources: [RssSource] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return sources }
        return sources.filter {
            $0.sourceName.localizedCaseInsensitiveContains(needle) ||
            $0.sourceUrl.localizedCaseInsensitiveContains(needle) ||
            ($0.sourceGroup?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if sources.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(filteredSources) { source in
                            Button {
                                selectedSourceForArticles = source
                            } label: {
                                HStack(spacing: 12) {
                                    sourceIcon(for: source)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.sourceName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        HStack(spacing: 6) {
                                            if let group = source.sourceGroup, !group.isEmpty {
                                                Text(group)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.12))
                                                    .foregroundColor(.secondary)
                                                    .cornerRadius(4)
                                            }
                                            Text(source.sourceUrl)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("编辑") {
                                    editingSource = source
                                    showEditSheet = true
                                }
                                Button("调试订阅源") {
                                    debuggingSource = source
                                    showDebugSheet = true
                                }
                                Button("置顶") {
                                    pinSource(source)
                                }
                                Button("删除", role: .destructive) {
                                    sources.removeAll { $0.sourceUrl == source.sourceUrl }
                                    RssStore.saveSources(sources)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            sources.remove(atOffsets: indexSet)
                            RssStore.saveSources(sources)
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .searchable(text: $searchText, prompt: "搜索订阅源名称或分组")
            .navigationTitle("订阅")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showFavorites = true
                        } label: {
                            Image(systemName: "star")
                        }

                        Menu {
                            Button {
                                editingSource = RssSource()
                                showEditSheet = true
                            } label: {
                                Label("新建订阅源", systemImage: "plus")
                            }

                            Button {
                                showImportSheet = true
                            } label: {
                                Label("导入订阅源 JSON", systemImage: "doc.badge.plus")
                            }

                            Button {
                                sources = RssStore.defaultSources
                                RssStore.saveSources(sources)
                            } label: {
                                Label("恢复默认订阅源", systemImage: "arrow.clockwise")
                            }

                            Button {
                                if let json = RssStore.exportSourcesJSON(sources) {
                                    copyToClipboard(json)
                                    alertMessage = "已将全部订阅源导出为 JSON 至剪贴板"
                                    showAlert = true
                                }
                            } label: {
                                Label("导出全部至剪贴板", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedSourceForArticles) { source in
                RssArticleListView(source: source)
            }
            .sheet(isPresented: $showFavorites) {
                RssStarListView()
            }
            .sheet(isPresented: $showEditSheet) {
                if let s = editingSource {
                    RssSourceEditSheet(source: s) { saved in
                        if let idx = sources.firstIndex(where: { $0.sourceUrl == saved.sourceUrl }) {
                            sources[idx] = saved
                        } else {
                            sources.insert(saved, at: 0)
                        }
                        RssStore.saveSources(sources)
                    }
                }
            }
            .sheet(isPresented: $showDebugSheet) {
                if let s = debuggingSource {
                    RssSourceDebugSheet(source: s)
                }
            }
            .sheet(isPresented: $showImportSheet) {
                NavigationView {
                    VStack(spacing: 12) {
                        TextEditor(text: $importText)
                            .frame(minHeight: 180)
                            .border(Color.secondary.opacity(0.2))
                        Button("导入") {
                            sources = RssStore.importSourcesJSON(importText, into: sources)
                            RssStore.saveSources(sources)
                            showImportSheet = false
                            importText = ""
                        }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("导入订阅源 JSON")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showImportSheet = false }
                        }
                    }
                }
            }
            .alert(alertMessage ?? "", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            }
            .onAppear {
                sources = RssStore.loadSources()
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.6))
            Text("暂无订阅源")
                .font(.headline)
            Text("点击右上角菜单可导入或恢复预装订阅源")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("加载预装订阅源") {
                sources = RssStore.defaultSources
                RssStore.saveSources(sources)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @ViewBuilder
    private func sourceIcon(for source: RssSource) -> some View {
        if let icon = source.sourceIcon, let url = URL(string: icon) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else {
                    Image(systemName: "newspaper.fill").foregroundColor(.accentColor)
                }
            }
            .frame(width: 36, height: 36)
            .cornerRadius(6)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "newspaper.fill").foregroundColor(.accentColor))
        }
    }

    private func pinSource(_ source: RssSource) {
        guard let idx = sources.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) else { return }
        let s = sources.remove(at: idx)
        sources.insert(s, at: 0)
        RssStore.saveSources(sources)
    }

    private func copyToClipboard(_ str: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = str
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        #endif
    }
}

// MARK: - RssArticleListView (文章列表页)

public struct RssArticleListView: View {
    let source: RssSource
    @Environment(\.dismiss) private var dismiss

    @State private var currentStyle: Int = 0

    @State private var categories: [RssService.RssCategory] = []
    @State private var selectedCategoryUrl: String = ""
    @State private var articles: [RssArticle] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedArticleForRead: RssArticle? = nil
    // Plan Phase 1 Part 1.4: `ruleNextPage` 触底翻页；nil / 与当前页相同表示没有下一页。
    @State private var nextPageUrl: String? = nil
    @State private var isLoadingMore: Bool = false
    // Plan Phase 1 Part 1.5: 已读状态置灰与阅读历史落盘。
    @State private var readState: [String: Int64] = [:]

    public init(source: RssSource) {
        self.source = source
        self._currentStyle = State(initialValue: min(max(source.articleStyle, 0), 2))
    }

    private var articleStyle: Int {
        currentStyle
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                categoryPills

                if isLoading && articles.isEmpty {
                    Spacer()
                    ProgressView()
                    Text("正在拉取最新文章...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if let err = errorMessage, articles.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("重试") { loadArticles() }
                    }
                    Spacer()
                } else if articleStyle == 2 {
                    articleGrid
                } else {
                    articleList
                }
            }
            .navigationTitle(source.sourceName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    styleMenu
                }
            }
            .sheet(item: $selectedArticleForRead) { article in
                RssArticleReaderView(article: article, source: source)
            }
            .onAppear {
                categories = RssService.shared.parseCategories(source: source)
                if selectedCategoryUrl.isEmpty, let first = categories.first {
                    selectedCategoryUrl = first.url
                }
                readState = RssStore.loadReadState()
                loadArticles()
            }
        }
    }

    // MARK: - 版式切换 (articleStyle: 0 左文右图 / 1 无图 / 2 双列网格)

    private var styleMenu: some View {
        Menu {
            Button {
                setArticleStyle(0)
            } label: {
                Label("左文右图", systemImage: articleStyle == 0 ? "checkmark" : "rectangle.split.horizontal")
            }
            Button {
                setArticleStyle(1)
            } label: {
                Label("无图模式", systemImage: articleStyle == 1 ? "checkmark" : "doc.text")
            }
            Button {
                setArticleStyle(2)
            } label: {
                Label("双列网格", systemImage: articleStyle == 2 ? "checkmark" : "rectangle.grid.2x2")
            }
        } label: {
            Image(systemName: articleStyle == 2 ? "rectangle.grid.2x2" : "list.bullet")
        }
    }

    /// Persists the chosen layout on the source so it survives restarts, like Android's `articleStyle`.
    private func setArticleStyle(_ style: Int) {
        currentStyle = style
        var all = RssStore.loadSources()
        if let idx = all.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) {
            all[idx].articleStyle = style
            RssStore.saveSources(all)
        }
    }

    // MARK: - Sub views

    private var categoryPills: some View {
        Group {
            if categories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { cat in
                            let isSel = (selectedCategoryUrl == cat.url)
                            Button {
                                selectedCategoryUrl = cat.url
                                loadArticles()
                            } label: {
                                Text(cat.title)
                                    .font(.caption.weight(isSel ? .bold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSel ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(isSel ? .white : .primary)
                                    .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var articleList: some View {
        List(articles) { article in
            articleRow(article)
                .onAppear { maybeLoadMore(current: article) }
        }
        .refreshable { loadArticles() }
        #if os(iOS)
        .listStyle(.plain)
        #endif
    }

    private var articleGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(articles) { article in
                    articleGridCard(article)
                        .onAppear { maybeLoadMore(current: article) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isLoadingMore {
                ProgressView()
                    .padding(.bottom, 12)
            }
        }
        .refreshable { loadArticles() }
    }

    /// Style 0 (左文右图) / Style 1 (无图) share one row layout; the image block is the only diff.
    private func articleRow(_ article: RssArticle) -> some View {
        Button {
            markRead(article)
            selectedArticleForRead = article
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    articleTitle(article)
                        .font(.subheadline.bold())

                    if let desc = article.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    articleMeta(article)
                }

                Spacer()

                if articleStyle == 0, let imgStr = article.image, let url = URL(string: imgStr) {
                    articleImage(url, imageWidth: 72, height: 54)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    /// Style 2: 双列网格卡片，图上文下。
    private func articleGridCard(_ article: RssArticle) -> some View {
        Button {
            markRead(article)
            selectedArticleForRead = article
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let imgStr = article.image, let url = URL(string: imgStr) {
                    articleImage(url, imageWidth: nil, height: 90)
                }
                articleTitle(article)
                    .font(.caption.bold())
                    .lineLimit(2)
                articleMeta(article)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    /// 已读文章标题置灰（Plan Phase 1 Part 1.5）。
    private func articleTitle(_ article: RssArticle) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(article.title)
                .foregroundColor(article.isRead(in: readState) ? .secondary : .primary)
            if article.isRead(in: readState) {
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }

    private func articleMeta(_ article: RssArticle) -> some View {
        Text(article.pubDate ?? "")
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.7))
    }

    private func articleImage(_ url: URL, imageWidth: CGFloat?, height: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            if let img = phase.image {
                img.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.1)
            }
        }
        .frame(maxWidth: imageWidth ?? .infinity, minHeight: height, maxHeight: height)
        .cornerRadius(6)
        .clipped()
    }

    // MARK: - Data flow

    private func loadArticles() {
        guard !selectedCategoryUrl.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let page = try await RssService.shared.fetchArticlePage(source: source, pageUrl: selectedCategoryUrl)
                await MainActor.run {
                    self.articles = page.articles
                    self.nextPageUrl = page.nextPageUrl
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "拉取失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    /// 触底自动拼装：仅当 `ruleNextPage` 给出且与已访问页不同时继续。
    private func maybeLoadMore(current: RssArticle) {
        guard current.id == articles.last?.id,
              !isLoadingMore, !isLoading,
              let next = nextPageUrl else { return }
        isLoadingMore = true

        Task {
            do {
                let page = try await RssService.shared.fetchArticlePage(source: source, pageUrl: next)
                await MainActor.run {
                    let seen = Set(articles.map { $0.link })
                    articles.append(contentsOf: page.articles.filter { !seen.contains($0.link) })
                    nextPageUrl = page.nextPageUrl
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run { isLoadingMore = false }
            }
        }
    }

    /// 已读标记 + 阅读历史落盘（RssStore.markArticleRead）。
    private func markRead(_ article: RssArticle) {
        RssStore.markArticleRead(article)
        readState = RssStore.loadReadState()
        if let idx = articles.firstIndex(where: { $0.id == article.id }) {
            articles[idx].read = true
        }
    }
}

// MARK: - RssArticleReaderView (文章详情与正文阅读页)

public struct RssArticleReaderView: View {
    let article: RssArticle
    let source: RssSource
    @Environment(\.dismiss) private var dismiss

    @State private var fullContent: String = ""
    @State private var isLoading: Bool = true
    @State private var isStarred: Bool = false

    public init(article: RssArticle, source: RssSource) {
        self.article = article
        self.source = source
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(article.title)
                        .font(.title2.bold())
                        .foregroundColor(.primary)

                    HStack(spacing: 10) {
                        Text(source.sourceName)
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        if let date = article.pubDate {
                            Text(date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("正在提取正文...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else {
                        Text(fullContent)
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("文章详情")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            toggleStar()
                        } label: {
                            Image(systemName: isStarred ? "star.fill" : "star")
                                .foregroundColor(isStarred ? .yellow : .accentColor)
                        }

                        if let url = URL(string: article.link) {
                            Link(destination: url) {
                                Image(systemName: "safari")
                            }
                        }
                    }
                }
            }
            .onAppear {
                checkStarStatus()
                loadContent()
            }
        }
    }

    private func checkStarStatus() {
        let stars = RssStore.loadStars()
        isStarred = stars.contains { $0.link == article.link }
    }

    private func toggleStar() {
        var stars = RssStore.loadStars()
        if let idx = stars.firstIndex(where: { $0.link == article.link }) {
            stars.remove(at: idx)
            isStarred = false
        } else {
            let star = RssStar(
                origin: article.origin,
                sort: article.sort,
                title: article.title,
                link: article.link,
                pubDate: article.pubDate,
                description: article.description,
                content: article.content,
                image: article.image
            )
            stars.insert(star, at: 0)
            isStarred = true
        }
        RssStore.saveStars(stars)
    }

    private func loadContent() {
        Task {
            let extracted = try? await RssService.shared.fetchArticleContent(article: article, source: source)
            await MainActor.run {
                self.fullContent = BookContentService.cleanHtml(extracted ?? article.content ?? article.description ?? "")
                self.isLoading = false
            }
        }
    }
}

// MARK: - RssStarListView (文章收藏夹)

struct RssStarListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stars: [RssStar] = []

    var body: some View {
        NavigationView {
            Group {
                if stars.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "star")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("暂无收藏文章")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(stars) { star in
                            if let url = URL(string: star.link) {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(star.title)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                        Text(star.sort)
                                            .font(.caption2)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            stars.remove(atOffsets: indexSet)
                            RssStore.saveStars(stars)
                        }
                    }
                }
            }
            .navigationTitle("收藏文章 (\(stars.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                stars = RssStore.loadStars()
            }
        }
    }
}

// MARK: - RssSourceEditSheet (订阅源编辑器)// MARK: - RssSourceEditSheet (订阅源编辑器 — 全字段，对齐 Android RssSourceEditActivity)

struct RssSourceEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var source: RssSource
    let onSave: (RssSource) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    HStack {
                        Text("源名称")
                            .frame(width: 80, alignment: .leading)
                        TextField("如：少数派", text: $source.sourceName)
                    }
                    HStack {
                        Text("源网址")
                            .frame(width: 80, alignment: .leading)
                        TextField("https://...", text: $source.sourceUrl)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }
                    HStack {
                        Text("源分组")
                            .frame(width: 80, alignment: .leading)
                        TextField("科技资讯", text: optionalBinding(\.sourceGroup))
                    }
                    HStack {
                        Text("源图标")
                            .frame(width: 80, alignment: .leading)
                        TextField("https://.../favicon.ico", text: optionalBinding(\.sourceIcon))
                            #if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }
                    Toggle("启用该订阅源", isOn: $source.enabled)
                }

                Section(header: Text("注释与说明")) {
                    TextEditor(text: optionalBinding(\.sourceComment))
                        .frame(minHeight: 50)
                        .font(.system(.caption, design: .monospaced))
                    HStack {
                        Text("变量说明")
                            .frame(width: 80, alignment: .leading)
                        TextField("变量用途说明 (variableComment)", text: optionalBinding(\.variableComment))
                    }
                }

                Section(header: Text("登录 (loginUrl / loginUi)")) {
                    TextEditor(text: optionalBinding(\.loginUrl))
                        .frame(minHeight: 50)
                        .font(.system(.caption, design: .monospaced))
                    TextEditor(text: optionalBinding(\.loginUi))
                        .frame(minHeight: 60)
                        .font(.system(.caption, design: .monospaced))
                    Text("loginUi 填 RowUi JSON 数组，如 [\"name\":\"账号\",\"type\":\"text\"]")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("请求头 (header)")) {
                    TextEditor(text: optionalBinding(\.header))
                        .frame(minHeight: 50)
                        .font(.system(.caption, design: .monospaced))
                    Text("JSON 对象，如 {\"User-Agent\":\"Mozilla/5.0\"}")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("分类与版式")) {
                    TextEditor(text: optionalBinding(\.sortUrl))
                        .frame(minHeight: 60)
                        .font(.system(.caption, design: .monospaced))
                    Text("每行一条「分类名::URL」，支持 {{page}}")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Toggle("单链接模式 (singleUrl)", isOn: $source.singleUrl)
                    Picker("文章版式", selection: $source.articleStyle) {
                        Text("左文右图").tag(0)
                        Text("无图模式").tag(1)
                        Text("双列网格").tag(2)
                    }
                }

                Section(header: Text("列表规则 (ruleArticles)")) {
                    ruleField("文章列表", placeholder: "//item", keyPath: \.ruleArticles)
                    ruleField("翻页规则", placeholder: "class.next@href 或 //a[text()=下一页]/@href", keyPath: \.ruleNextPage)
                    ruleField("标题规则", placeholder: "//title/text()", keyPath: \.ruleTitle)
                    ruleField("时间规则", placeholder: "//pubDate/text()", keyPath: \.rulePubDate)
                    ruleField("描述规则", placeholder: "//description/text()", keyPath: \.ruleDescription)
                    ruleField("图片规则", placeholder: "//enclosure/@url 或 img@src", keyPath: \.ruleImage)
                    ruleField("链接规则", placeholder: "//link/text()", keyPath: \.ruleLink)
                }

                Section(header: Text("正文与样式")) {
                    TextEditor(text: optionalBinding(\.ruleContent))
                        .frame(minHeight: 50)
                        .font(.system(.caption, design: .monospaced))
                    Text("正文提取规则 (ruleContent)，留空时使用列表内描述兜底")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("样式 (style)")
                            .frame(width: 80, alignment: .leading)
                        TextField("background-color:...", text: optionalBinding(\.style))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Toggle("启用 Js (enableJs)", isOn: $source.enableJs)
                    Toggle("以链接为 BaseUrl (loadWithBaseUrl)", isOn: $source.loadWithBaseUrl)
                }

                Section(header: Text("变量与排序")) {
                    TextEditor(text: optionalBinding(\.variable))
                        .frame(minHeight: 50)
                        .font(.system(.caption, design: .monospaced))
                    Text("源变量 (variable)，JSON 对象")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Stepper("排序权重 (customOrder): \(source.customOrder)", value: $source.customOrder, in: -9999...9999)
                }
            }
            .navigationTitle("编辑订阅源")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(source)
                        dismiss()
                    }
                    .disabled(source.sourceName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              source.sourceUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<RssSource, String?>) -> Binding<String> {
        Binding(
            get: { source[keyPath: keyPath] ?? "" },
            set: { source[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func ruleField(_ label: String, placeholder: String, keyPath: WritableKeyPath<RssSource, String?>) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: optionalBinding(keyPath))
                .font(.system(.caption, design: .monospaced))
        }
    }
}

// MARK: - RssSourceDebugSheet (订阅源流式调试台 — Plan Phase 1 Part 1.2)

/// 三阶段流式调试：1 解析分类 (sortUrl) → 2 拉取文章列表 (ruleArticles 系列) → 3 抽取首篇正文 (ruleContent)。
/// 对齐 `SourceDebugSheet` 的日志样式：▶ 阶段头 / ✅ 成功 / ❌ 失败，等宽字体实时滚动。
struct RssSourceDebugSheet: View {
    let source: RssSource
    @Environment(\.dismiss) private var dismiss

    @State private var logs: [String] = []
    @State private var isRunning: Bool = false
    @State private var debugTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.sourceName)
                            .font(.subheadline.bold())
                        Text(source.sourceUrl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(isRunning ? "停止" : "开始调试") {
                        if isRunning {
                            stopDebug()
                        } else {
                            startDebug()
                        }
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isRunning ? Color.orange : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(colorForLog(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: logs.count) { _ in
                        if let last = logs.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("调试订阅源")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { stopDebug(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("清空") { logs.removeAll() }
                }
            }
            .onDisappear {
                stopDebug()
            }
        }
    }

    private func colorForLog(_ line: String) -> Color {
        if line.hasPrefix("❌") { return .red }
        if line.hasPrefix("✅") { return .green }
        if line.hasPrefix("▶") { return .accentColor }
        return .primary
    }

    private func appendLog(_ text: String) {
        logs.append(text)
    }

    private func stopDebug() {
        debugTask?.cancel()
        debugTask = nil
        isRunning = false
    }

    private func startDebug() {
        logs.removeAll()
        isRunning = true

        debugTask = Task {
            let start = Date()
            await MainActor.run {
                appendLog("▶ [阶段 1/3] 解析分类 (sortUrl)")
                appendLog("  源地址：\(source.sourceUrl)")
            }

            // 阶段 1：分类解析（纯本地规则，不联网）
            let categories = RssService.shared.parseCategories(source: source)
            await MainActor.run {
                if categories.isEmpty {
                    appendLog("❌ [分类为空] 请检查 sortUrl 格式（每行「分类名::URL」）")
                } else {
                    appendLog("✅ [分类解析成功] 共 \(categories.count) 个分类")
                    for cat in categories.prefix(10) {
                        appendLog("  · \(cat.title) → \(cat.url)")
                    }
                    if categories.count > 10 {
                        appendLog("  ... 其余 \(categories.count - 10) 个略")
                    }
                }
            }

            // 阶段 2：文章列表
            guard let firstCategory = categories.first else {
                await MainActor.run {
                    appendLog("❌ [调试中止] 无可用分类")
                    isRunning = false
                }
                return
            }
            if Task.isCancelled { return }
            await MainActor.run { appendLog("▶ [阶段 2/3] 拉取文章列表「\(firstCategory.title)」") }

            let stageStart = Date()
            do {
                let page = try await RssService.shared.fetchArticlePage(source: source, pageUrl: firstCategory.url)
                if Task.isCancelled { return }
                let ms = Int(Date().timeIntervalSince(stageStart) * 1000)
                await MainActor.run {
                    if page.articles.isEmpty {
                        appendLog("❌ [文章列表为空] 耗时 \(ms)ms。请检查 ruleArticles / ruleTitle / ruleLink")
                    } else {
                        appendLog("✅ [文章列表成功] 耗时 \(ms)ms，共 \(page.articles.count) 篇")
                        for article in page.articles.prefix(5) {
                            appendLog("  · \(article.title)")
                        }
                        if let next = page.nextPageUrl {
                            appendLog("  翻页规则生效，下一页：\(next)")
                        } else if source.ruleNextPage?.isEmpty == false {
                            appendLog("  ⚠️ 已配置 ruleNextPage 但本页未解析出下一页链接")
                        }
                    }
                }

                // 阶段 3：首篇正文
                guard let firstArticle = page.articles.first else {
                    await MainActor.run {
                        appendLog("❌ [调试中止] 无文章可测正文规则")
                        isRunning = false
                    }
                    return
                }
                if Task.isCancelled { return }
                await MainActor.run {
                    appendLog("▶ [阶段 3/3] 抓取首篇正文 (ruleContent)")
                    appendLog("  文章：\(firstArticle.title)")
                    appendLog("  链接：\(firstArticle.link)")
                }

                let contentStart = Date()
                do {
                    let content = try await RssService.shared.fetchArticleContent(article: firstArticle, source: source)
                    if Task.isCancelled { return }
                    let ms = Int(Date().timeIntervalSince(contentStart) * 1000)
                    await MainActor.run {
                        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            appendLog("❌ [正文为空] 耗时 \(ms)ms。请检查 ruleContent")
                        } else {
                            appendLog("✅ [正文成功] 耗时 \(ms)ms，共 \(content.count) 字")
                            let preview = content.prefix(120).replacingOccurrences(of: "\n", with: " ")
                            appendLog("  预览：\(preview)...")
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        appendLog("❌ [正文抓取失败] \(error.localizedDescription)")
                        isRunning = false
                    }
                }
            } catch {
                if Task.isCancelled { return }
                let ms = Int(Date().timeIntervalSince(stageStart) * 1000)
                await MainActor.run {
                    appendLog("❌ [文章列表失败] 耗时 \(ms)ms：\(error.localizedDescription)")
                    isRunning = false
                }
                return
            }

            await MainActor.run {
                appendLog("▶ 调试结束，总耗时 \(Int(Date().timeIntervalSince(start) * 1000))ms")
                isRunning = false
            }
        }
    }
}

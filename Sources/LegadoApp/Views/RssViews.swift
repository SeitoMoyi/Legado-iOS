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

    @State private var categories: [RssService.RssCategory] = []
    @State private var selectedCategoryUrl: String = ""
    @State private var articles: [RssArticle] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedArticleForRead: RssArticle? = nil

    public init(source: RssSource) {
        self.source = source
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Pills
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
                } else {
                    List(articles) { article in
                        Button {
                            selectedArticleForRead = article
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(article.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                        .lineLimit(2)

                                    if let desc = article.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }

                                    if let date = article.pubDate, !date.isEmpty {
                                        Text(date)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary.opacity(0.7))
                                    }
                                }

                                Spacer()

                                if let imgStr = article.image, let url = URL(string: imgStr) {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable().scaledToFill()
                                        } else {
                                            Color.secondary.opacity(0.1)
                                        }
                                    }
                                    .frame(width: 72, height: 54)
                                    .cornerRadius(6)
                                    .clipped()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .refreshable {
                        loadArticles()
                    }
                    #if os(iOS)
                    .listStyle(.plain)
                    #endif
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
            }
            .sheet(item: $selectedArticleForRead) { article in
                RssArticleReaderView(article: article, source: source)
            }
            .onAppear {
                categories = RssService.shared.parseCategories(source: source)
                if selectedCategoryUrl.isEmpty, let first = categories.first {
                    selectedCategoryUrl = first.url
                }
                loadArticles()
            }
        }
    }

    private func loadArticles() {
        guard !selectedCategoryUrl.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await RssService.shared.fetchArticles(source: source, categoryUrl: selectedCategoryUrl)
                await MainActor.run {
                    self.articles = fetched
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

// MARK: - RssSourceEditSheet (订阅源编辑器)

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
                        TextField("科技资讯", text: Binding(
                            get: { source.sourceGroup ?? "" },
                            set: { source.sourceGroup = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    Toggle("启用该订阅源", isOn: $source.enabled)
                }

                Section(header: Text("分类与列表 (sortUrl / ruleArticles)")) {
                    TextEditor(text: Binding(
                        get: { source.sortUrl ?? "" },
                        set: { source.sortUrl = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 60)
                    .font(.system(.caption, design: .monospaced))

                    HStack {
                        Text("文章列表")
                            .frame(width: 80, alignment: .leading)
                        TextField("//item", text: Binding(
                            get: { source.ruleArticles ?? "" },
                            set: { source.ruleArticles = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    HStack {
                        Text("标题规则")
                            .frame(width: 80, alignment: .leading)
                        TextField("//title/text()", text: Binding(
                            get: { source.ruleTitle ?? "" },
                            set: { source.ruleTitle = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    HStack {
                        Text("链接规则")
                            .frame(width: 80, alignment: .leading)
                        TextField("//link/text()", text: Binding(
                            get: { source.ruleLink ?? "" },
                            set: { source.ruleLink = $0.isEmpty ? nil : $0 }
                        ))
                    }
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
}

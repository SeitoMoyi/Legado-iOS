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

public struct EditSourceSheet: View {
    public enum EditorTab: Int, CaseIterable {
        case basic = 0
        case search = 1
        case explore = 2
        case bookInfo = 3
        case toc = 4
        case content = 5

        var title: String {
            switch self {
            case .basic: return "基本"
            case .search: return "搜索"
            case .explore: return "发现"
            case .bookInfo: return "详情"
            case .toc: return "目录"
            case .content: return "正文"
            }
        }
    }

    @ObservedObject var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    let originalSource: BookSource
    let isCreatingNew: Bool

    @State private var selectedTab: EditorTab = .basic
    @State private var draft: BookSource
    @State private var showDebugSheet: Bool = false
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init(source: BookSource, isCreatingNew: Bool = false) {
        self.originalSource = source
        self.isCreatingNew = isCreatingNew
        var editable = source
        if editable.ruleSearch == nil { editable.ruleSearch = SearchRule() }
        if editable.ruleExplore == nil { editable.ruleExplore = ExploreRule() }
        if editable.ruleBookInfo == nil { editable.ruleBookInfo = BookInfoRule() }
        if editable.ruleToc == nil { editable.ruleToc = TocRule() }
        if editable.ruleContent == nil { editable.ruleContent = ContentRule() }
        self._draft = State(initialValue: editable)
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 6-Tab segmented selector
                Picker("规则分组", selection: $selectedTab) {
                    ForEach(EditorTab.allCases, id: \.rawValue) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Form {
                    switch selectedTab {
                    case .basic:
                        basicTabSections
                    case .search:
                        searchTabSections
                    case .explore:
                        exploreTabSections
                    case .bookInfo:
                        bookInfoTabSections
                    case .toc:
                        tocTabSections
                    case .content:
                        contentTabSections
                    }
                }
            }
            .navigationTitle(isCreatingNew ? "新建书源" : "编辑书源")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Menu {
                            Button {
                                showDebugSheet = true
                            } label: {
                                Label("调试该书源", systemImage: "ladybug")
                            }

                            Button {
                                copyWholeSourceJSON()
                            } label: {
                                Label("拷贝整源 JSON", systemImage: "doc.on.doc")
                            }

                            Button {
                                pasteWholeSourceJSON()
                            } label: {
                                Label("从剪贴板粘贴整源 JSON", systemImage: "doc.on.clipboard")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Button("保存") {
                            saveChanges()
                            dismiss()
                        }
                        .disabled(
                            draft.bookSourceName.trimmingCharacters(in: .whitespaces).isEmpty ||
                            draft.bookSourceUrl.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                    }
                }
            }
            .sheet(isPresented: $showDebugSheet) {
                SourceDebugSheet(source: sanitizedSource())
            }
            .alert(alertMessage ?? "", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            }
        }
    }

    // MARK: - Tab 1: Basic

    @ViewBuilder
    private var basicTabSections: some View {
        Section(header: Text("核心信息")) {
            ruleField("书源名称 *", placeholder: "如：起点中文", text: $draft.bookSourceName)
            ruleField("书源网址 *", placeholder: "https://...", text: $draft.bookSourceUrl)
            ruleField("书源分组", placeholder: "多个用逗号分隔", text: optionalBinding(\.bookSourceGroup))
            Picker("书源类型", selection: Binding(
                get: { draft.bookSourceType ?? 0 },
                set: { draft.bookSourceType = $0 }
            )) {
                Text("文本 (0)").tag(0)
                Text("音频 (1)").tag(1)
                Text("图片/漫画 (2)").tag(2)
                Text("文件 (3)").tag(3)
            }
            Toggle("启用书源", isOn: Binding(
                get: { draft.enabled ?? true },
                set: { draft.enabled = $0 }
            ))
            Toggle("启用发现", isOn: Binding(
                get: { draft.enabledExplore ?? true },
                set: { draft.enabledExplore = $0 }
            ))
        }

        Section(header: Text("请求头与登录 (Header / Login)")) {
            ruleMultilineField("请求头 (header)", placeholder: "{\"User-Agent\": \"...\"}", text: optionalBinding(\.header))
            ruleField("详情 URL 正则 (bookUrlPattern)", placeholder: "https://.../book/\\d+", text: optionalBinding(\.bookUrlPattern))
            ruleMultilineField("登录地址或脚本 (loginUrl)", placeholder: "https://... 或 @js:...", text: optionalBinding(\.loginUrl))
            ruleMultilineField("登录表单 UI (loginUi JSON)", placeholder: "[{\"name\":\"用户名\",\"type\":\"text\"}]", text: optionalBinding(\.loginUi))
            ruleMultilineField("登录检测 JS (loginCheckJs)", placeholder: "result", text: optionalBinding(\.loginCheckJs))
        }

        Section(header: Text("注释与变量说明")) {
            ruleMultilineField("书源注释 (bookSourceComment)", placeholder: "书源说明、注意事项...", text: optionalBinding(\.bookSourceComment))
            ruleMultilineField("变量说明 (variableComment)", placeholder: "提示用户如何设置源变量...", text: optionalBinding(\.variableComment))
            ruleMultilineField("封面解密 JS (coverDecodeJs)", placeholder: "", text: optionalBinding(\.coverDecodeJs))
        }
    }

    // MARK: - Tab 2: Search

    @ViewBuilder
    private var searchTabSections: some View {
        Section(header: Text("搜索地址")) {
            ruleMultilineField("搜索地址 (searchUrl)", placeholder: "/search?key={{key}}&page={{page}}", text: optionalBinding(\.searchUrl), minHeight: 72)
            ruleField("校验关键字 (checkKeyWord)", placeholder: "我的", text: searchRuleBinding(\.checkKeyWord))
        }

        Section(header: Text("搜索结果列表规则 (ruleSearch)")) {
            ruleField("书籍列表 (bookList)", placeholder: "class.book-item 或 //li", text: searchRuleBinding(\.bookList))
            ruleField("书名 (name)", placeholder: "tag.a.0@text", text: searchRuleBinding(\.name))
            ruleField("作者 (author)", placeholder: "class.author@text", text: searchRuleBinding(\.author))
            ruleField("分类/标签 (kind)", placeholder: "class.cat@text", text: searchRuleBinding(\.kind))
            ruleField("字数 (wordCount)", placeholder: "class.words@text", text: searchRuleBinding(\.wordCount))
            ruleField("最新章节 (lastChapter)", placeholder: "class.latest@text", text: searchRuleBinding(\.lastChapter))
            ruleField("简介 (intro)", placeholder: "class.desc@text", text: searchRuleBinding(\.intro))
            ruleField("封面链接 (coverUrl)", placeholder: "img@src", text: searchRuleBinding(\.coverUrl))
            ruleField("详情链接 (bookUrl)", placeholder: "tag.a.0@href", text: searchRuleBinding(\.bookUrl))
        }
    }

    // MARK: - Tab 3: Explore

    @ViewBuilder
    private var exploreTabSections: some View {
        Section(header: Text("发现分类配置 (exploreUrl)")) {
            ruleMultilineField("发现分类地址 (exploreUrl)", placeholder: "玄幻::/sort/1/{{page}}.html\n或 JSON 数组", text: optionalBinding(\.exploreUrl), minHeight: 110)
        }

        Section(header: Text("发现列表规则 (ruleExplore，留空时复用搜索规则)")) {
            ruleField("书籍列表 (bookList)", placeholder: "class.book-item", text: exploreRuleBinding(\.bookList))
            ruleField("书名 (name)", placeholder: "tag.a.0@text", text: exploreRuleBinding(\.name))
            ruleField("作者 (author)", placeholder: "class.author@text", text: exploreRuleBinding(\.author))
            ruleField("分类/标签 (kind)", placeholder: "class.cat@text", text: exploreRuleBinding(\.kind))
            ruleField("字数 (wordCount)", placeholder: "class.words@text", text: exploreRuleBinding(\.wordCount))
            ruleField("最新章节 (lastChapter)", placeholder: "class.latest@text", text: exploreRuleBinding(\.lastChapter))
            ruleField("简介 (intro)", placeholder: "class.desc@text", text: exploreRuleBinding(\.intro))
            ruleField("封面链接 (coverUrl)", placeholder: "img@src", text: exploreRuleBinding(\.coverUrl))
            ruleField("详情链接 (bookUrl)", placeholder: "tag.a.0@href", text: exploreRuleBinding(\.bookUrl))
        }
    }

    // MARK: - Tab 4: BookInfo

    @ViewBuilder
    private var bookInfoTabSections: some View {
        Section(header: Text("详情页规则 (ruleBookInfo)")) {
            ruleField("预处理规则 (init)", placeholder: "JSON/DOM 根节点预提取", text: bookInfoRuleBinding(\.initRule))
            ruleField("书名 (name)", placeholder: "h1@text", text: bookInfoRuleBinding(\.name))
            ruleField("作者 (author)", placeholder: "class.author@text", text: bookInfoRuleBinding(\.author))
            ruleField("分类/标签 (kind)", placeholder: "class.category@text", text: bookInfoRuleBinding(\.kind))
            ruleField("字数 (wordCount)", placeholder: "class.count@text", text: bookInfoRuleBinding(\.wordCount))
            ruleField("最新章节 (lastChapter)", placeholder: "class.last@text", text: bookInfoRuleBinding(\.lastChapter))
            ruleMultilineField("简介 (intro)", placeholder: "id.intro@text", text: bookInfoRuleBinding(\.intro))
            ruleField("封面链接 (coverUrl)", placeholder: "id.cover@img@src", text: bookInfoRuleBinding(\.coverUrl))
            ruleField("目录链接 (tocUrl)", placeholder: "text.查看目录@href", text: bookInfoRuleBinding(\.tocUrl))
        }
    }

    // MARK: - Tab 5: TOC

    @ViewBuilder
    private var tocTabSections: some View {
        Section(header: Text("目录页规则 (ruleToc)")) {
            ruleField("章节列表 (chapterList)", placeholder: "id.list@tag.dd@tag.a（前缀 - 反转）", text: tocRuleBinding(\.chapterList))
            ruleField("章节名称 (chapterName)", placeholder: "text", text: tocRuleBinding(\.chapterName))
            ruleField("章节链接 (chapterUrl)", placeholder: "href", text: tocRuleBinding(\.chapterUrl))
            ruleField("下一页目录 (nextTocUrl)", placeholder: "text.下一页@href", text: tocRuleBinding(\.nextTocUrl))
            ruleField("分卷标识 (isVolume)", placeholder: "", text: tocRuleBinding(\.isVolume))
            ruleField("VIP 标识 (isVip)", placeholder: "", text: tocRuleBinding(\.isVip))
            ruleField("已购买标识 (isPay)", placeholder: "", text: tocRuleBinding(\.isPay))
            ruleField("更新时间 (updateTime)", placeholder: "", text: tocRuleBinding(\.updateTime))
            ruleMultilineField("目录前处理 JS (preUpdateJs)", placeholder: "", text: tocRuleBinding(\.preUpdateJs))
            ruleMultilineField("章节标题格式化 JS (formatJs)", placeholder: "", text: tocRuleBinding(\.formatJs))
        }
    }

    // MARK: - Tab 6: Content

    @ViewBuilder
    private var contentTabSections: some View {
        Section(header: Text("正文页规则 (ruleContent)")) {
            ruleMultilineField("正文规则 (content)", placeholder: "id.content@html 或 //div[@id='content']/text()", text: contentRuleBinding(\.content), minHeight: 80)
            ruleField("章节标题 (title)", placeholder: "h1@text", text: contentRuleBinding(\.title))
            ruleField("下一页正文 (nextContentUrl)", placeholder: "text.下一页@href", text: contentRuleBinding(\.nextContentUrl))
            ruleMultilineField("替换规则 (replaceRegex)", placeholder: "##广告正则##替换内容", text: contentRuleBinding(\.replaceRegex))
            ruleField("图片样式 (imageStyle)", placeholder: "DEFAULT / FULL / TEXT / SINGLE", text: contentRuleBinding(\.imageStyle))
            ruleMultilineField("WebView 脚本 (webJs)", placeholder: "", text: contentRuleBinding(\.webJs))
            ruleField("资源正则 (sourceRegex)", placeholder: "", text: contentRuleBinding(\.sourceRegex))
            ruleMultilineField("图片解密 JS (imageDecode)", placeholder: "", text: contentRuleBinding(\.imageDecode))
        }
    }

    // MARK: - Field Helpers & Bindings

    @ViewBuilder
    private func ruleField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .font(.system(.subheadline, design: .monospaced))
                #if os(iOS)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                #endif
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func ruleMultilineField(_ label: String, placeholder: String, text: Binding<String>, minHeight: CGFloat = 58) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.45))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: minHeight)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif
            }
        }
        .padding(.vertical, 2)
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<BookSource, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { newVal in
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : newVal
            }
        )
    }

    private func searchRuleBinding(_ keyPath: WritableKeyPath<SearchRule, String?>) -> Binding<String> {
        Binding(
            get: { draft.ruleSearch?[keyPath: keyPath] ?? "" },
            set: { newVal in
                var rule = draft.ruleSearch ?? SearchRule()
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                rule[keyPath: keyPath] = trimmed.isEmpty ? nil : newVal
                draft.ruleSearch = rule
            }
        )
    }

    private func exploreRuleBinding(_ keyPath: WritableKeyPath<ExploreRule, String?>) -> Binding<String> {
        Binding(
            get: { draft.ruleExplore?[keyPath: keyPath] ?? "" },
            set: { newVal in
                var rule = draft.ruleExplore ?? ExploreRule()
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                rule[keyPath: keyPath] = trimmed.isEmpty ? nil : newVal
                draft.ruleExplore = rule
            }
        )
    }

    private func bookInfoRuleBinding(_ keyPath: WritableKeyPath<BookInfoRule, String?>) -> Binding<String> {
        Binding(
            get: { draft.ruleBookInfo?[keyPath: keyPath] ?? "" },
            set: { newVal in
                var rule = draft.ruleBookInfo ?? BookInfoRule()
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                rule[keyPath: keyPath] = trimmed.isEmpty ? nil : newVal
                draft.ruleBookInfo = rule
            }
        )
    }

    private func tocRuleBinding(_ keyPath: WritableKeyPath<TocRule, String?>) -> Binding<String> {
        Binding(
            get: { draft.ruleToc?[keyPath: keyPath] ?? "" },
            set: { newVal in
                var rule = draft.ruleToc ?? TocRule()
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                rule[keyPath: keyPath] = trimmed.isEmpty ? nil : newVal
                draft.ruleToc = rule
            }
        )
    }

    private func contentRuleBinding(_ keyPath: WritableKeyPath<ContentRule, String?>) -> Binding<String> {
        Binding(
            get: { draft.ruleContent?[keyPath: keyPath] ?? "" },
            set: { newVal in
                var rule = draft.ruleContent ?? ContentRule()
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                rule[keyPath: keyPath] = trimmed.isEmpty ? nil : newVal
                draft.ruleContent = rule
            }
        )
    }

    private func sanitizedSource() -> BookSource {
        var updated = draft
        updated.bookSourceName = draft.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.bookSourceUrl = draft.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.lastUpdateTime = Int64(Date().timeIntervalSince1970 * 1000)
        return updated
    }

    private func saveChanges() {
        let updated = sanitizedSource()
        if isCreatingNew {
            if let data = try? JSONEncoder().encode([updated]),
               let json = String(data: data, encoding: .utf8) {
                _ = try? bookStore.importSources(json: json)
            }
        } else {
            bookStore.updateSource(originalSource: originalSource, newSource: updated)
        }
    }

    private func copyWholeSourceJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(sanitizedSource()),
              let json = String(data: data, encoding: .utf8) else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = json
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        #endif
        alertMessage = "已将当前书源完整 JSON 拷贝至剪贴板"
        showAlert = true
    }

    private func pasteWholeSourceJSON() {
        let raw: String?
        #if canImport(UIKit)
        raw = UIPasteboard.general.string
        #elseif canImport(AppKit)
        raw = NSPasteboard.general.string(forType: .string)
        #else
        raw = nil
        #endif
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = text.data(using: .utf8) else {
            alertMessage = "剪贴板为空"
            showAlert = true
            return
        }

        if let single = BookSource.decodeWithExtras(from: data) {
            draft = single
            alertMessage = "已从剪贴板载入书源「\(single.bookSourceName)」"
            showAlert = true
        } else if let array = BookSource.decodeListWithExtras(from: data), let first = array.first {
            draft = first
            alertMessage = "已从剪贴板载入书源「\(first.bookSourceName)」"
            showAlert = true
        } else {
            alertMessage = "剪贴板内容不是有效的 Legado 书源 JSON"
            showAlert = true
        }
    }
}

// MARK: - SourceDebugSheet (4-Stage Live Source Debugger)

public struct SourceDebugSheet: View {
    let source: BookSource
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = "我的"
    @State private var logs: [String] = []
    @State private var isRunning: Bool = false
    @State private var debugTask: Task<Void, Never>? = nil

    public init(source: BookSource) {
        self.source = source
        if let check = source.ruleSearch?.checkKeyWord?.trimmingCharacters(in: .whitespacesAndNewlines), !check.isEmpty {
            self._query = State(initialValue: check)
        }
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("输入搜索词或详情页 URL...", text: $query)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif

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
                    .buttonStyle(.plain)
                }
                .padding(12)

                Divider()

                if logs.isEmpty && !isRunning {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "ladybug")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("点击「开始调试」将依次测试：\n1. 搜索列表 → 2. 书籍详情 → 3. 目录解析 → 4. 正文提取")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(colorForLog(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("调试：\(source.bookSourceName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        stopDebug()
                        dismiss()
                    }
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        logs.removeAll()
        isRunning = true

        debugTask = Task {
            let start = Date()
            await MainActor.run {
                appendLog("▶ [阶段 1/4] 正在测试搜索，关键词：「\(trimmed)」")
                appendLog("  书源 URL：\(source.bookSourceUrl)")
            }

            do {
                let searchResults = try await BookSearchService.shared.search(source: source, key: trimmed, page: 1)
                if Task.isCancelled { return }

                let searchMs = Int(Date().timeIntervalSince(start) * 1000)
                guard let firstBook = searchResults.first else {
                    await MainActor.run {
                        appendLog("❌ [搜索结果为空] 耗时 \(searchMs)ms。请检查 searchUrl 或 ruleSearch.bookList")
                        isRunning = false
                    }
                    return
                }

                await MainActor.run {
                    appendLog("✅ [搜索成功] 耗时 \(searchMs)ms，共返回 \(searchResults.count) 本书")
                    appendLog("  首本书名：\(firstBook.name)")
                    appendLog("  首本作者：\(firstBook.author)")
                    appendLog("  详情地址：\(firstBook.bookUrl)")
                    appendLog("▶ [阶段 2/4 & 3/4] 正在拉取书籍详情与目录列表...")
                }

                let tempBook = Book(
                    bookUrl: firstBook.bookUrl,
                    name: firstBook.name,
                    author: firstBook.author,
                    kind: firstBook.kind,
                    coverUrl: firstBook.coverUrl,
                    intro: firstBook.intro,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName
                )

                let detailStart = Date()
                let (detailedBook, chapters) = try await BookContentService.shared.fetchBookDetail(book: tempBook, source: source)
                if Task.isCancelled { return }
                let detailMs = Int(Date().timeIntervalSince(detailStart) * 1000)

                await MainActor.run {
                    appendLog("✅ [详情解析完成] 耗时 \(detailMs)ms")
                    appendLog("  书名：\(detailedBook.name) | 作者：\(detailedBook.author)")
                    appendLog("  简介：\((detailedBook.intro ?? "无").prefix(80))...")
                }

                guard let firstChapter = chapters.first else {
                    await MainActor.run {
                        appendLog("❌ [目录为空] 未解析到任何章节，请检查 ruleToc.chapterList")
                        isRunning = false
                    }
                    return
                }

                await MainActor.run {
                    appendLog("✅ [目录解析成功] 共 \(chapters.count) 章")
                    appendLog("  首章标题：\(firstChapter.title)")
                    appendLog("  首章地址：\(firstChapter.url)")
                    if chapters.count > 1, let last = chapters.last {
                        appendLog("  末章标题：\(last.title)")
                    }
                    appendLog("▶ [阶段 4/4] 正在抓取首章正文...")
                }

                let contentStart = Date()
                let nextUrl = chapters.count > 1 ? chapters[1].url : nil
                let content = try await BookContentService.shared.fetchChapterContent(
                    chapter: firstChapter,
                    source: source,
                    nextChapterUrl: nextUrl
                )
                if Task.isCancelled { return }
                let contentMs = Int(Date().timeIntervalSince(contentStart) * 1000)

                await MainActor.run {
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendLog("❌ [正文为空] 耗时 \(contentMs)ms，请检查 ruleContent.content")
                    } else {
                        appendLog("✅ [正文抓取成功] 耗时 \(contentMs)ms，共 \(content.count) 字")
                        appendLog("  正文预览：\n\(content.prefix(240))...")
                    }
                    let totalMs = Int(Date().timeIntervalSince(start) * 1000)
                    appendLog("🎉 全流程四步调试结束，总耗时 \(totalMs)ms")
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    appendLog("❌ [调试异常] \(error.localizedDescription)")
                    isRunning = false
                }
            }
        }
    }
}

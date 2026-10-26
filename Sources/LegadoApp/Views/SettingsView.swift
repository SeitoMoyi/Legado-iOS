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
/// 我的 — SwiftUI counterpart of Android `MyFragment` + `pref_main.xml`.
///
/// Row order, titles, summaries and grouping mirror the Android preference screen exactly
/// (top-level rows, then 设置 category, then 其它 category); entries whose feature has no
/// iOS counterpart yet (文件管理/退出) are omitted rather than stubbed.
public struct SettingsView: View {

    @ObservedObject var bookStore = BookStore.shared
    @ObservedObject var readerConfig = ReaderConfig.shared
    @ObservedObject private var webServer = LocalWebServer.shared

    @AppStorage("legado_app_theme") private var appTheme: String = "system"

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                // MARK: 顶层（无分组，对齐 pref_main 顶部六行）

                prefLink("square.stack.3d.up.fill", "书源管理", "新建、导入、编辑或管理书源") {
                    SourceManagerView()
                }
                prefLink("square.stack.3d.up.fill", "TXT 目录规则", "配置 TXT 目录规则") {
                    TxtTocRuleListView()
                }
                prefLink("arrow.left.arrow.right.square.fill", "替换净化", "配置替换净化规则") {
                    ReplaceRuleListView()
                }
                prefLink("character.book.closed.fill", "字典规则", "配置字典规则") {
                    DictRuleListView()
                }

                // 主题模式（Android NameListPreference：值显示在 summary 位）
                HStack(spacing: 12) {
                    prefIcon("paintbrush.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Menu {
                            Button("跟随系统") { appTheme = "system" }
                            Button("浅色模式") { appTheme = "light" }
                            Button("深色模式") { appTheme = "dark" }
                        } label: {
                            HStack {
                                Text("主题模式")
                                Spacer()
                                Text(appThemeLabel)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("选择主题模式")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)

                // Web 服务（Android SwitchPreference：运行时 summary 显示地址）
                HStack(spacing: 12) {
                    prefIcon("network")
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: Binding(
                            get: { webServer.isRunning },
                            set: { $0 ? webServer.start() : webServer.stop() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Web 服务")
                                Text(webServer.isRunning ? webServer.serverURLString : "用浏览器写源或看书")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)

                // WiFi 传书详情（iOS 特有：浏览器上传门户的本地状态与传输动态）
                prefLink("arrow.up.arrow.down.circle.fill", "WiFi 传书",
                         webServer.isRunning ? "运行中 · \(webServer.serverURLString)" : "未启动") {
                    LocalWebServerView()
                }

                // MARK: 设置

                Section(header: Text("设置")) {
                    prefLink("externaldrive.connected.to.line.below.fill", "备份与恢复",
                             "WebDav 设置/导入旧版本数据") {
                        WebDAVSyncView()
                    }
                    prefLink("gearshape.fill", "其它设置", "与功能相关的一些设置") {
                        OtherConfigView()
                    }
                }

                // MARK: 其它

                Section(header: Text("其它")) {
                    prefLink("bookmark.fill", "书签", "所有书签") {
                        AllBookmarksView()
                    }
                    prefLink("clock.arrow.circlepath", "阅读记录", "阅读时间记录") {
                        ReadRecordListView()
                    }
                    prefLink("info.circle", "关于", "Legado iOS") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("我的")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }

    private var appThemeLabel: String {
        switch appTheme {
        case "light": return "浅色模式"
        case "dark": return "深色模式"
        default: return "跟随系统"
        }
    }

    /// Android `Preference` row look: leading icon, bold title, caption summary, full-row tap.
    private func prefLink<D: View>(_ icon: String, _ title: String, _ summary: String,
                                   @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                prefIcon(icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func prefIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17))
            .foregroundColor(.accentColor)
            .frame(width: 26)
    }
}

/// 其它设置 — collects the iOS feature toggles that Android keeps under
/// `ConfigTag.OTHER_CONFIG` (正文处理 / 朗读引擎 / 缓存).
struct OtherConfigView: View {
    @ObservedObject var bookStore = BookStore.shared
    @ObservedObject var readerConfig = ReaderConfig.shared
    @State private var showClearCacheAlert: Bool = false
    @State private var clearCacheMessage: String? = nil

    var body: some View {
        Form {
            Section(header: Text("正文处理")) {
                Toggle("新书默认启用净化", isOn: Binding(
                    get: { readerConfig.prefs.replaceEnableDefault },
                    set: { var p = readerConfig.prefs; p.replaceEnableDefault = $0; readerConfig.prefs = p }
                ))

                Picker("简繁转换", selection: Binding(
                    get: { readerConfig.prefs.chineseConverterType },
                    set: { var p = readerConfig.prefs; p.chineseConverterType = $0; readerConfig.prefs = p }
                )) {
                    Text("关闭").tag(0)
                    Text("繁体转简体").tag(1)
                    Text("简体转繁体").tag(2)
                }

                Picker("图片样式", selection: Binding(
                    get: { readerConfig.prefs.imageStyle },
                    set: { var p = readerConfig.prefs; p.imageStyle = $0; readerConfig.prefs = p }
                )) {
                    ForEach(ReadImageStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            }

            Section(header: Text("朗读")) {
                NavigationLink(destination: HttpTTSListView()) {
                    HStack {
                        Text("朗读引擎")
                        Spacer()
                        Text("\(HttpTTSStore.load().filter { $0.enabled }.count) 个引擎")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("缓存")) {
                Button(role: .destructive) {
                    showClearCacheAlert = true
                } label: {
                    Text("清理阅读缓存")
                }
            }
        }
        .navigationTitle("其它设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("清理阅读缓存", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("确定清理", role: .destructive) {
                for book in bookStore.bookshelf {
                    BookContentService.shared.clearCache(for: book.bookUrl)
                }
                clearCacheMessage = "缓存已成功清理"
            }
        } message: {
            Text("确定要清理临时章节与图片缓存吗？书架书籍与阅读进度将保留。")
        }
        .alert(clearCacheMessage ?? "", isPresented: Binding(
            get: { clearCacheMessage != nil },
            set: { if !$0 { clearCacheMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        }
    }
}

/// 关于 — Android `AboutActivity` counterpart (应用名称 / 当前版本 / 内核引擎).
struct AboutView: View {
    private var quickJSNotice: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "QuickJS"),
              let text = try? String(contentsOf: url) else { return "QuickJS — MIT License" }
        return text
    }
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "未知"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("Legado iOS (开源阅读)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("内核引擎")
                    Spacer()
                    Text("Swift 原生 + QuickJS")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack {
                    Text("开源许可")
                    Spacer()
                    Text("GPLv3")
                        .foregroundColor(.secondary)
                }
                NavigationLink("QuickJS · MIT") {
                    ScrollView { Text(quickJSNotice).font(.footnote).padding() }
                        .navigationTitle("QuickJS")
                }
            }
        }
        .navigationTitle("关于")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - AllBookmarksView (Android AllBookmarkActivity Counterpart)

public struct AllBookmarksView: View {
    @ObservedObject var bookStore = BookStore.shared
    @State private var searchText: String = ""
    @State private var editingBookmark: Bookmark? = nil
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    private var filteredBookmarks: [Bookmark] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return bookStore.bookmarks }
        return bookStore.bookmarks.filter {
            $0.bookName.localizedCaseInsensitiveContains(needle) ||
            $0.bookAuthor.localizedCaseInsensitiveContains(needle) ||
            $0.chapterName.localizedCaseInsensitiveContains(needle) ||
            $0.bookText.localizedCaseInsensitiveContains(needle) ||
            $0.content.localizedCaseInsensitiveContains(needle)
        }
    }

    private struct BookGroup: Identifiable {
        let id: String
        let bookName: String
        let bookAuthor: String
        let items: [Bookmark]
    }

    private var groupedBookmarks: [BookGroup] {
        var order: [String] = []
        var dict: [String: [Bookmark]] = [:]
        for bm in filteredBookmarks {
            let key = bm.bookKey
            if dict[key] == nil {
                order.append(key)
                dict[key] = []
            }
            dict[key]?.append(bm)
        }
        return order.compactMap { key in
            guard let items = dict[key], let first = items.first else { return nil }
            return BookGroup(id: key, bookName: first.bookName, bookAuthor: first.bookAuthor, items: items)
        }
    }

    public var body: some View {
        contentView
            .searchable(text: $searchText, prompt: "搜索书名、章节、摘录或笔记")
            .navigationTitle("所有书签 (\(bookStore.bookmarks.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                toolbarMenu
            }
            .sheet(item: $editingBookmark) { bm in
                BookmarkEditorSheet(bookmark: bm, isNew: false) { saved in
                    bookStore.updateBookmark(saved)
                } onDelete: { removed in
                    bookStore.deleteBookmark(time: removed.time)
                }
            }
            .alert(alertMessage ?? "", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if filteredBookmarks.isEmpty {
            emptyView
        } else {
            bookmarksList
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text(searchText.isEmpty ? "暂无书签" : "未找到匹配的书签")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var bookmarksList: some View {
        List {
            ForEach(groupedBookmarks) { group in
                Section(header: Text(group.bookAuthor.isEmpty ? group.bookName : "\(group.bookName) · \(group.bookAuthor)")) {
                    ForEach(group.items) { bm in
                        bookmarkRow(for: bm)
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

    private func bookmarkRow(for bm: Bookmark) -> some View {
        Button {
            editingBookmark = bm
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(bm.chapterName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                if !bm.bookText.isEmpty {
                    Text(bm.bookText)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
                if !bm.content.isEmpty {
                    Text(bm.content)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑") { editingBookmark = bm }
            Button("删除", role: .destructive) {
                bookStore.deleteBookmark(time: bm.time)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    if let json = BookmarkStore.exportJSON(bookStore.bookmarks) {
                        copyToClipboard(json)
                        alertMessage = "已将全部 \(bookStore.bookmarks.count) 条书签导出为 JSON 至剪贴板"
                        showAlert = true
                    }
                } label: {
                    Label("导出 JSON 至剪贴板", systemImage: "curlybraces")
                }

                Button {
                    let md = BookmarkStore.exportMarkdown(bookStore.bookmarks)
                    copyToClipboard(md)
                    alertMessage = "已将全部 \(bookStore.bookmarks.count) 条书签导出为 Markdown 至剪贴板"
                    showAlert = true
                } label: {
                    Label("导出 Markdown 至剪贴板", systemImage: "doc.richtext")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(bookStore.bookmarks.isEmpty)
        }
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

// MARK: - TxtTocRuleListView (Android TxtTocRuleActivity Counterpart)

public struct TxtTocRuleListView: View {
    @State private var rules: [TxtTocRule] = []
    @State private var editingRule: TxtTocRule? = nil
    @State private var isCreatingNew: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var importText: String = ""
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section(header: Text("目录拆分规则 (\(rules.count) 条)")) {
                ForEach(rules) { rule in
                    Button {
                        editingRule = rule
                        isCreatingNew = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(rule.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    if let ex = rule.example, !ex.isEmpty {
                                        Text("例: \(ex)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Text(rule.rule)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { rule.enable },
                                set: { newVal in
                                    if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                                        rules[idx].enable = newVal
                                        TxtTocRuleStore.save(rules)
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑") {
                            editingRule = rule
                            isCreatingNew = false
                        }
                        Button("删除", role: .destructive) {
                            rules.removeAll { $0.id == rule.id }
                            TxtTocRuleStore.save(rules)
                        }
                    }
                }
                .onDelete { indexSet in
                    rules.remove(atOffsets: indexSet)
                    TxtTocRuleStore.save(rules)
                }
                .onMove { source, destination in
                    rules.move(fromOffsets: source, toOffset: destination)
                    // serialNumber 即匹配优先级，重排后按显示顺序重写
                    for idx in rules.indices { rules[idx].serialNumber = idx }
                    TxtTocRuleStore.save(rules)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("TXT 目录规则")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    #if os(iOS)
                    EditButton()
                    #endif
                    Button {
                        editingRule = TxtTocRule(id: Int64(Date().timeIntervalSince1970 * 1000), name: "", rule: "", example: "")
                        isCreatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Menu {
                        Button("恢复默认规则") {
                            rules = TxtTocRuleStore.defaultRules
                            TxtTocRuleStore.save(rules)
                        }
                        Button("从剪贴板导入 JSON") {
                            showImportSheet = true
                        }
                        Button("导出规则至剪贴板") {
                            if let json = TxtTocRuleStore.exportJSON(rules) {
                                copyToClipboard(json)
                                alertMessage = "已将全部 TXT 目录规则导出至剪贴板"
                                showAlert = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            rules = TxtTocRuleStore.load()
        }
        .sheet(item: $editingRule) { rule in
            TxtTocRuleEditSheet(rule: rule, isNew: isCreatingNew) { saved in
                if let idx = rules.firstIndex(where: { $0.id == saved.id }) {
                    rules[idx] = saved
                } else {
                    rules.append(saved)
                }
                TxtTocRuleStore.save(rules)
            }
        }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        }
        .sheet(isPresented: $showImportSheet) {
            NavigationView {
                VStack(spacing: 12) {
                    TextEditor(text: $importText)
                        .padding(8)
                        .border(Color.secondary.opacity(0.2))
                        .frame(minHeight: 180)
                    Button("导入") {
                        rules = TxtTocRuleStore.importJSON(importText, into: rules)
                        TxtTocRuleStore.save(rules)
                        showImportSheet = false
                        importText = ""
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding()
                .navigationTitle("导入规则 JSON")
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

struct TxtTocRuleEditSheet: View {
    @State var rule: TxtTocRule
    let isNew: Bool
    let onSave: (TxtTocRule) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("规则配置")) {
                    HStack {
                        Text("规则名称")
                            .frame(width: 80, alignment: .leading)
                        TextField("如：第X章", text: $rule.name)
                    }
                    HStack {
                        Text("正则表达式")
                            .frame(width: 80, alignment: .leading)
                        TextField("^(第[0-9]+章.*)$", text: $rule.rule)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }
                    HStack {
                        Text("示例标题")
                            .frame(width: 80, alignment: .leading)
                        TextField("可选", text: Binding(
                            get: { rule.example ?? "" },
                            set: { rule.example = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    Toggle("启用该规则", isOn: $rule.enable)
                }
            }
            .navigationTitle(isNew ? "新建目录规则" : "编辑目录规则")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              rule.rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - ReadRecordListView (Android ReadRecordActivity Counterpart)

public struct ReadRecordListView: View {
    @State private var records: [ReadRecord] = []
    @State private var searchText: String = ""
    @State private var showClearConfirm: Bool = false

    public init() {}

    private var filteredRecords: [ReadRecord] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = records.sorted { $0.lastRead > $1.lastRead }
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { $0.bookName.localizedCaseInsensitiveContains(needle) }
    }

    private var totalDurationHours: String {
        let totalMs = records.reduce(0) { $0 + $1.readTime }
        let totalMinutes = totalMs / 60000
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours) 小时 \(mins) 分钟"
        } else {
            return "\(mins) 分钟"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("累计阅读时长")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(totalDurationHours)
                        .font(.title2.bold())
                        .foregroundColor(.accentColor)
                }
                Spacer()
                Text("共读过 \(records.count) 本书")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            if filteredRecords.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "暂无阅读记录" : "未找到匹配的记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(filteredRecords) { rec in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rec.bookName)
                                    .font(.subheadline.bold())
                                Text("上次阅读: \(formatDate(rec.lastRead))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(formatDuration(rec.readTime))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        let ids = Set(indexSet.map { filteredRecords[$0].id })
                        records.removeAll { ids.contains($0.id) }
                        ReadRecordStore.save(records)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .searchable(text: $searchText, prompt: "搜索书名")
        .navigationTitle("阅读记录")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清空") {
                    showClearConfirm = true
                }
                .disabled(records.isEmpty)
            }
        }
        .confirmationDialog("确认清空所有书籍的阅读时长记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空全部记录", role: .destructive) {
                records.removeAll()
                ReadRecordStore.save(records)
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            records = ReadRecordStore.load()
        }
    }

    private func formatDuration(_ ms: Int64) -> String {
        let mins = ms / 60000
        if mins >= 60 {
            return "\(mins / 60)小时\(mins % 60)分"
        } else if mins > 0 {
            return "\(mins)分钟"
        } else {
            return "<1分钟"
        }
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - DictRuleListView (Android DictRuleActivity Counterpart)

public struct DictRuleListView: View {
    @State private var rules: [DictRule] = []
    @State private var editingRule: DictRule? = nil
    @State private var isCreatingNew: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var importText: String = ""
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section(header: Text("字典规则列表 (\(rules.count) 条)")) {
                ForEach(rules) { rule in
                    Button {
                        editingRule = rule
                        isCreatingNew = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(rule.urlRule)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { newVal in
                                    if let idx = rules.firstIndex(where: { $0.name == rule.name }) {
                                        rules[idx].enabled = newVal
                                        DictRuleStore.save(rules)
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑") {
                            editingRule = rule
                            isCreatingNew = false
                        }
                        Button("删除", role: .destructive) {
                            rules.removeAll { $0.name == rule.name }
                            DictRuleStore.save(rules)
                        }
                    }
                }
                .onDelete { indexSet in
                    rules.remove(atOffsets: indexSet)
                    DictRuleStore.save(rules)
                }
                .onMove { source, destination in
                    rules.move(fromOffsets: source, toOffset: destination)
                    for idx in rules.indices { rules[idx].sortNumber = idx }
                    DictRuleStore.save(rules)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("字典规则")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    #if os(iOS)
                    EditButton()
                    #endif
                    Button {
                        editingRule = DictRule(name: "", urlRule: "https://...{{key}}", showRule: "body@text")
                        isCreatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Menu {
                        Button("恢复默认字典") {
                            rules = DictRuleStore.defaultRules
                            DictRuleStore.save(rules)
                        }
                        Button("从剪贴板导入 JSON") {
                            showImportSheet = true
                        }
                        Button("导出规则至剪贴板") {
                            if let json = DictRuleStore.exportJSON(rules) {
                                copyToClipboard(json)
                                alertMessage = "已将全部字典规则导出至剪贴板"
                                showAlert = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            rules = DictRuleStore.load()
        }
        .sheet(item: $editingRule) { rule in
            DictRuleEditSheet(rule: rule, isNew: isCreatingNew) { saved in
                if let idx = rules.firstIndex(where: { $0.name == saved.name }) {
                    rules[idx] = saved
                } else {
                    rules.append(saved)
                }
                DictRuleStore.save(rules)
            }
        }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        }
        .sheet(isPresented: $showImportSheet) {
            NavigationView {
                VStack(spacing: 12) {
                    TextEditor(text: $importText)
                        .padding(8)
                        .border(Color.secondary.opacity(0.2))
                        .frame(minHeight: 180)
                    Button("导入") {
                        rules = DictRuleStore.importJSON(importText, into: rules)
                        DictRuleStore.save(rules)
                        showImportSheet = false
                        importText = ""
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding()
                .navigationTitle("导入字典 JSON")
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

struct DictRuleEditSheet: View {
    @State var rule: DictRule
    let isNew: Bool
    let onSave: (DictRule) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    HStack {
                        Text("字典名称")
                            .frame(width: 80, alignment: .leading)
                        TextField("如：百度汉语", text: $rule.name)
                            .disabled(!isNew)
                    }
                    HStack {
                        Text("接口地址")
                            .frame(width: 80, alignment: .leading)
                        TextField("https://...{{key}}", text: $rule.urlRule)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }
                    Toggle("启用字典", isOn: $rule.enabled)
                }

                Section(header: Text("解释提取规则 (showRule)")) {
                    TextEditor(text: $rule.showRule)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(isNew ? "新建字典" : "编辑字典")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              rule.urlRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - HttpTTSListView (Android HttpTTSActivity Counterpart)

public struct HttpTTSListView: View {
    @State private var engines: [HttpTTS] = []
    @State private var editingEngine: HttpTTS? = nil
    @State private var isCreatingNew: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var importText: String = ""
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section(header: Text("朗读引擎列表 (\(engines.count) 个)")) {
                ForEach(engines) { engine in
                    Button {
                        editingEngine = engine
                        isCreatingNew = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(engine.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(engine.url.isEmpty ? "内置系统语音合成引擎" : engine.url)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { engine.enabled },
                                set: { newVal in
                                    if let idx = engines.firstIndex(where: { $0.id == engine.id }) {
                                        engines[idx].enabled = newVal
                                        HttpTTSStore.save(engines)
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑") {
                            editingEngine = engine
                            isCreatingNew = false
                        }
                        if engine.id != 1 {
                            Button("删除", role: .destructive) {
                                engines.removeAll { $0.id == engine.id }
                                HttpTTSStore.save(engines)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for idx in indexSet.sorted(by: >) where engines[idx].id != 1 {
                        engines.remove(at: idx)
                    }
                    HttpTTSStore.save(engines)
                }
                .onMove { source, destination in
                    engines.move(fromOffsets: source, toOffset: destination)
                    HttpTTSStore.save(engines)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("HttpTTS 引擎")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    #if os(iOS)
                    EditButton()
                    #endif
                    Button {
                        editingEngine = HttpTTS(name: "", url: "https://...{{speakText}}")
                        isCreatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Menu {
                        Button("恢复默认引擎") {
                            engines = HttpTTSStore.defaultEngines
                            HttpTTSStore.save(engines)
                        }
                        Button("从剪贴板导入 JSON") {
                            showImportSheet = true
                        }
                        Button("导出引擎至剪贴板") {
                            if let json = HttpTTSStore.exportJSON(engines) {
                                copyToClipboard(json)
                                alertMessage = "已将全部 HttpTTS 引擎导出至剪贴板"
                                showAlert = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            engines = HttpTTSStore.load()
        }
        .sheet(item: $editingEngine) { engine in
            HttpTTSEditSheet(engine: engine, isNew: isCreatingNew) { saved in
                if let idx = engines.firstIndex(where: { $0.id == saved.id }) {
                    engines[idx] = saved
                } else {
                    engines.append(saved)
                }
                HttpTTSStore.save(engines)
            }
        }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        }
        .sheet(isPresented: $showImportSheet) {
            NavigationView {
                VStack(spacing: 12) {
                    TextEditor(text: $importText)
                        .padding(8)
                        .border(Color.secondary.opacity(0.2))
                        .frame(minHeight: 180)
                    Button("导入") {
                        engines = HttpTTSStore.importJSON(importText, into: engines)
                        HttpTTSStore.save(engines)
                        showImportSheet = false
                        importText = ""
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding()
                .navigationTitle("导入 HttpTTS JSON")
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

struct HttpTTSEditSheet: View {
    @State var engine: HttpTTS
    let isNew: Bool
    let onSave: (HttpTTS) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基础配置")) {
                    HStack {
                        Text("引擎名称")
                            .frame(width: 80, alignment: .leading)
                        TextField("如：微软云 TTS", text: $engine.name)
                    }
                    HStack {
                        Text("接口地址")
                            .frame(width: 80, alignment: .leading)
                        TextField("https://...{{speakText}}", text: $engine.url)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }
                    HStack {
                        Text("Content-Type")
                            .frame(width: 80, alignment: .leading)
                        TextField("audio/mpeg", text: Binding(
                            get: { engine.contentType ?? "" },
                            set: { engine.contentType = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    Toggle("启用引擎", isOn: $engine.enabled)
                }

                Section(header: Text("请求头配置 (Header)")) {
                    TextEditor(text: Binding(
                        get: { engine.header ?? "" },
                        set: { engine.header = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                }
            }
            .navigationTitle(isNew ? "新建 TTS 引擎" : "编辑 TTS 引擎")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(engine)
                        dismiss()
                    }
                    .disabled(engine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - LocalWebServerView (WiFi 传书与局域网 Web 服务)

public struct LocalWebServerView: View {
    @ObservedObject var server = LocalWebServer.shared
    @ObservedObject var bookStore = BookStore.shared
    @State private var uploadNotice: String? = nil

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("服务状态")) {
                HStack {
                    Text("服务开关")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { server.isRunning },
                        set: { if $0 { server.start() } else { server.stop() } }
                    ))
                    .labelsHidden()
                }

                if server.isRunning {
                    HStack {
                        Text("网页传书地址")
                        Spacer()
                        Text(server.serverURLString)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                }
            }

            if server.isRunning {
                Section(header: Text("使用说明")) {
                    Text("请确保电脑或另一台设备与当前 iPhone / iPad 处于同一个 WiFi 局域网下，在电脑浏览器中直接输入上方网址，即可将 TXT 或 EPUB 小说快速上传到本地书架。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
            }

            if let notice = uploadNotice {
                Section(header: Text("传输动态")) {
                    Text(notice)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .navigationTitle("WiFi 传书")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            server.onBookUploaded = { filename, data in
                let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? data.write(to: tempFile)
                if let imported = try? bookStore.importFile(from: tempFile) {
                    uploadNotice = "已成功导入书籍：「\(imported.name)」"
                }
            }
        }
    }
}

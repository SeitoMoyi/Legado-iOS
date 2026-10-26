import SwiftUI
import UniformTypeIdentifiers
#if canImport(LegadoCore)
import LegadoCore
#endif

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct SourceManagerView: View {
    @ObservedObject var bookStore = BookStore.shared

    @State private var searchText: String = ""
    @State private var selectedGroupFilter: String = "全部"
    @State private var isSelecting: Bool = false
    @State private var isSortMode: Bool = false
    @State private var selectedUrls: Set<String> = []

    // Validation state
    @State private var isValidating: Bool = false
    @State private var validationChecked: Int = 0
    @State private var validationTotal: Int = 0
    @State private var validationFailedCount: Int = 0
    @State private var validationTask: Task<Void, Never>? = nil
    @State private var refreshTask: Task<Void, Never>?

    @State private var showImportSheet: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var selectedSourceForLogin: BookSource? = nil
    @State private var selectedSourceForEdit: BookSource? = nil
    @State private var selectedSourceForDebug: BookSource? = nil
    @State private var showNewSourceSheet: Bool = false
    @State private var selectedSourceForSearch: BookSource? = nil
    @State private var importText: String = ""
    @State private var importUrl: String = ""
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    // 扫码导入与分享二维码 (Plan 第一批 Part 3)
    @State private var showQRScanner: Bool = false
    @State private var scannedRaw: String = ""
    @State private var showScanResult: Bool = false
    @State private var qrShareJSON: String = ""
    @State private var showQRShare: Bool = false

    public init() {}

    private let availableGroupFilters: [String] = ["全部", "已启用", "已禁用"]

    private var sourceList: some View {
        List {
            Section(header: Text("书源 (\(filteredSources.count)/\(bookStore.sources.count))")) {
                ForEach(filteredSources) { source in
                    if isSelecting {
                        Button {
                            toggleSelection(for: source.bookSourceUrl)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedUrls.contains(source.bookSourceUrl) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedUrls.contains(source.bookSourceUrl) ? .accentColor : .secondary)
                                    .font(.system(size: 20))
                                sourceRow(for: source)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: SourceDetailView(source: source)) {
                            sourceRow(for: source)
                        }
                        .contextMenu {
                            Button {
                                selectedSourceForEdit = source
                            } label: {
                                Label("编辑规则", systemImage: "pencil")
                            }

                            Button {
                                selectedSourceForDebug = source
                            } label: {
                                Label("调试该源", systemImage: "ladybug")
                            }
                            Button {
                                bookStore.pinSource(sourceUrl: source.bookSourceUrl)
                            } label: {
                                Label("置顶", systemImage: "pin")
                            }

                            if !(source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                                Button {
                                    bookStore.toggleSourceExplore(sourceUrl: source.bookSourceUrl)
                                } label: {
                                    Label((source.enabledExplore ?? true) ? "禁用发现" : "启用发现",
                                          systemImage: (source.enabledExplore ?? true) ? "eye.slash" : "eye")
                                }
                            }

                            if source.loginUi != nil || source.loginUrl != nil {
                                Button {
                                    selectedSourceForLogin = source
                                } label: {
                                    Label(source.isLogged ? "重新登录" : "登录", systemImage: "person.badge.key")
                                }
                            }

                            Button {
                                SearchViewModel.shared.selectSource(url: source.bookSourceUrl)
                                selectedSourceForSearch = source
                            } label: {
                                Label("仅在此源搜索", systemImage: "magnifyingglass")
                            }

                            Button {
                                refreshSource(source)
                            } label: {
                                Label("刷新发现", systemImage: "arrow.clockwise")
                            }

                            Button {
                                copySourcesJSON(urls: [source.bookSourceUrl])
                            } label: {
                                Label("拷贝书源 JSON", systemImage: "doc.on.doc")
                            }

                            Button {
                                shareSourceQR(source)
                            } label: {
                                Label("生成分享二维码", systemImage: "qrcode")
                            }

                            Button(role: .destructive) {
                                bookStore.deleteSource(sourceUrl: source.bookSourceUrl)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete(perform: deleteFilteredSources)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private var filteredSources: [BookSource] {
        var list = bookStore.sources

        // 1. Group pill filter ("全部" / "已启用" / "已禁用")
        switch selectedGroupFilter {
        case "已启用":
            list = list.filter { $0.enabled ?? true }
        case "已禁用":
            list = list.filter { !($0.enabled ?? true) }
        default:
            break
        }
        // 2. Search bar filter (`group:xxx` or name/url/group substring)
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return list }

        if needle.lowercased().hasPrefix("group:") {
            let gName = String(needle.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if !gName.isEmpty {
                return list.filter { src in
                    src.groups.contains { $0.localizedCaseInsensitiveContains(gName) }
                }
            }
        }

        return list.filter { src in
            src.bookSourceName.localizedCaseInsensitiveContains(needle) ||
            src.bookSourceUrl.localizedCaseInsensitiveContains(needle) ||
            (src.bookSourceGroup?.localizedCaseInsensitiveContains(needle) ?? false) ||
            (src.bookSourceComment?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Group filter pill bar
            groupFilterBar

            // Validation progress banner
            if isValidating {
                validationBanner
            }

            sourceList

            if isSelecting {
                batchActionBar
            }
        }
        .searchable(text: $searchText, prompt: "搜索名称、域名或 group:分组")
        .navigationTitle("书源管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isSelecting {
                    Button("完成") {
                        withAnimation {
                            isSelecting = false
                            selectedUrls.removeAll()
                        }
                    }
                } else if isSortMode {
                    Button("完成") {
                        withAnimation { isSortMode = false }
                    }
                } else {
                    Menu {
                        Button {
                            withAnimation {
                                isSelecting = false
                                isSortMode.toggle()
                            }
                        } label: {
                            Label(isSortMode ? "退出拖拽排序" : "拖拽排序（优先级）",
                                  systemImage: isSortMode ? "checkmark.circle" : "arrow.up.arrow.down")
                        }

                        Button {
                            withAnimation {
                                isSortMode = false
                                isSelecting = true
                            }
                        } label: {
                            Label("选择", systemImage: "checkmark.circle")
                        }

                        Button {
                            showNewSourceSheet = true
                        } label: {
                            Label("新建空白书源", systemImage: "doc.badge.plus")
                        }

                        Button {
                            showImportSheet = true
                        } label: {
                            Label("导入书源", systemImage: "plus.circle")
                        }

                        Button {
                            showQRScanner = true
                        } label: {
                            Label("扫码导入", systemImage: "qrcode.viewfinder")
                        }
                        Button {
                            startBatchValidation(sources: filteredSources)
                        } label: {
                            Label(isValidating ? "停止校验" : "校验当前列表书源",
                                  systemImage: isValidating ? "stop.circle" : "checkmark.seal")
                        }

                        Button {
                            copySourcesJSON(urls: nil)
                        } label: {
                            Label("导出全部书源至剪贴板", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("确认删除选中的 \(selectedUrls.count) 个书源？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除 (\(selectedUrls.count))", role: .destructive) {
                bookStore.deleteSources(urls: selectedUrls)
                selectedUrls.removeAll()
                isSelecting = false
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showImportSheet) {
            importSourceSheet
        }
        .sheet(item: $selectedSourceForLogin) { source in
            SourceLoginSheet(source: source)
        }
        .sheet(item: $selectedSourceForEdit) { source in
            EditSourceSheet(source: source)
        }
        .sheet(item: $selectedSourceForDebug) { source in
            SourceDebugSheet(source: source)
        }
        .sheet(isPresented: $showNewSourceSheet) {
            EditSourceSheet(
                source: BookSource(bookSourceUrl: "", bookSourceName: ""),
                isCreatingNew: true
            )
        }
        .sheet(item: $selectedSourceForSearch) { _ in
            NavigationView {
                SearchBookView()
            }
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerSheet { raw in
                showQRScanner = false
                scannedRaw = raw
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showScanResult = true
                }
            }
        }
        .sheet(isPresented: $showScanResult) {
            ScanResultSheet(raw: scannedRaw)
        }
        .sheet(isPresented: $showQRShare) {
            QRCodeShareView(content: qrShareJSON, title: "书源二维码 · 用 Legado 扫码导入")
        }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var totalCount = 0
                var errorCount = 0
                for url in urls {
                    let canAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if canAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        if let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) {
                            let count = try bookStore.importSources(json: str)
                            totalCount += count
                        } else {
                            errorCount += 1
                        }
                    } catch {
                        errorCount += 1
                    }
                }
                showImportSheet = false
                if totalCount > 0 {
                    alertMessage = "成功导入 \(totalCount) 个书源！" + (errorCount > 0 ? " (\(errorCount)个文件解析失败)" : "")
                } else {
                    alertMessage = errorCount > 0 ? "导入失败：未能成功解析书源文件" : "未在文件中发现有效书源"
                }
                showAlert = true
            case .failure(let error):
                alertMessage = "打开文件失败: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    // MARK: - Subviews & Helpers

    private var groupFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableGroupFilters, id: \.self) { group in
                    let isSelected = (selectedGroupFilter == group)
                    Button {
                        selectedGroupFilter = group
                    } label: {
                        Text(group)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
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

    private var validationBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在校验书源 (\(validationChecked)/\(validationTotal)) · 失效 \(validationFailedCount)")
                    .font(.caption.weight(.medium))
                ProgressView(value: Double(validationChecked), total: Double(max(1, validationTotal)))
                    .progressViewStyle(.linear)
            }
            Spacer()
            Button("停止") {
                stopValidation()
            }
            .font(.caption.bold())
            .foregroundColor(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
    }

    private var batchActionBar: some View {
        let visibleUrls = Set(filteredSources.map { $0.bookSourceUrl })
        let allVisibleSelected = !visibleUrls.isEmpty && visibleUrls.isSubset(of: selectedUrls)

        return HStack(spacing: 16) {
            Button(allVisibleSelected ? "取消全选" : "全选") {
                if allVisibleSelected {
                    selectedUrls.subtract(visibleUrls)
                } else {
                    selectedUrls.formUnion(visibleUrls)
                }
            }
            .font(.caption.weight(.medium))

            Button("反选") {
                for u in visibleUrls {
                    if selectedUrls.contains(u) {
                        selectedUrls.remove(u)
                    } else {
                        selectedUrls.insert(u)
                    }
                }
            }
            .font(.caption.weight(.medium))

            Spacer()

            Button("启用") {
                bookStore.setSourcesEnabled(urls: selectedUrls, enabled: true)
            }
            .font(.caption.weight(.medium))
            .disabled(selectedUrls.isEmpty)

            Button("禁用") {
                bookStore.setSourcesEnabled(urls: selectedUrls, enabled: false)
            }
            .font(.caption.weight(.medium))
            .disabled(selectedUrls.isEmpty)

            Button("导出") {
                copySourcesJSON(urls: selectedUrls)
            }
            .font(.caption.weight(.medium))
            .disabled(selectedUrls.isEmpty)

            Button("删除(\(selectedUrls.count))") {
                showDeleteConfirm = true
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.red)
            .disabled(selectedUrls.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.12))
    }

    private func toggleSelection(for url: String) {
        if selectedUrls.contains(url) {
            selectedUrls.remove(url)
        } else {
            selectedUrls.insert(url)
        }
    }

    private func copySourcesJSON(urls: Set<String>?) {
        guard let json = bookStore.exportSourcesJSON(urls: urls) else {
            alertMessage = "没有可导出的书源"
            showAlert = true
            return
        }
        #if canImport(UIKit)
        UIPasteboard.general.string = json
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        #endif
        let count = urls?.count ?? bookStore.sources.count
        alertMessage = "已将 \(count) 个书源的 JSON 导出至剪贴板"
        showAlert = true
    }

    /// 生成分享二维码: single-source JSON, capped by QR data capacity (~2.4k bytes at
    /// correction level M keeps scanners reliable). Oversized sources fall back to a hint.
    private func shareSourceQR(_ source: BookSource) {
        guard let json = bookStore.exportSourcesJSON(urls: [source.bookSourceUrl]) else {
            alertMessage = "没有可导出的书源"
            showAlert = true
            return
        }
        guard json.utf8.count <= 2400 else {
            alertMessage = "「\(source.bookSourceName)」的 JSON 超出二维码容量，请改用「拷贝书源 JSON」分享"
            showAlert = true
            return
        }
        qrShareJSON = json
        showQRShare = true
    }

    private func startBatchValidation(sources: [BookSource]) {
        if isValidating {
            stopValidation()
            return
        }
        guard !sources.isEmpty else { return }
        isValidating = true
        validationChecked = 0
        validationTotal = sources.count
        validationFailedCount = 0

        validationTask = Task {
            let chunkSize = 5
            var index = 0
            while index < sources.count {
                if Task.isCancelled { break }
                let chunk = Array(sources[index..<min(index + chunkSize, sources.count)])
                await withTaskGroup(of: (String, Bool, Int64).self) { group in
                    for src in chunk {
                        group.addTask {
                            let start = Date()
                            do {
                                let results = try await BookSearchService.shared.search(
                                    source: src,
                                    key: (src.ruleSearch?.checkKeyWord).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "我的",
                                    page: 1
                                )
                                let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
                                return (src.bookSourceUrl, !results.isEmpty, elapsed)
                            } catch {
                                let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
                                return (src.bookSourceUrl, false, elapsed)
                            }
                        }
                    }

                    for await (url, passed, ms) in group {
                        if Task.isCancelled { break }
                        await MainActor.run {
                            bookStore.markSourceValidationResult(sourceUrl: url, passed: passed, respondTimeMs: ms)
                            validationChecked += 1
                            if !passed {
                                validationFailedCount += 1
                            }
                        }
                    }
                }
                index += chunk.count
            }

            await MainActor.run {
                let finished = !Task.isCancelled
                isValidating = false
                validationTask = nil
                if finished {
                    alertMessage = "校验完成：共校验 \(validationChecked) 个书源，发现 \(validationFailedCount) 个失效源（已标记「失效」）。"
                    showAlert = true
                }
            }
        }
    }

    private func stopValidation() {
        validationTask?.cancel()
        validationTask = nil
        isValidating = false
    }

    private func refreshSource(_ source: BookSource) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            do {
                let cats = try await BookExploreService.shared.loadExploreCategories(source: source)
                guard !Task.isCancelled else { return }
                alertMessage = "书源「\(source.bookSourceName)」分类解析完成（共 \(cats.count) 个分类）"
            } catch {
                guard !Task.isCancelled else { return }
                alertMessage = "分类解析失败：\(error.localizedDescription)"
            }
            showAlert = true
        }
    }

    @ViewBuilder
    private func sourceRow(for source: BookSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.bookSourceName)
                        .font(.headline)
                    if let group = source.displayGroup, !group.isEmpty {
                        Text(group)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(group.contains("失效") ? Color.red.opacity(0.15) : Color.secondary.opacity(0.12))
                            .foregroundColor(group.contains("失效") ? .red : .secondary)
                            .cornerRadius(4)
                    }
                    if let ms = source.respondTime, BookSource.isMeasuredRespondTime(ms) {
                        Text("\(ms)ms")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ms < 2000 ? .green : .orange)
                    }
                    if source.loginUi != nil || source.loginUrl != nil {
                        loginButton(for: source)
                    }
                }
                Text(source.bookSourceUrl)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !isSelecting {
                Toggle("", isOn: Binding(
                    get: { source.enabled ?? true },
                    set: { _ in bookStore.toggleSource(sourceUrl: source.bookSourceUrl) }
                ))
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func loginButton(for source: BookSource) -> some View {
        Button(action: {
            selectedSourceForLogin = source
        }) {
            HStack(spacing: 3) {
                Image(systemName: source.isLogged ? "checkmark.shield.fill" : "person.badge.key")
                Text(source.isLogged ? "已登录" : "登录")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(source.isLogged ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
            .foregroundColor(source.isLogged ? .green : .blue)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func deleteFilteredSources(at offsets: IndexSet) {
        let targets = offsets.map { filteredSources[$0].bookSourceUrl }
        bookStore.deleteSources(urls: Set(targets))
    }
    private var importSourceSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("本地文件导入")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("从本地文件导入 (.json)", systemImage: "doc.badge.plus")
                    }
                }

                Section(header: Text("扫码导入")) {
                    Button {
                        showImportSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showQRScanner = true
                        }
                    } label: {
                        Label("扫描二维码导入", systemImage: "qrcode.viewfinder")
                    }
                }

                Section(header: Text("网络导入 (JSON URL)")) {
                    TextField("输入书源网址 (https://...)", text: $importUrl)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                    Button("从网络获取并导入") {
                        importFromUrl()
                    }
                    .disabled(importUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section(header: Text("剪贴板 / 本地文本导入")) {
                    TextEditor(text: $importText)
                        .frame(height: 120)
                    Button("导入 JSON 文本") {
                        importFromText()
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("导入书源")
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

    private func importFromText() {
        do {
            let count = try bookStore.importSources(json: importText)
            showImportSheet = false
            importText = ""
            alertMessage = "成功导入 \(count) 个书源！"
            showAlert = true
        } catch {
            alertMessage = "导入失败: JSON 格式错误"
            showAlert = true
        }
    }

    private func importFromUrl() {
        guard let url = URL(string: importUrl.trimmingCharacters(in: .whitespaces)) else {
            alertMessage = "无效的 URL"
            showAlert = true
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let jsonStr = String(data: data, encoding: .utf8) else {
                    await MainActor.run {
                        alertMessage = "无法读取网络数据"
                        showAlert = true
                    }
                    return
                }

                await MainActor.run {
                    do {
                        let count = try bookStore.importSources(json: jsonStr)
                        showImportSheet = false
                        importUrl = ""
                        alertMessage = "成功从网络导入 \(count) 个书源！"
                        showAlert = true
                    } catch {
                        alertMessage = "书源格式解析失败: \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "网络请求失败: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}

public struct SourceLoginSheet: View {
    let source: BookSource
    let onLoginCompleted: ((BookSource) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var loginMode: String
    @State private var fields: [LoginField] = []
    @State private var fieldValues: [String: String] = [:]
    @State private var isLoggingIn: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var loginTask: Task<Void, Never>?
    @State private var buttonURL: String?
    @State private var showButtonBrowser = false

    typealias LoginField = SourceLoginRow

    /// A plain http(s) loginUrl means web login; `<js>` / `@js:` scripts mean form login.
    private static func isWebLoginDefault(_ source: BookSource) -> Bool {
        guard let loginUrl = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !loginUrl.isEmpty else {
            return false
        }
        return (loginUrl.hasPrefix("http://") || loginUrl.hasPrefix("https://")) &&
               !loginUrl.contains("<js>") &&
               !loginUrl.contains("@js:")
    }

    private var isWebLoginDefault: Bool { Self.isWebLoginDefault(source) }

    public init(source: BookSource, onLoginCompleted: ((BookSource) -> Void)? = nil) {
        self.source = source
        self.onLoginCompleted = onLoginCompleted
        self._loginMode = State(initialValue: Self.isWebLoginDefault(source) ? "web" : "form")
    }

    public var body: some View {
        if isWebLoginDefault || loginMode == "web" {
            SourceWebLoginView(source: source, onLoginCompleted: onLoginCompleted)
        } else {
            formLoginView
        }
    }

    private var formLoginView: some View {
        NavigationView {
            Form {
                Section(header: Text("书源信息")) {
                    Text(source.bookSourceName)
                        .font(.headline)
                    Text(source.bookSourceUrl)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if source.isLogged {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("当前状态：已登录")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        }
                    }
                }

                Section(header: Text("登录模式切换")) {
                    Picker("登录模式", selection: $loginMode) {
                        Text("表单脚本登录").tag("form")
                        Text("网页/Cookie 登录").tag("web")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("账号登录表单")) {
                    if fields.isEmpty {
                        Text("该书源无需配置字段，直接点击下方按钮执行登录脚本")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(fields) { field in
                            if field.type == "button" {
                                Button(field.name) { performButton(field) }.disabled(isLoggingIn)
                            } else if field.type == "password" {
                                SecureField(field.name, text: Binding(
                                    get: { fieldValues[field.name] ?? "" },
                                    set: { fieldValues[field.name] = $0 }
                                ))
                            } else {
                                TextField(field.name, text: Binding(
                                    get: { fieldValues[field.name] ?? "" },
                                    set: { fieldValues[field.name] = $0 }
                                ))
                                #if os(iOS)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                #endif
                            }
                        }
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }

                if let succ = successMessage {
                    Section {
                        Text(succ)
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button(action: performLogin) {
                        if isLoggingIn {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("正在执行登录...").padding(.leading, 8)
                                Spacer()
                            }
                        } else {
                            Text(source.isLogged ? "重新登录" : "立即登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoggingIn)

                    if source.isLogged {
                        Button(role: .destructive, action: {
                            if let completed = onLoginCompleted {
                                var updated = source; updated.loginHeader = nil; updated.loginInfo = nil
                                SourceSessionStore.save(header: nil, for: source.bookSourceUrl)
                                completed(updated)
                            } else { BookStore.shared.logoutSource(sourceUrl: source.bookSourceUrl) }
                            dismiss()
                        }) {
                            Text("退出登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("书源登录")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear(perform: parseLoginUi)
            .onDisappear { loginTask?.cancel() }
            .sheet(isPresented: $showButtonBrowser) {
                if let url = buttonURL { SourceBrowserView(initialURL: url, source: source) }
            }
        }
    }

    private func parseLoginUi() {
        if let info = source.loginInfo, let data = info.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            fieldValues = dict
        }

        let parsed = SourceLoginRow.parse(source.loginUi)
        fields = parsed.isEmpty && source.loginUi == nil ? [LoginField(name: "账号"), LoginField(name: "密码", type: "password")] : parsed
    }

    private func performButton(_ field: LoginField) {
        guard let action = field.action else { return }
        if RuleSubscriptionService.validURL(action) != nil {
            buttonURL = action; showButtonBrowser = true
        } else { execute(action: action) }
    }

    private func performLogin() { execute(action: nil) }

    private func execute(action: String?) {
        loginTask?.cancel()
        isLoggingIn = true; errorMessage = nil; successMessage = nil
        loginTask = Task { @MainActor in
            defer { if !Task.isCancelled { isLoggingIn = false } }
            do {
                let result = try await SourceLoginService.execute(source: source, credentials: fieldValues, action: action)
                try Task.checkCancellation()
                var updated = source
                updated.loginInfo = result.info
                if let header = result.header {
                    updated.loginHeader = header
                    SourceSessionStore.save(header: header, for: source.bookSourceUrl)
                }
                if let completed = onLoginCompleted { completed(updated) }
                else { BookStore.shared.applyLoginState(sourceURL: source.bookSourceUrl, header: updated.loginHeader, info: updated.loginInfo) }
                successMessage = action == nil ? "登录成功！" : result.message ?? "操作完成"
                if action == nil { dismiss() }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
}

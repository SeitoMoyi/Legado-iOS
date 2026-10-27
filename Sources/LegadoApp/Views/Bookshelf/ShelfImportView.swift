import SwiftUI
import UniformTypeIdentifiers
#if canImport(LegadoCore)
import LegadoCore
#endif

struct ShelfImportView: View {
    @ObservedObject var bookStore: BookStore
    let groupID: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var preview: [ShelfBookInfo] = []
    @State private var selected = Set<String>()
    @State private var statuses: [String: String] = [:]
    @State private var message = ""
    @State private var running = false
    @State private var showFile = false
    @State private var task: Task<Void, Never>?
    @State private var runID = UUID()

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("输入 Android 书单 JSON 或网址。按书名和作者精确搜索已启用书源，保留书架已有书籍与阅读进度。备份恢复请使用「备份与恢复」。")) {
                    TextEditor(text: $input).frame(minHeight: 120).disabled(running)
                    HStack {
                        Button("选择文件") { showFile = true }.disabled(running)
                        Spacer()
                        Button("预览") { loadPreview() }.disabled(running || input.isEmpty)
                    }
                }
                if !preview.isEmpty {
                    Section(header: Text("选择书籍 (\(selected.count)/\(preview.count))")) {
                        ForEach(preview) { info in
                            Button {
                                if selected.contains(info.id) { selected.remove(info.id) } else { selected.insert(info.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(info.name)
                                        Text(statuses[info.id] ?? info.author).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selected.contains(info.id) { Image(systemName: "checkmark") }
                                }
                            }.disabled(running)
                        }
                    }
                }
                if !message.isEmpty { Text(message).font(.caption) }
                if running { ProgressView("正在处理…") }
            }
            .navigationTitle("导入书单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { stop(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if running { Button("停止") { stop() } }
                    else { Button("导入") { importSelected() }.disabled(selected.isEmpty) }
                }
            }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.json, .plainText]) { result in
                do {
                    let url = try result.get()
                    begin { _ in
                        let values = try await Task.detached {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= ShelfImportService.maximumBytes else { throw RuleSubscriptionError.tooLarge }
                            return try ShelfImportService.parse(Data(contentsOf: url))
                        }.value
                        try Task.checkCancellation()
                        showPreview(values)
                    }
                } catch { message = error.localizedDescription }
            }
            .onDisappear { stop() }
        }
    }

    private func stop() { task?.cancel(); runID = UUID(); running = false }
    private func begin(_ work: @escaping @MainActor (UUID) async throws -> Void) {
        task?.cancel()
        let id = UUID(); runID = id; running = true; message = ""
        task = Task { @MainActor in
            defer { if runID == id { running = false } }
            do { try await work(id) }
            catch { if !Task.isCancelled, runID == id { message = error.localizedDescription; AppLogStore.shared.record("书单", message) } }
        }
    }
    private func loadPreview() {
        let text = input
        begin { _ in
            let values = try await ShelfImportService.load(text)
            try Task.checkCancellation()
            showPreview(values)
        }
    }
    private func showPreview(_ values: [ShelfBookInfo]) {
        preview = values; selected = Set(values.map(\.id)); statuses = [:]
        message = "已识别 \(values.count) 本书，导入后会搜索当前启用的书源。"
    }
    private func importSelected() {
        let books = preview.filter { selected.contains($0.id) }
        let sources = bookStore.sources
        begin { id in
            var added = 0; var skipped = 0; var missing = 0
            for info in books {
                try Task.checkCancellation()
                guard runID == id else { return }
                if bookStore.bookshelf.contains(where: { $0.name == info.name && $0.author == info.author }) {
                    statuses[info.id] = "书架已有，已保留"; skipped += 1; continue
                }
                statuses[info.id] = "正在搜索…"
                if let book = try await ShelfImportService.find(info, sources: sources) {
                    try Task.checkCancellation()
                    guard runID == id else { return }
                    if try bookStore.insertShelfImport(book, groupID: groupID) { added += 1; statuses[info.id] = "已加入书架" }
                    else { skipped += 1; statuses[info.id] = "书架已有，已保留" }
                } else { missing += 1; statuses[info.id] = "没有精确匹配"; AppLogStore.shared.record("书单", "没有搜索到《\(info.name)》 \(info.author)") }
            }
            message = "新增 \(added) 本，已有 \(skipped) 本，未找到 \(missing) 本。"
            AppLogStore.shared.record("书单", message)
        }
    }
}

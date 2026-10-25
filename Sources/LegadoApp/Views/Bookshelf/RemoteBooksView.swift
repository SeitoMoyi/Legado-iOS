import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

// MARK: - Remote Books View (Plan 第一批 书架二级菜单 ④: 远程书籍)
//
// WebDAV directory browser reusing the service's PROPFIND plumbing. Pick a `.txt` / `.epub`,
// download it through the authenticated session and push it through the same local import
// chain the 添加本地 file importer uses.

public struct RemoteBooksView: View {
    @ObservedObject private var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    var onImported: ((Book) -> Void)? = nil

    @State private var path: [String] = []
    @State private var entries: [WebDAVService.RemoteDirectoryEntry] = []
    @State private var isLoading: Bool = false
    @State private var isImporting: Bool = false
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @State private var notConfigured: Bool = false
    @State private var statusMessage: String? = nil

    private static let importableExtensions: Set<String> = ["txt", "epub"]

    public init(onImported: ((Book) -> Void)? = nil) {
        self.onImported = onImported
    }

    private var currentDirectoryURL: URL? {
        let config = WebDAVService.shared.loadConfig()
        guard !config.url.isEmpty else { return nil }
        var url = config.directoryURL
        for component in path {
            url = url?.appendingPathComponent(component)
        }
        return url
    }

    public var body: some View {
        NavigationView {
            Group {
                if notConfigured {
                    notConfiguredView
                } else {
                    listView
                }
            }
            .navigationTitle("远程书籍")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || notConfigured)
                }
            }
            .overlay {
                if isImporting {
                    importingOverlay
                }
            }
            .alert("导入失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .task {
                await load()
            }
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text("未配置 WebDAV")
                .font(.headline)
            Text("请先到「我的 - 备份与恢复」完成 WebDAV 配置，再从网盘导入书籍。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            // Breadcrumb
            Section {
                HStack(spacing: 8) {
                    Button("根目录") {
                        path.removeAll()
                        Task { await load() }
                    }
                    .buttonStyle(.plain)
                    ForEach(Array(path.enumerated()), id: \.offset) { index, component in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button(component) {
                            path = Array(path.prefix(index + 1))
                            Task { await load() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.footnote)
            }

            Section {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取目录...")
                            .foregroundColor(.secondary)
                    }
                } else if entries.isEmpty {
                    Text("目录为空")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            } footer: {
                Text("支持导入 .txt / .epub 文件，其余类型仅作浏览。")
            }

            if let status = statusMessage {
                Section {
                    Label(status, systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.footnote)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    @ViewBuilder
    private func row(_ entry: WebDAVService.RemoteDirectoryEntry) -> some View {
        let isImportable = Self.importableExtensions.contains(
            (entry.name as NSString).pathExtension.lowercased())
        Button {
            if entry.isDirectory {
                path.append(entry.name)
                Task { await load() }
            } else if isImportable {
                Task { await importEntry(entry) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory
                      ? "folder.fill"
                      : (isImportable ? "book.closed.fill" : "doc"))
                    .foregroundColor(entry.isDirectory ? .accentColor
                                      : (isImportable ? .orange : .secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    if let size = entry.size, !entry.isDirectory {
                        Text(CacheManageView.byteCount(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if !entry.isDirectory && isImportable {
                    Text("导入")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var importingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在下载并导入...")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    private func load() async {
        guard let url = currentDirectoryURL else {
            await MainActor.run { notConfigured = true }
            return
        }
        await MainActor.run {
            isLoading = true
            statusMessage = nil
            notConfigured = false
        }
        do {
            let config = WebDAVService.shared.loadConfig()
            let list = try await WebDAVService.shared.listDirectory(url: url, config: config)
            await MainActor.run { entries = list; isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                entries = []
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func importEntry(_ entry: WebDAVService.RemoteDirectoryEntry) async {
        let config = WebDAVService.shared.loadConfig()
        guard !config.url.isEmpty else {
            await MainActor.run { notConfigured = true }
            return
        }
        await MainActor.run { isImporting = true }
        do {
            let data = try await WebDAVService.shared.downloadFileData(url: entry.url, config: config)
            let ext = (entry.name as NSString).pathExtension.lowercased()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("remote-\(UUID().uuidString).\(ext)")
            try data.write(to: tmp)
            let book = try bookStore.importFile(from: tmp)
            try? FileManager.default.removeItem(at: tmp)
            await MainActor.run {
                isImporting = false
                statusMessage = "已导入「\(book.name)」"
                onImported?(book)
            }
        } catch {
            await MainActor.run {
                isImporting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

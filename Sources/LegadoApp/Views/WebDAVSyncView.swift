import SwiftUI
import UniformTypeIdentifiers
#if canImport(LegadoCore)
import LegadoCore
#endif

public struct WebDAVSyncView: View {
    @ObservedObject var bookStore = BookStore.shared

    @State private var url: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var remotePath: String = "legado"
    @State private var lastSyncTime: Date? = nil

    @State private var isTesting: Bool = false
    @State private var isBackingUp: Bool = false
    @State private var isRestoring: Bool = false
    @State private var showFileImporter: Bool = false

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showRestoreConfirm: Bool = false

    public init() {}

    private var currentConfig: WebDAVConfig {
        WebDAVConfig(
            url: url,
            username: username,
            password: password,
            remotePath: remotePath,
            lastSyncTime: lastSyncTime
        )
    }

    public var body: some View {
        Form {
            serverConfigSection
            statusSection
            actionsSection
            localBackupSection
        }
        .navigationTitle("WebDAV 云同步")
        .onAppear {
            loadConfig()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("从 WebDAV 恢复", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定恢复", role: .destructive) {
                saveConfig()
                restoreFromWebDAV()
            }
        } message: {
            Text("恢复操作将从 WebDAV 下载最新备份（bookshelf.json 或 Android backup*.zip），并与当前本地数据合并更新。是否继续？")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.zip, .archive],
            allowsMultipleSelection: false
        ) { result in
            handleLocalZipImport(result: result)
        }
    }

    @ViewBuilder
    private var serverConfigSection: some View {
        Section {
            HStack {
                Text("服务器地址")
                    .frame(width: 85, alignment: .leading)
                TextField("https://dav.jianguoyun.com/dav/", text: $url)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif
            }

            HStack {
                Text("账号")
                    .frame(width: 85, alignment: .leading)
                TextField("坚果云账号/邮箱", text: $username)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif
            }

            HStack {
                Text("密码")
                    .frame(width: 85, alignment: .leading)
                SecureField("应用密码 / 访问凭证", text: $password)
            }

            HStack {
                Text("远程目录")
                    .frame(width: 85, alignment: .leading)
                TextField("legado", text: $remotePath)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif
            }

            // Quick presets
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷填入服务预设")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Button("坚果云") {
                        url = "https://dav.jianguoyun.com/dav/"
                        if remotePath.isEmpty { remotePath = "legado" }
                        saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Button("InfiniCLOUD") {
                        url = "https://teracloud.jp/dav/"
                        if remotePath.isEmpty { remotePath = "legado" }
                        saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Button("Nextcloud") {
                        url = "https://example.com/remote.php/dav/files/user/"
                        if remotePath.isEmpty { remotePath = "legado" }
                        saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("WebDAV 服务器设置")
        } footer: {
            Text("提示：坚果云等服务需在网页端设置 -> 安全设置中生成「应用专用密码」填入。")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text("同步状态")) {
            HStack {
                Text("上次同步时间")
                Spacer()
                if let date = lastSyncTime {
                    Text(formatDate(date))
                        .foregroundColor(.secondary)
                } else {
                    Text("暂未同步")
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("本地书架")
                Spacer()
                Text("\(bookStore.bookshelf.count) 本")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("本地书源")
                Spacer()
                Text("\(bookStore.sources.count) 个")
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section(header: Text("同步操作")) {
            Button {
                saveConfig()
                testConnection()
            } label: {
                HStack {
                    if isTesting {
                        ProgressView()
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(isTesting ? "正在测试连接..." : "测试连接")
                }
            }
            .disabled(isTesting || isBackingUp || isRestoring || url.isEmpty)

            Button {
                saveConfig()
                backupToWebDAV()
            } label: {
                HStack {
                    if isBackingUp {
                        ProgressView()
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "arrow.up.doc")
                    }
                    Text(isBackingUp ? "正在备份中..." : "立即备份至 WebDAV")
                }
            }
            .disabled(isTesting || isBackingUp || isRestoring || url.isEmpty || username.isEmpty)

            Button(role: .destructive) {
                showRestoreConfirm = true
            } label: {
                HStack {
                    if isRestoring {
                        ProgressView()
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "arrow.down.doc")
                    }
                    Text(isRestoring ? "正在恢复中..." : "从 WebDAV 恢复数据")
                }
            }
            .disabled(isTesting || isBackingUp || isRestoring || url.isEmpty || username.isEmpty)
        }
    }

    @ViewBuilder
    private var localBackupSection: some View {
        Section(header: Text("本地备份导入 (兼容 Android Legado)")) {
            Button {
                showFileImporter = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.arrow.up")
                    Text("导入本地 Android 备份包 (.zip)")
                }
            }

            Text("支持选取 Android 版 Legado 导出的 backup*.zip 备份包（可配合 bookProgress 进度目录），自动恢复 100% 书籍、书源与阅读进度，无需经过网络直接生效。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func handleLocalZipImport(result: Result<[URL], Error>) {
        do {
            guard let selectedUrl = try result.get().first else { return }
            let canAccess = selectedUrl.startAccessingSecurityScopedResource()
            defer {
                if canAccess { selectedUrl.stopAccessingSecurityScopedResource() }
            }

            let (books, sources) = try WebDAVService.shared.restoreFromZip(fileUrl: selectedUrl)
            let (bCount, sCount) = bookStore.restoreFromWebDAV(books: books, sources: sources)

            alertTitle = "备份包导入成功"
            alertMessage = "成功识别并合并 Android 备份数据：\n• 书架更新/新增: \(bCount) 本\n• 书源更新/新增: \(sCount) 个"
            showAlert = true
        } catch {
            alertTitle = "导入失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func loadConfig() {
        let config = WebDAVService.shared.loadConfig()
        self.url = config.url
        self.username = config.username
        self.password = config.password
        self.remotePath = config.remotePath
        self.lastSyncTime = config.lastSyncTime
    }

    private func saveConfig() {
        WebDAVService.shared.saveConfig(currentConfig)
    }

    private func testConnection() {
        isTesting = true
        Task {
            do {
                let msg = try await WebDAVService.shared.testConnection(config: currentConfig)
                await MainActor.run {
                    isTesting = false
                    alertTitle = "测试连接成功"
                    alertMessage = msg
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    alertTitle = "测试连接失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func backupToWebDAV() {
        isBackingUp = true
        Task {
            do {
                let result = try await WebDAVService.shared.backup(
                    books: bookStore.bookshelf,
                    sources: bookStore.sources,
                    config: currentConfig
                )
                await MainActor.run {
                    isBackingUp = false
                    lastSyncTime = Date()
                    alertTitle = "备份成功"
                    alertMessage = "已成功上传至 WebDAV 远程目录 [\(remotePath)]：\n• 书架藏书：\(result.booksCount) 本\n• 书源配置：\(result.sourcesCount) 个"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isBackingUp = false
                    alertTitle = "备份失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func restoreFromWebDAV() {
        isRestoring = true
        Task {
            do {
                let (books, sources) = try await WebDAVService.shared.restore(config: currentConfig)
                let result = bookStore.restoreFromWebDAV(books: books, sources: sources)
                await MainActor.run {
                    isRestoring = false
                    lastSyncTime = Date()
                    alertTitle = "恢复成功"
                    var detail = "已完成从 WebDAV 数据合并：\n"
                    if let b = books {
                        detail += "• 书架同步：\(b.count) 本 (新增 \(result.booksAdded) 本)\n"
                    } else {
                        detail += "• 未找到远程 bookshelf.json\n"
                    }
                    if let s = sources {
                        detail += "• 书源同步：\(s.count) 个 (新增 \(result.sourcesAdded) 个)"
                    } else {
                        detail += "• 未找到远程 bookSource.json"
                    }
                    alertMessage = detail
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    alertTitle = "恢复失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

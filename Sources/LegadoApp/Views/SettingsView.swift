import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

public struct SettingsView: View {

    @ObservedObject var bookStore = BookStore.shared
    @ObservedObject var readerConfig = ReaderConfig.shared

    @AppStorage("legado_app_theme") private var appTheme: String = "system"

    @State private var showRestoreAlert: Bool = false
    @State private var restoreSuccessMessage: String? = nil
    @State private var showClearCacheAlert: Bool = false
    @State private var clearCacheMessage: String? = nil

    public init() {}

    /// Read from the bundle so the screen cannot drift from `MARKETING_VERSION` — it used to
    /// say 1.0.0 while the project and the VERSION file said 0.2.0.
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "未知"
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("书源管理")) {
                    NavigationLink(destination: SourceManagerView()) {
                        HStack {
                            Text("管理全部网络书源")
                            Spacer()
                            Text("\(bookStore.sources.filter { $0.enabled != false }.count) / \(bookStore.sources.count) 个可用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showRestoreAlert = true
                    } label: {
                        HStack {
                            Text("恢复预装默认书源")
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                Section(header: Text("书架与存储")) {
                    HStack {
                        Text("书架藏书")
                        Spacer()
                        Text("\(bookStore.bookshelf.count) 本")
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        showClearCacheAlert = true
                    } label: {
                        HStack {
                            Text("清理阅读缓存")
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("外观模式")) {
                    Picker("外观模式", selection: $appTheme) {
                        Text("跟随系统").tag("system")
                        Text("浅色模式").tag("light")
                        Text("深色模式").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("数据与云备份")) {
                    NavigationLink(destination: WebDAVSyncView()) {
                        HStack {
                            Label("WebDAV 云同步", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            if WebDAVService.shared.loadConfig().lastSyncTime != nil {
                                Text("已同步")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("未配置")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("正文处理")) {
                    NavigationLink(destination: ReplaceRuleListView()) {
                        HStack {
                            Text("替换净化")
                            Spacer()
                            Text("\(bookStore.replaceRules.filter { $0.isEnabled }.count) / \(bookStore.replaceRules.count) 条启用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

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

                Section(header: Text("关于 Legado iOS")) {
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
                        Text("Swift 原生 + JavaScriptCore")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .alert("恢复默认书源", isPresented: $showRestoreAlert) {
                Button("取消", role: .cancel) {}
                Button("确定恢复", role: .destructive) {
                    bookStore.loadBundledSources(forceReset: true)
                    restoreSuccessMessage = "已恢复预装书源"
                }
            } message: {
                Text("确定要将书源列表恢复为预装默认状态吗？自定义导入的书源可能被覆盖。")
            }
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
        }
    }
}

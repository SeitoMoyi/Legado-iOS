import SwiftUI
import WebKit
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Shared in-app browser for source actions and ordinary browsing. WebKit owns its
/// navigation and download tasks; downloaded files remain available until deleted.
struct SourceBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: SourceBrowserState
    @State private var showDownloads = false

    init(initialURL: String = "", source: BookSource? = nil) {
        _state = StateObject(wrappedValue: SourceBrowserState(initialURL: initialURL, source: source))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    TextField("网址", text: $state.address).textFieldStyle(.roundedBorder)
                        .onSubmit { state.openAddress() }
                    Button("前往") { state.openAddress() }
                }.padding(8)
                BrowserSurface(webView: state.webView)
                HStack {
                    Button { state.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    Button { state.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    Button { state.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    if state.loading { ProgressView() }
                    Button("下载 (\(state.files.count))") { state.reloadFiles(); showDownloads = true }
                }.padding()
            }
            .navigationTitle(state.title.isEmpty ? "浏览器" : state.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showDownloads) {
                NavigationView {
                    List {
                        if state.activeDownloads > 0 { Text("正在下载 \(state.activeDownloads) 个文件…") }
                        ForEach(state.files, id: \.self) { file in
                            VStack(alignment: .leading) {
                                Text(file.lastPathComponent).font(.caption)
                                if ["txt", "epub"].contains(file.pathExtension.lowercased()) {
                                    Button("导入书架") {
                                        do { let book = try BookStore.shared.importFile(from: file); state.message = "已导入《\(book.name)》" }
                                        catch { state.message = error.localizedDescription }
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { try? FileManager.default.removeItem(at: state.files[index]) }
                            state.reloadFiles()
                        }
                    }
                    .navigationTitle("下载文件")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showDownloads = false } } }
                    .overlay(alignment: .bottom) {
                        if let message = state.message { Text(message).font(.caption).padding().background(.regularMaterial) }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = state.message, !showDownloads { Text(message).font(.caption).padding().background(.regularMaterial) }
            }
            .onAppear { state.startIfNeeded() }
            .onDisappear { state.stop() }
        }
    }
}

private final class SourceBrowserState: NSObject, ObservableObject, WKNavigationDelegate, WKDownloadDelegate {
    @Published var address: String
    @Published var title = ""
    @Published var loading = false
    @Published var files: [URL] = []
    @Published var activeDownloads = 0
    @Published var message: String?
    let webView: WKWebView
    private let source: BookSource?
    private var started = false
    private var headerTask: Task<Void, Never>?
    private var downloads: [ObjectIdentifier: (WKDownload, URL?)] = [:]
    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BrowserDownloads", isDirectory: true)
    }

    init(initialURL: String, source: BookSource?) {
        self.address = initialURL; self.source = source
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = NetworkClient.defaultUserAgent
        reloadFiles()
    }

    func startIfNeeded() { if !started { started = true; if !address.isEmpty { openAddress() } } }
    func openAddress() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = RuleSubscriptionService.validURL(text.contains("://") ? text : "https://" + text) else {
            message = "请输入有效的 HTTP 或 HTTPS 地址"; return
        }
        message = nil
        headerTask?.cancel()
        headerTask = Task { @MainActor in
            var request = URLRequest(url: url)
            let headers = await SourceWebSession.prepare(source: source, url: url, webView: webView)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            guard !Task.isCancelled else { return }
            webView.load(request)
        }
    }
    func stop() {
        headerTask?.cancel()
        webView.stopLoading()
        for (_, item) in downloads { item.0.cancel { _ in }; if let url = item.1 { try? FileManager.default.removeItem(at: url) } }
        downloads.removeAll(); activeDownloads = 0
    }
    func reloadFiles() {
        files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; title = webView.title ?? ""; address = webView.url?.absoluteString ?? address
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false; message = error.localizedDescription }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false; message = error.localizedDescription }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) else { decisionHandler(.cancel); return }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { track(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { track(download) }
    private func track(_ download: WKDownload) { downloads[ObjectIdentifier(download)] = (download, nil); activeDownloads = downloads.count; download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = WebDAVService.shared.sanitizeFileName(URL(fileURLWithPath: suggestedFilename).lastPathComponent)
            let target = directory.appendingPathComponent("." + UUID().uuidString + "-" + (filename.isEmpty ? "download" : filename))
            downloads[ObjectIdentifier(download)] = (download, target)
            completionHandler(target)
        } catch { message = error.localizedDescription; completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let item = downloads.removeValue(forKey: ObjectIdentifier(download)), let temporary = item.1 else { return }
        do {
            let target = temporary.deletingLastPathComponent().appendingPathComponent(String(temporary.lastPathComponent.dropFirst()))
            try FileManager.default.moveItem(at: temporary, to: target)
            message = "下载完成"
        } catch { message = error.localizedDescription }
        activeDownloads = downloads.count; reloadFiles()
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let item = downloads.removeValue(forKey: ObjectIdentifier(download)), let url = item.1 { try? FileManager.default.removeItem(at: url) }
        activeDownloads = downloads.count; message = error.localizedDescription
    }
}

#if os(iOS)
private struct BrowserSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
private struct BrowserSurface: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

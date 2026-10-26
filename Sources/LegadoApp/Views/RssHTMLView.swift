import SwiftUI
import WebKit
#if canImport(LegadoCore)
import LegadoCore
#endif

struct RssHTMLView: View {
    let content: String
    let articleURL: String
    let source: RssSource
    var body: some View {
        RssHTMLSurface(html: RssDocument.html(content: content, source: source),
                       baseURL: source.loadWithBaseUrl ? URL(string: articleURL) : nil, enableJS: source.enableJs,
                       source: source.scriptSource, articleURL: URL(string: articleURL))
    }
}

private func rssWebView(enableJS: Bool) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = enableJS
    configuration.websiteDataStore = .default()
    return WKWebView(frame: .zero, configuration: configuration)
}

#if os(iOS)
private struct RssHTMLSurface: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let enableJS: Bool
    let source: BookSource
    let articleURL: URL?
    func makeUIView(context: Context) -> WKWebView {
        let view = rssWebView(enableJS: enableJS)
        context.coordinator.task = Task { @MainActor in
            if let url = articleURL { _ = await SourceWebSession.prepare(source: source, url: url, webView: view) }
            guard !Task.isCancelled else { return }
            view.loadHTMLString(html, baseURL: baseURL)
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    func makeCoordinator() -> RSSWebCoordinator { RSSWebCoordinator() }
    static func dismantleUIView(_ view: WKWebView, coordinator: RSSWebCoordinator) { coordinator.task?.cancel(); view.stopLoading() }
}
#else
private struct RssHTMLSurface: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let enableJS: Bool
    let source: BookSource
    let articleURL: URL?
    func makeNSView(context: Context) -> WKWebView {
        let view = rssWebView(enableJS: enableJS)
        context.coordinator.task = Task { @MainActor in
            if let url = articleURL { _ = await SourceWebSession.prepare(source: source, url: url, webView: view) }
            guard !Task.isCancelled else { return }
            view.loadHTMLString(html, baseURL: baseURL)
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    func makeCoordinator() -> RSSWebCoordinator { RSSWebCoordinator() }
    static func dismantleNSView(_ view: WKWebView, coordinator: RSSWebCoordinator) { coordinator.task?.cancel(); view.stopLoading() }
}
#endif

struct RssSingleArticleView: View {
    let source: RssSource
    @State private var article: RssArticle?
    @State private var error: String?
    var body: some View {
        Group {
            if let article = article { RssArticleReaderView(article: article, source: source) }
            else if let error = error { Text(error).padding() }
            else { ProgressView("正在加载…") }
        }
        .task {
            do {
                let categories = try await RssService.shared.loadCategories(source: source)
                try Task.checkCancellation()
                article = RssArticle(origin: source.sourceUrl, title: source.sourceName, link: categories.first?.url ?? source.sourceUrl)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private final class RSSWebCoordinator { var task: Task<Void, Never>? }

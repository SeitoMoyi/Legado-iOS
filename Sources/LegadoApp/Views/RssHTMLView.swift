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
                       source: source, articleURL: URL(string: articleURL))
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
    let source: RssSource
    let articleURL: URL?
    func makeUIView(context: Context) -> WKWebView {
        let view = rssWebView(enableJS: enableJS)
        context.coordinator.load(view, html: html, baseURL: baseURL, enableJS: enableJS, source: source, articleURL: articleURL)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.load(view, html: html, baseURL: baseURL, enableJS: enableJS, source: source, articleURL: articleURL)
    }
    func makeCoordinator() -> RSSWebCoordinator { RSSWebCoordinator() }
    static func dismantleUIView(_ view: WKWebView, coordinator: RSSWebCoordinator) { coordinator.task?.cancel(); view.stopLoading() }
}
#else
private struct RssHTMLSurface: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let enableJS: Bool
    let source: RssSource
    let articleURL: URL?
    func makeNSView(context: Context) -> WKWebView {
        let view = rssWebView(enableJS: enableJS)
        context.coordinator.load(view, html: html, baseURL: baseURL, enableJS: enableJS, source: source, articleURL: articleURL)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(view, html: html, baseURL: baseURL, enableJS: enableJS, source: source, articleURL: articleURL)
    }
    func makeCoordinator() -> RSSWebCoordinator { RSSWebCoordinator() }
    static func dismantleNSView(_ view: WKWebView, coordinator: RSSWebCoordinator) { coordinator.task?.cancel(); view.stopLoading() }
}
#endif


private final class RSSWebCoordinator {
    var task: Task<Void, Never>?
    private var lastHTML: String?
    private var lastSource: RssSource?
    private var lastBaseURL: URL?
    private var lastArticleURL: URL?
    func load(_ view: WKWebView, html: String, baseURL: URL?, enableJS: Bool, source: RssSource, articleURL: URL?) {
        guard lastHTML != html || lastSource != source || lastBaseURL != baseURL || lastArticleURL != articleURL else { return }
        lastHTML = html; lastSource = source; lastBaseURL = baseURL; lastArticleURL = articleURL
        task?.cancel()
        task = Task { @MainActor in
            if let url = articleURL { _ = await SourceWebSession.prepare(source: source.scriptSource, url: url, webView: view, sourceObject: source.scriptObject) }
            guard !Task.isCancelled else { return }
            view.configuration.defaultWebpagePreferences.allowsContentJavaScript = enableJS
            view.loadHTMLString(html, baseURL: baseURL)
        }
    }
}

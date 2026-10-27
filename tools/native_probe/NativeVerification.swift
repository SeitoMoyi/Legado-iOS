import Foundation
import UIKit
import SwiftUI
import WebKit

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
final class NativeVerificationApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var checks: [String] = []
    private var browser: SourceBrowserState?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        Task {
            do { try await run(); finish(error: nil) }
            catch { finish(error: String(describing: error)) }
        }
        return true
    }

    private func expect(_ value: Bool, _ label: String) throws {
        guard value else { throw ProbeFailure(description: label) }
        checks.append(label)
    }
    private func finish(error: String?) {
        let result: [String: Any] = ["passed": error == nil, "checks": checks, "error": error ?? "", "logs": AppLogStore.shared.snapshot().map { $0.message }, "sourceSHA256": Bundle.main.object(forInfoDictionaryKey: "VerificationSourceSHA256") as? String ?? "", "version": Bundle.main.object(forInfoDictionaryKey: "VerificationProductionVersion") as? String ?? ""]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("verification.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        print("NATIVE VERIFICATION \(error == nil ? "PASS" : "FAIL"): \(checks.count) checks; \(error ?? "")")
    }

    private func run() async throws {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "VerificationBaseURL") as? String,
              base.hasPrefix("http://127.0.0.1:") else { throw ProbeFailure(description: "Missing loopback fixture") }
        var source = BookSource(bookSourceUrl: base, bookSourceName: "Native")
        source.loginCheckJs = "java.connect(source.bookSourceUrl+'/replacement')"
        let response = try await NetworkClient.shared.request(parsed: .init(url: URL(string: base + "/gate")!, method: "GET", headers: [:], body: nil))
        let engine = JSEngine(bookSource: source)
        let checked = try engine.checkedResponse(response, requestedURL: URL(string: base + "/gate")!)
        try expect(checked.bodyString == "replacement" && checked.statusCode == 200, "native response replacement and synchronous host HTTP")
        engine.timeout = 0.02
        do { _ = try engine.evalChecked(script: "while(true){}", stage: "probe"); throw ProbeFailure(description: "Loop did not stop") }
        catch is SourceRuntimeError { }
        try expect(engine.didTimeOut, "native QuickJS deadline")
        try expect(engine.evalString("6*7") == "42", "native QuickJS recovery")

        var rss = RssSource(sourceUrl: base, sourceName: "RSS", header: "@js:JSON.stringify({'X-Probe':source.getVariable()})", ruleArticles: "$[*]", ruleTitle: "$.title@js:decorate(result)", ruleLink: "$.link")
        rss.variable = "native"
        rss.extra["jsLib"] = .string("function decorate(v){return source.sourceName+':'+v}")
        let page = try await RssService.shared.fetchArticlePage(source: rss, pageUrl: base + "/feed")
        try expect(page.articles.first?.title == "RSS:Native", "native RSS library, identity, headers and JSON rules")
        let rules = try await RuleLinkService.fetch(base + "/rules")
        if case .bookSources = ScanPayload.detect(rules) { checks.append("native rule-link download preview") }
        else { throw ProbeFailure(description: "Native rule-link detection") }

        let payload = WebDAVService.BackupRestorePayload(books: [], sources: [],
            readStyles: [ReadStyleConfig(name: "Day"), ReadStyleConfig(name: "Night")],
            readerSettings: ReaderBackupSettings(selectedStyle: 1), preservedMembers: ["config.xml": Data([0, 255, 3])])
        let service = WebDAVService()
        let restored = try service.restorePayloadFromZip(data: service.createBackupZip(payload: payload).data)
        try expect(restored.readStyles?.count == 2 && restored.readerSettings?.selectedStyle == 1, "native backup styles and selection")
        try expect(restored.preservedMembers["config.xml"] == Data([0, 255, 3]), "native opaque backup bytes")
        let book = Book(bookUrl: base + "/book", name: "Native Export", author: "Fixture", origin: base)
        let chapter = BookChapter(bookUrl: book.bookUrl, url: base + "/chapter", title: "Chapter", index: 0)
        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")!
        let exported = try BookExportService.exportEPUBReport(book: book, chapters: [chapter], contentProvider: { _ in "Native body\n[image:fixture]" }, imageProvider: { _ in gif })
        let parsed = try EpubParser().parse(epubUrl: exported.url)
        try expect(parsed.book.name == "Native Export" && !parsed.chapters.isEmpty, "native image EPUB export and reimport")

        var htmlSource = RssSource(sourceUrl: base, sourceName: "HTML", header: #"{"Cookie":"probe=1"}"#, style: "body{color:red}", enableJs: false, loadWithBaseUrl: true)
        let html = "<body><p id='probe1'>Native HTML</p><img id='pixel' src='/pixel.gif'><script>window.contentRan=42</script></body>"
        let host = UIHostingController(rootView: RssHTMLView(content: html, articleURL: base + "/article", source: htmlSource))
        window?.rootViewController = host
        host.view.frame = window?.bounds ?? UIScreen.main.bounds
        host.view.layoutIfNeeded()
        let web = try await waitForWeb(host.view)
        try await waitForDOM(web, id: "probe1")
        let color = try await web.evaluateJavaScript("getComputedStyle(document.body).color") as? String
        try expect(color == "rgb(255, 0, 0)", "production RSS WebKit custom CSS")
        let scriptBlocked = try await web.evaluateJavaScript("typeof window.contentRan === 'undefined'") as? Bool
        try expect(scriptBlocked == true, "production RSS content JavaScript disabled")
        let baseURI = try await web.evaluateJavaScript("document.baseURI") as? String
        try expect(baseURI == base + "/article", "production RSS document base URL")
        let imageWidth = try await web.evaluateJavaScript("document.getElementById('pixel').naturalWidth") as? Int
        try expect(imageWidth == 1, "production WebKit cookie bridge and relative image loading")

        let snapshot: UIImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let image = image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? ProbeFailure(description: "WebKit snapshot failed")) }
            }
        }
        if let png = snapshot.pngData() {
            try png.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("rss-render.png"))
        }

        htmlSource.enableJs = true
        htmlSource.style = "body{color:blue}"
        host.rootView = RssHTMLView(content: html.replacingOccurrences(of: "probe1", with: "probe2"), articleURL: base + "/article", source: htmlSource)
        try await waitForDOM(web, id: "probe2")
        let scriptRan = try await web.evaluateJavaScript("window.contentRan") as? Int
        try expect(scriptRan == 42, "production RSS reused view enables JavaScript and reloads")
        let blue = try await web.evaluateJavaScript("getComputedStyle(document.body).color") as? String
        try expect(blue == "rgb(0, 0, 255)", "production RSS reused view updates CSS")
        htmlSource.loadWithBaseUrl = false
        host.rootView = RssHTMLView(content: "<p id='probe3'>No base</p>", articleURL: base + "/article", source: htmlSource)
        try await waitForDOM(web, id: "probe3")
        let noBase = try await web.evaluateJavaScript("document.baseURI") as? String
        try expect(noBase?.hasPrefix("about:") == true, "production RSS base URL opt-out")

        let state = SourceBrowserState(initialURL: base + "/download", source: nil)
        browser = state
        let previous = Set(state.files)
        let controller = UIViewController()
        controller.view.addSubview(state.webView)
        state.webView.frame = window?.bounds ?? UIScreen.main.bounds
        window?.rootViewController = controller
        state.startIfNeeded()
        do { try await waitUntil { state.files.contains(where: { !previous.contains($0) && $0.lastPathComponent == "probe.txt" }) } }
        catch { throw ProbeFailure(description: "Browser download: " + (state.message ?? "no error") + "; active=\(state.activeDownloads); files=\(state.files.map(\.lastPathComponent)); url=\(state.webView.url?.absoluteString ?? "nil")") }
        guard let file = state.files.first(where: { !previous.contains($0) && $0.lastPathComponent == "probe.txt" }) else { throw ProbeFailure(description: "Missing browser download") }
        try expect(state.activeDownloads == 0, "production WebKit download completion")
        let imported = try BookStore().importFile(from: file)
        try expect(imported.name == "probe" && imported.totalChapterNum > 0, "production browser downloaded TXT imports with original filename")
        state.stop()
        await SourceWebSession.clear(sourceURL: base)
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in store.getAllCookies { continuation.resume(returning: $0) } }
        try expect(!cookies.contains(where: { $0.name == "probe" && NetworkClient.cookieDomain($0.domain, matchesHost: "127.0.0.1") }), "production WebKit logout clears scoped cookies")
    }

    private func findWeb(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = findWeb(child) { return web } }
        return nil
    }
    private func waitForWeb(_ view: UIView) async throws -> WKWebView {
        for _ in 0..<150 {
            if let web = findWeb(view) { return web }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProbeFailure(description: "Production RSS WebKit view did not appear")
    }
    private func waitForDOM(_ web: WKWebView, id: String) async throws {
        for _ in 0..<150 {
            let result = try? await web.evaluateJavaScript("document.getElementById('\(id)') !== null && document.readyState === 'complete'")
            if result as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProbeFailure(description: "Production RSS document failed to load: " + id)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProbeFailure(description: "Production browser download timed out")
    }
}

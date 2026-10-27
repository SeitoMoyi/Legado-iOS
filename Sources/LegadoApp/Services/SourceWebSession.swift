import Foundation
import WebKit
#if canImport(LegadoCore)
import LegadoCore
#endif

/// WebKit and URLSession use different cookie stores. Copy only cookies scoped to the
/// requested host; explicit source headers stay on their source host.
enum SourceWebSession {
    @MainActor
    static func clear(sourceURL: String) async {
        guard let host = URL(string: sourceURL)?.host else { return }
        SourceSessionStore.save(header: nil, for: sourceURL)
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where NetworkClient.cookieDomain(cookie.domain, matchesHost: host) { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie]? = await withCheckedContinuation { continuation in
            let gate = WebKitResult<[HTTPCookie]?>(continuation)
            gate.startTimeout(fallback: nil)
            store.getAllCookies { values in Task { @MainActor in gate.resolve(values) } }
        }
        guard let cookies = cookies else { AppLogStore.shared.record("网页", "WebKit 未及时完成 Cookie 读取，请关闭网页后重试退出登录"); return }
        let scoped = cookies.filter { NetworkClient.cookieDomain($0.domain, matchesHost: host) }
        if !(await changeCookies(scoped, store: store, deleting: true)) { AppLogStore.shared.record("网页", "未及时确认 Cookie 清理结果，请关闭网页后重试退出登录") }

    }

    @MainActor
    static func prepare(source: BookSource?, url: URL, webView: WKWebView, sourceObject: [String: Any]? = nil) async -> [String: String] {
        var headers: [String: String] = [:]
        if let source = source, URL(string: source.bookSourceUrl)?.host?.lowercased() == url.host?.lowercased(),
           let raw = await SourceLoginService.headers(source: source, sourceObject: sourceObject), let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) { headers = decoded }
        guard !Task.isCancelled else { return [:] }
        var cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        if let host = url.host, let raw = headers.first(where: { $0.key.lowercased() == "cookie" })?.value {
            for pair in raw.split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                var properties: [HTTPCookiePropertyKey: Any] = [.domain: host, .path: "/", .name: String(parts[0]).trimmingCharacters(in: .whitespaces), .value: String(parts[1]).trimmingCharacters(in: .whitespaces)]
                if url.scheme == "https" { properties[.secure] = "TRUE" }
                if let cookie = HTTPCookie(properties: properties) { cookies.append(cookie) }
            }
        }
        // A new WebKit process can omit a cookie-store completion until navigation
        // starts. Bound the batch so waiting for that callback cannot prevent navigation.
        let completed = await changeCookies(cookies, store: webView.configuration.websiteDataStore.httpCookieStore)
        if !completed { AppLogStore.shared.record("网页", "Cookie 同步未及时完成，继续打开页面") }
        guard !Task.isCancelled else { return [:] }
        webView.customUserAgent = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value ?? NetworkClient.defaultUserAgent
        return headers
    }
    @MainActor
    private static func changeCookies(_ cookies: [HTTPCookie], store: WKHTTPCookieStore, deleting: Bool = false) async -> Bool {
        guard !cookies.isEmpty else { return true }
        return await withCheckedContinuation { continuation in
            let gate = WebKitResult<Bool>(continuation)
            gate.pending = cookies.count
            gate.startTimeout(fallback: false)
            for cookie in cookies {
                let completion: () -> Void = { Task { @MainActor in
                    gate.pending -= 1
                    if gate.pending == 0 { gate.resolve(true) }
                } }
                if deleting { store.delete(cookie, completionHandler: completion) }
                else { store.setCookie(cookie, completionHandler: completion) }
            }
        }
    }

}

@MainActor
private final class WebKitResult<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var timeout: Task<Void, Never>?
    var pending = 0
    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }
    func startTimeout(fallback: Value) {
        timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            resolve(fallback)
        }
    }
    func resolve(_ value: Value) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        continuation.resume(returning: value)
    }
}

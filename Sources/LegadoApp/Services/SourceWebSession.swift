import Foundation
import WebKit
#if canImport(LegadoCore)
import LegadoCore
#endif

/// WebKit and URLSession use different cookie stores. Copy only cookies scoped to the
/// requested host; explicit source headers stay on their source host.
enum SourceWebSession {
    @MainActor
    static func prepare(source: BookSource?, url: URL, webView: WKWebView) async -> [String: String] {
        var headers: [String: String] = [:]
        if let source = source, URL(string: source.bookSourceUrl)?.host?.lowercased() == url.host?.lowercased(),
           let raw = await SourceLoginService.headers(source: source), let data = raw.data(using: .utf8),
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
        for cookie in cookies {
            guard !Task.isCancelled else { return [:] }
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
            }
        }
        webView.customUserAgent = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value ?? NetworkClient.defaultUserAgent
        return headers
    }
}

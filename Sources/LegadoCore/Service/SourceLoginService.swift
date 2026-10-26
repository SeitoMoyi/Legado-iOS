import Foundation

public struct SourceLoginRow: Codable, Equatable, Identifiable {
    public var id: String { name + "|" + type }
    public var name: String = ""
    public var type: String = "text"
    public var action: String?
    public static func parse(_ json: String?) -> [SourceLoginRow] {
        guard let data = json?.data(using: .utf8),
              let rows = TolerantJSON.decodeList(Self.self, from: data, fallback: Self()) else { return [] }
        return rows.filter { !$0.name.isEmpty && ["text", "password", "button"].contains($0.type) }
    }
    public init(name: String = "", type: String = "text", action: String? = nil) {
        self.name = name; self.type = type; self.action = action
    }
}

public struct SourceLoginResult {
    public var header: String?
    public var info: String
    public var message: String?
}

public enum SourceLoginService {
    public static func headers(source: BookSource) async -> String? {
        guard !Task.isCancelled else { return nil }
        return JSEngine.resolvedSourceHeader(source)
    }
    /// Async non-actor entry keeps scripts and synchronous host requests off the UI actor.
    public static func execute(source: BookSource, credentials: [String: String], action: String? = nil) async throws -> SourceLoginResult {
        try Task.checkCancellation()
        guard let raw = source.loginUrl, !raw.isEmpty else { throw SourceRuntimeError.bridge("该源未配置登录脚本") }
        var candidate = source
        let info = String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self)
        candidate.loginInfo = info
        let engine = JSEngine(bookSource: candidate)
        try engine.checkReady()
        var header: String?
        engine.onLoginHeaderUpdated = { header = $0 }
        _ = try engine.evalChecked(script: JSEngine.extractJSScript(from: raw) ?? raw, stage: "loginUrl")
        let value: Any?
        if let action = action {
            value = try engine.evalChecked(script: JSEngine.extractJSScript(from: action) ?? action, result: credentials, stage: "loginUi.action")
        } else {
            value = try engine.evalChecked(script: "if (typeof login === 'function') login();", stage: "login")
            guard let saved = header, !saved.isEmpty else { throw SourceRuntimeError.bridge("登录未返回有效凭据，请检查账号密码") }
        }
        try Task.checkCancellation()
        return SourceLoginResult(header: header, info: info, message: value.map(JSEngine.stringValue))
    }
}

extension RssSource {
    /// Reuse BaseSource bridges with RSS identity and metadata, without importing RSS into
    /// the bookshelf's source list.
    public var scriptSource: BookSource {
        var source = BookSource(bookSourceUrl: sourceUrl, bookSourceName: sourceName)
        source.header = header; source.loginUrl = loginUrl; source.loginUi = loginUi
        source.variable = variable; source.loginHeader = loginHeader
        source.extra = extra
        source.extra["sourceUrl"] = .string(sourceUrl)
        source.extra["sourceName"] = .string(sourceName)
        if case let .string(value)? = extra["jsLib"] { source.jsLib = value }
        if case let .string(value)? = extra["loginCheckJs"] { source.loginCheckJs = value }
        if case let .string(value)? = extra["loginInfo"] { source.loginInfo = value }
        return source
    }
}

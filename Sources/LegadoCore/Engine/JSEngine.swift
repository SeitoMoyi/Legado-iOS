import Foundation
import SwiftSoup
import JavaScriptCore

@objc public protocol JavaShimProtocol: JSExport {
    func ajax(_ url: String) -> String
    func connect(_ url: String) -> JSValue
    func connect(_ url: String, _ header: String) -> JSValue
    func post(_ url: String, _ body: String, _ header: JSValue) -> JSValue
    func get(_ key: String) -> String?
    func put(_ key: String, _ value: String) -> String
    func md5Encode(_ str: String) -> String
    func base64Encode(_ str: String) -> String
    func base64Decode(_ str: String) -> String
    func timeFormat(_ timestamp: JSValue) -> String
    func getString(_ path: String) -> String
    func refreshTocUrl()
    func reGetBook()
}

@objc public class JavaShim: NSObject, JavaShimProtocol {
    private var kvStore: [String: String] = [:]
    private let lock = NSLock()
    private weak var jsContext: JSContext?
    private let baseURL: String?
    /// Resolves the owning source's headers (loginHeader → header, JS-evaluated).
    /// `java.ajax(url)` without them cannot reach Cookie-gated APIs (Android parity).
    public var defaultHeaderProvider: (() -> String?)?
    var refreshTocAction: (() throws -> Void)?
    var reGetBookAction: (() throws -> Void)?
    var variableReader: ((String) -> String?)?
    var variableWriter: ((String, String) -> Void)?

    public func refreshTocUrl() { performPreUpdateAction(refreshTocAction) }
    public func reGetBook() { performPreUpdateAction(reGetBookAction) }

    private func performPreUpdateAction(_ action: (() throws -> Void)?) {
        guard let context = jsContext else { return }
        do {
            guard let action = action else {
                throw SourceRuntimeError.bridge("只能在 preUpdateJs 中调用此方法")
            }
            try action()
        } catch {
            context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
        }
    }

    public init(context: JSContext?, baseURL: String? = nil) {
        self.jsContext = context
        self.baseURL = baseURL
        super.init()
    }

    public func ajax(_ url: String) -> String {
        guard let parsed = NetworkClient.parseLegadoUrl(url, defaultHeader: defaultHeaderProvider?(), baseUrl: baseURL) else { return "" }
        let resp = NetworkClient.shared.requestSync(parsed: parsed)
        return resp?.bodyString ?? ""
    }

    public func connect(_ url: String) -> JSValue {
        return connect(url, defaultHeaderProvider?() ?? "")
    }

    public func connect(_ url: String, _ header: String) -> JSValue {
        guard let ctx = jsContext else {
            return JSValue(undefinedIn: JSContext())
        }
        guard let parsed = NetworkClient.parseLegadoUrl(url, defaultHeader: header, baseUrl: baseURL) else {
            return JSValue(nullIn: ctx)
        }
        return responseValue(NetworkClient.shared.requestSync(parsed: parsed), url: parsed.url.absoluteString, context: ctx)
    }

    public func post(_ url: String, _ body: String, _ header: JSValue) -> JSValue {
        guard let ctx = jsContext else {
            return JSValue(undefinedIn: JSContext())
        }

        guard let base = NetworkClient.parseLegadoUrl(url, defaultHeader: defaultHeaderProvider?(), baseUrl: baseURL) else {
            return JSValue(nullIn: ctx)
        }
        var headerDict = base.headers
        if header.isObject || header.isString {
            if let dict = header.toDictionary() as? [String: Any] {
                for (k, v) in dict {
                    NetworkClient.mergeHeaders([k: "\(v)"], into: &headerDict)
                }
            } else if let str = header.toString(), let data = str.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    NetworkClient.mergeHeaders([k: "\(v)"], into: &headerDict)
                }
            }
        }

        if !headerDict.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headerDict["Content-Type"] = "application/json"
        }

        let parsed = NetworkClient.ParsedRequest(url: base.url, method: "POST", headers: headerDict, body: body.data(using: .utf8))
        return responseValue(NetworkClient.shared.requestSync(parsed: parsed), url: base.url.absoluteString, context: ctx)
    }

    private func responseValue(_ response: NetworkResponse?, url: String, context: JSContext) -> JSValue {
        let body = response?.bodyString ?? ""
        let code = response?.statusCode ?? 0
        let result = JSValue(newObjectIn: context)
        let bodyBlock: @convention(block) () -> String = { body }
        let codeBlock: @convention(block) () -> Int = { code }
        let urlBlock: @convention(block) () -> String = { url }
        result?.setValue(bodyBlock, forProperty: "body")
        result?.setValue(codeBlock, forProperty: "statusCode")
        result?.setValue(urlBlock, forProperty: "url")
        result?.setValue(body, forProperty: "text")
        return result ?? JSValue(nullIn: context)
    }

    public func get(_ key: String) -> String? {
        // With a book context its variable map is authoritative, including deletion and
        // empty values. Falling back to kvStore could resurrect an earlier java.put value.
        if let reader = variableReader { return reader(key) ?? "" }
        lock.lock()
        defer { lock.unlock() }
        return kvStore[key]
    }

    public func put(_ key: String, _ value: String) -> String {
        lock.lock()
        kvStore[key] = value
        lock.unlock()
        variableWriter?(key, value)
        return value
    }

    public func md5Encode(_ str: String) -> String {
        return CryptoUtils.md5(str)
    }

    public func base64Encode(_ str: String) -> String {
        return CryptoUtils.base64Encode(str)
    }

    public func base64Decode(_ str: String) -> String {
        return CryptoUtils.base64Decode(str)
    }

    public func timeFormat(_ timestamp: JSValue) -> String {
        var num = timestamp.toNumber()?.doubleValue ?? 0
        if num == 0, let str = timestamp.toString(), let d = Double(str) {
            num = d
        }
        guard num > 0 else { return "" }
        if num > 10_000_000_000 {
            num /= 1000
        }
        let date = Date(timeIntervalSince1970: num)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public func getString(_ path: String) -> String {
        guard let ctx = jsContext, let resVal = ctx.objectForKeyedSubscript("result" as NSString) else {
            return ""
        }
        if resVal.isObject {
            let cleanKey = path.replacingOccurrences(of: "$.", with: "").replacingOccurrences(of: "$", with: "")
            if let prop = resVal.forProperty(cleanKey), !prop.isUndefined && !prop.isNull {
                return prop.toString() ?? ""
            }
            if let dict = resVal.toDictionary() {
                if let evaluated = JSONPath.evaluate(path: path, json: dict) {
                    return "\(evaluated)"
                }
            }
        }
        let jsonStr = resVal.toString() ?? ""
        if let data = jsonStr.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: []),
           let evaluated = JSONPath.evaluate(path: path, json: obj) {
            return "\(evaluated)"
        }
        return ""
    }
}

/// Minimal surface for `resolvedSourceHeader` — both `BookSource` and `RssSource` ship a
/// static `header` rule plus a login-captured `loginHeader`.
public protocol HeaderRuleProviding {
    var bookSourceUrl: String { get }
    var header: String? { get }
    var loginHeader: String? { get }
}

extension BookSource: HeaderRuleProviding {}
extension RssSource: HeaderRuleProviding {
    public var bookSourceUrl: String { sourceUrl }
    /// RSS 源暂未采集登录头（Android RssSource 同样没有 loginHeader 字段）。
    public var loginHeader: String? { nil }
}

public class JSEngine {
    public let context: JSContext
    private let javaShim: JavaShim
    private var isResolvingHeader = false
    public private(set) var initializationError: Error?
    public private(set) var lastScriptError: String?
    private var readBook: (() -> Book)?
    private var replaceBook: ((Book) -> Void)?
    public var onLoginHeaderUpdated: ((String) -> Void)?
    public var onBookVariableUpdated: ((String?) -> Void)?

    private static let variableLock = NSLock()
    private static var bookVariableCache: [String: String] = [:]
    private static var sourceVariableCache: [String: String] = [:]

    public init(bookSource: BookSource? = nil, book: Book? = nil, baseUrl: String? = nil) {
        self.context = JSContext()
        self.javaShim = JavaShim(context: context, baseURL: baseUrl ?? bookSource?.bookSourceUrl)

        setupEnvironment(bookSource: bookSource, book: book, baseUrl: baseUrl)
        let legacyLibrary: String?
        if case let .string(value)? = bookSource?.extra["jsLib"] { legacyLibrary = value } else { legacyLibrary = nil }
        if let library = bookSource?.jsLib ?? legacyLibrary, !library.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                for script in try SourceLibraryStore.shared.scripts(for: library) {
                    _ = try evalChecked(script: Self.extractJSScript(from: script) ?? script, stage: "jsLib")
                }
            } catch { initializationError = error }
        }
    }

    /// Splits a rule into its non-JS prefix (may be empty) and the `<js>…</js>` / `@js:`
    /// script body (`nil` when the rule carries no script). RuleAnalyzer's JS sites and the
    /// header/URL evaluators all shared this split copy-pasted.
    public static func splitJSRule(_ rule: String) -> (prefix: String, script: String?) {
        if let open = rule.range(of: "<js>"), let close = rule.range(of: "</js>"), open.upperBound <= close.lowerBound {
            let prefix = String(rule[..<open.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (prefix, String(rule[open.upperBound..<close.lowerBound]))
        }
        if rule.hasPrefix("@js:") {
            return ("", String(rule.dropFirst(4)))
        }
        return (rule, nil)
    }

    /// Extracts the script body from a Legado rule that wraps it in `<js>…</js>` or prefixes it
    /// with `@js:`; `nil` when the rule carries no script.
    public static func extractJSScript(from rule: String) -> String? {
        splitJSRule(rule).script
    }

    /// Android `BaseSource.getHeaderMap(hasLoginHeader: true)`: evaluates the source's `header`
    /// rule (`<js>` / `@js:` supported), then overlays `loginHeader` on top — a MERGE, not the
    /// `loginHeader ?? header` replacement. Proxies such as book.xkvi.top gate all API traffic
    /// on the header-shipped `Cookie` while authentication rides `Authorization: Bearer`, so
    /// replacing the header at login breaks every authed request with 502.
    /// - Parameters:
    ///   - engine: reuse the caller's engine when one exists; a fresh one is created for the
    ///     evaluation otherwise.
    ///   - loginHeaderOverride: session-captured login header (putLoginHeader) taking priority
    ///     over the persisted `source.loginHeader`.
    public static func resolvedSourceHeader(_ source: some HeaderRuleProviding,
                                            engine: JSEngine? = nil,
                                            loginHeaderOverride: String? = nil) -> String? {
        var merged: [String: String] = [:]
        for raw in [source.header, loginHeaderOverride ?? source.loginHeader] {
            guard var json = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !json.isEmpty else { continue }
            if let script = extractJSScript(from: json) {
                let evalEngine = engine ?? JSEngine(bookSource: source as? BookSource, baseUrl: source.bookSourceUrl)
                // Header scripts may themselves call java.ajax. Do not recursively re-evaluate
                // that same header while preparing the nested request.
                guard !evalEngine.isResolvingHeader else { continue }
                evalEngine.isResolvingHeader = true
                defer { evalEngine.isResolvingHeader = false }
                guard let evaluated = evalEngine.context.evaluateScript(script)?.toString(),
                      !evaluated.isEmpty, evaluated != "undefined", evaluated != "null" else { continue }
                json = evaluated
            }
            if let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in dict {
                    NetworkClient.mergeHeaders([key: "\(value)"], into: &merged)
                }
            } else if json.contains(":") {
                for line in json.components(separatedBy: .newlines) {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        NetworkClient.mergeHeaders([parts[0].trimmingCharacters(in: .whitespaces): parts[1].trimmingCharacters(in: .whitespaces)], into: &merged)
                    }
                }
            }
        }
        guard !merged.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: merged),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func setupEnvironment(bookSource: BookSource?, book: Book?, baseUrl: String?) {
        // Exception handler
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastScriptError = exception?.toString() ?? "Unknown JavaScript error"
            #if DEBUG
            print("[JSEngine Error] \(exception?.toString() ?? "unknown error")")
            #endif
        }

        // Expose java shim
        context.setObject(javaShim, forKeyedSubscript: "java" as NSString)

        // Expose source object
        let sourceObj = JSValue(newObjectIn: context)
        // Android `getLoginHeader()` reads only the login-captured header
        // (`CacheManager.get("loginHeader_<key>")`) — the source's static `header` field must
        // NOT satisfy it, or `<js>` scripts that branch on 登录状态 (e.g. xkvi exploreUrl's
        // `level=${token ? 0 : 1}`) take the logged-in path with an invalid token and every
        // category/browse request 401/502s.
        var loginHeader: String? = bookSource?.loginHeader
        var loginInfoStr: String? = bookSource?.loginInfo
        let sourceKey = bookSource?.bookSourceUrl ?? ""
        var variableStr: String? = bookSource?.variable ?? {
            guard !sourceKey.isEmpty else { return nil }
            Self.variableLock.lock()
            defer { Self.variableLock.unlock() }
            return Self.sourceVariableCache[sourceKey] ?? UserDefaults.standard.string(forKey: "legado_source_var_\(sourceKey)")
        }()

        // `java.ajax` / `java.connect` must carry the source's headers (Android builds
        // `AnalyzeUrl(url, source = source)`): loginHeader first, then the static `header`,
        // JS-evaluated so `<js>` Cookie headers actually ship. Without this, scripts that
        // probe user endpoints inside exploreUrl (`java.ajax("/api/user/favored")`) hit the
        // proxy without a Cookie and surface 502 as 未知错误.
        javaShim.defaultHeaderProvider = { [weak self] in
            guard let self, let source = bookSource else { return nil }
            return JSEngine.resolvedSourceHeader(source, engine: self, loginHeaderOverride: loginHeader)
        }

        let getLoginHeaderBlock: @convention(block) () -> String? = { loginHeader }
        let putLoginHeaderBlock: @convention(block) (String) -> Void = { [weak self] newH in
            loginHeader = newH
            self?.onLoginHeaderUpdated?(newH)
        }
        let getLoginInfoBlock: @convention(block) () -> String? = { loginInfoStr }
        let putLoginInfoBlock: @convention(block) (String) -> Void = { newInfo in loginInfoStr = newInfo }
        let getVariableBlock: @convention(block) () -> String = { variableStr ?? "" }
        let setVariableBlock: @convention(block) (String) -> Void = { newV in
            variableStr = newV
            if !sourceKey.isEmpty {
                Self.variableLock.lock()
                Self.sourceVariableCache[sourceKey] = newV
                Self.variableLock.unlock()
                UserDefaults.standard.set(newV, forKey: "legado_source_var_\(sourceKey)")
            }
        }
        let getLoginInfoMapBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let ctx = self?.context else { return JSValue(nullIn: JSContext()) }
            let mapObj = JSValue(newObjectIn: ctx)
            var values: [String: String] = [:]
            if let info = loginInfoStr, let data = info.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    mapObj?.setValue(v, forProperty: k)
                    values[k] = "\(v)"
                }
            }
            let getBlock: @convention(block) (String) -> String = { key in
                return values[key] ?? ""
            }
            mapObj?.setValue(getBlock, forProperty: "get")
            return mapObj ?? JSValue(newObjectIn: ctx)
        }

        sourceObj?.setValue(getLoginHeaderBlock, forProperty: "getLoginHeader")
        sourceObj?.setValue(putLoginHeaderBlock, forProperty: "putLoginHeader")
        sourceObj?.setValue(getLoginInfoBlock, forProperty: "getLoginInfo")
        sourceObj?.setValue(putLoginInfoBlock, forProperty: "putLoginInfo")
        sourceObj?.setValue(getLoginInfoMapBlock, forProperty: "getLoginInfoMap")
        sourceObj?.setValue(getVariableBlock, forProperty: "getVariable")
        sourceObj?.setValue(setVariableBlock, forProperty: "setVariable")
        sourceObj?.setValue(bookSource?.loginUrl ?? "", forProperty: "loginUrl")
        sourceObj?.setValue(bookSource?.bookSourceUrl ?? "", forProperty: "bookSourceUrl")
        sourceObj?.setValue(bookSource?.bookSourceName ?? "", forProperty: "bookSourceName")

        context.setObject(sourceObj, forKeyedSubscript: "source" as NSString)

        // Expose book object with persistent variable map
        let bookObj = JSValue(newObjectIn: context)
        let bookKey = book?.bookUrl ?? baseUrl ?? sourceKey
        var currentBook = book ?? Book(bookUrl: bookKey, name: "", author: "", origin: sourceKey)
        if currentBook.variable == nil, !bookKey.isEmpty {
            Self.variableLock.lock()
            let cached = Self.bookVariableCache[bookKey] ?? UserDefaults.standard.string(forKey: "legado_book_var_\(bookKey)")
            Self.variableLock.unlock()
            currentBook.variable = cached
        }

        let persistBookVar: (String?) -> Void = { [weak self] updated in
            if !bookKey.isEmpty {
                Self.variableLock.lock()
                Self.bookVariableCache[bookKey] = updated
                Self.variableLock.unlock()
                if let updated = updated {
                    UserDefaults.standard.set(updated, forKey: "legado_book_var_\(bookKey)")
                } else {
                    UserDefaults.standard.removeObject(forKey: "legado_book_var_\(bookKey)")
                }
            }
            self?.onBookVariableUpdated?(updated)
        }

        let getBookVarBlock: @convention(block) (JSValue) -> String = { keyVal in
            let key: String? = (keyVal.isUndefined || keyVal.isNull) ? nil : keyVal.toString()
            return currentBook.getVariable(key)
        }
        let putBookVarBlock: @convention(block) (String, JSValue) -> Void = { key, val in
            let strVal: String? = (val.isUndefined || val.isNull) ? nil : val.toString()
            currentBook.putVariable(key: key, value: strVal)
            persistBookVar(currentBook.variable)
        }
        let setBookVarBlock: @convention(block) (JSValue, JSValue) -> Void = { first, second in
            if second.isUndefined {
                let v: String? = (first.isUndefined || first.isNull) ? nil : first.toString()
                currentBook.putVariable(key: nil, value: v)
            } else {
                let k = first.toString() ?? ""
                let v: String? = second.isNull ? nil : second.toString()
                currentBook.putVariable(key: k, value: v)
            }
            persistBookVar(currentBook.variable)
        }

        bookObj?.setValue(getBookVarBlock, forProperty: "getVariable")
        bookObj?.setValue(putBookVarBlock, forProperty: "putVariable")
        bookObj?.setValue(setBookVarBlock, forProperty: "setVariable")
        if book != nil {
            javaShim.variableReader = { key in
                key == "bookName" ? currentBook.name : currentBook.getVariable(key)
            }
            javaShim.variableWriter = { key, value in
                currentBook.putVariable(key: key, value: value)
                persistBookVar(currentBook.variable)
            }
        }
        bookObj?.setValue(currentBook.name, forProperty: "name")
        bookObj?.setValue(currentBook.author, forProperty: "author")
        bookObj?.setValue(currentBook.bookUrl, forProperty: "bookUrl")
        bookObj?.setValue(currentBook.tocUrl, forProperty: "tocUrl")
        bookObj?.setValue(bookSource?.bookSourceUrl ?? currentBook.origin, forProperty: "origin")
        readBook = {
            var updated = currentBook
            updated.name = bookObj?.forProperty("name")?.toString() ?? updated.name
            updated.author = bookObj?.forProperty("author")?.toString() ?? updated.author
            updated.bookUrl = bookObj?.forProperty("bookUrl")?.toString() ?? updated.bookUrl
            updated.tocUrl = bookObj?.forProperty("tocUrl")?.toString() ?? updated.tocUrl
            return updated
        }
        replaceBook = { updated in
            currentBook = updated
            bookObj?.setValue(updated.name, forProperty: "name")
            bookObj?.setValue(updated.author, forProperty: "author")
            bookObj?.setValue(updated.bookUrl, forProperty: "bookUrl")
            bookObj?.setValue(updated.tocUrl, forProperty: "tocUrl")
        }
        context.setObject(bookObj, forKeyedSubscript: "book" as NSString)
        if let baseUrl = baseUrl {
            context.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        }

        // Compatibility polyfills
        context.evaluateScript("""
        var console = {
            log: function(msg) { },
            error: function(msg) { }
        };
        function format(str) { return Array.isArray(str) ? str.join('\\n\\n') : (str || ''); }
        function regex(str) { return str || ''; }
        function annotate(text, kanji) { return text || ''; }
        function update(url, token) { }
        """)
    }

    /// Evaluates a JavaScript snippet with optional `result` value
    public func eval(script: String, result: Any? = nil) -> Any? {
        guard initializationError == nil else { return nil }
        lastScriptError = nil
        if let result = result {
            context.setObject(Self.scriptValue(result), forKeyedSubscript: "result" as NSString)
        }
        let val = context.evaluateScript(script)
        if val?.isUndefined == true || val?.isNull == true {
            return nil
        }
        if val?.isString == true {
            return val?.toString()
        }
        if val?.isNumber == true {
            return val?.toNumber()
        }
        if val?.isBoolean == true {
            return val?.toBool()
        }
        if val?.isArray == true {
            return val?.toArray()
        }
        if val?.isObject == true {
            return val?.toDictionary()
        }
        return val?.toObject()
    }

    public func checkReady() throws {
        if let error = initializationError { throw error }
    }

    @discardableResult
    public func evalChecked(script: String, result: Any? = nil, stage: String) throws -> Any? {
        try checkReady()
        let value = eval(script: script, result: result)
        if let message = lastScriptError { throw SourceRuntimeError.script(stage: stage, message: message) }
        return value
    }

    func bookSnapshot() -> Book? { readBook?() }

    func installPreUpdateActions(refresh: @escaping (Book) throws -> Book,
                                 reGet: @escaping (Book) throws -> Book) {
        javaShim.refreshTocAction = { [weak self] in
            guard let self = self, let book = self.readBook?() else { return }
            self.replaceBook?(try refresh(book))
        }
        javaShim.reGetBookAction = { [weak self] in
            guard let self = self, let book = self.readBook?() else { return }
            self.replaceBook?(try reGet(book))
        }
    }

    /// SwiftSoup nodes cannot be bridged directly into JavaScriptCore (copyWithZone crash).
    /// Give scripts HTML text, also when a selector returns a list of nodes.
    private static func scriptValue(_ value: Any) -> Any {
        if let node = value as? Node { return (try? node.outerHtml()) ?? "" }
        if let array = value as? [Any] { return array.map { scriptValue($0) } }
        if let object = value as? [String: Any] { return object.mapValues { scriptValue($0) } }
        return value
    }

    /// Evaluates template strings containing `{{ ... }}`
    public func renderTemplate(_ text: String, variables: [String: Any] = [:]) -> String {
        for (k, v) in variables {
            context.setObject(v, forKeyedSubscript: k as NSString)
        }

        var result = text
        let pattern = "\\{\\{(.*?)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let fullRange = match.range
            let innerRange = match.range(at: 1)
            let expression = nsString.substring(with: innerRange).trimmingCharacters(in: .whitespacesAndNewlines)

            let evaluated = eval(script: expression)
            let replacement = evaluated != nil ? "\(evaluated!)" : ""
            result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
        }

        return result
    }
}

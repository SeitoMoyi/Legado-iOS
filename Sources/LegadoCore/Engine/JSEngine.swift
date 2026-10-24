import Foundation
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
}

@objc public class JavaShim: NSObject, JavaShimProtocol {
    private var kvStore: [String: String] = [:]
    private let lock = NSLock()
    private weak var jsContext: JSContext?
    /// Resolves the owning source's headers (loginHeader → header, JS-evaluated).
    /// `java.ajax(url)` without them cannot reach Cookie-gated APIs (Android parity).
    public var defaultHeaderProvider: (() -> String?)?

    public init(context: JSContext?) {
        self.jsContext = context
        super.init()
    }

    public func ajax(_ url: String) -> String {
        guard let parsed = NetworkClient.parseLegadoUrl(url, defaultHeader: defaultHeaderProvider?()) else { return "" }
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
        guard let parsed = NetworkClient.parseLegadoUrl(url, defaultHeader: header) else {
            return JSValue(nullIn: ctx)
        }
        let resp = NetworkClient.shared.requestSync(parsed: parsed)
        let body = resp?.bodyString ?? ""
        let code = resp?.statusCode ?? 0

        let resultObj = JSValue(newObjectIn: ctx)
        let bodyBlock: @convention(block) () -> String = { body }
        let codeBlock: @convention(block) () -> Int = { code }
        let urlBlock: @convention(block) () -> String = { url }
        resultObj?.setValue(bodyBlock, forProperty: "body")
        resultObj?.setValue(codeBlock, forProperty: "statusCode")
        resultObj?.setValue(urlBlock, forProperty: "url")
        resultObj?.setValue(body, forProperty: "text")
        return resultObj ?? JSValue(nullIn: ctx)
    }

    public func post(_ url: String, _ body: String, _ header: JSValue) -> JSValue {
        guard let ctx = jsContext else {
            return JSValue(undefinedIn: JSContext())
        }

        var headerDict: [String: String] = [:]
        if header.isObject || header.isString {
            if let dict = header.toDictionary() as? [String: Any] {
                for (k, v) in dict {
                    headerDict[k] = "\(v)"
                }
            } else if let str = header.toString(), let data = str.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    headerDict[k] = "\(v)"
                }
            }
        }

        if headerDict["Content-Type"] == nil {
            headerDict["Content-Type"] = "application/json"
        }

        let bodyData = body.data(using: .utf8)
        guard let cleanUrl = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
            return JSValue(nullIn: ctx)
        }

        let parsed = NetworkClient.ParsedRequest(url: cleanUrl, method: "POST", headers: headerDict, body: bodyData)
        let resp = NetworkClient.shared.requestSync(parsed: parsed)
        let respBody = resp?.bodyString ?? ""
        let respCode = resp?.statusCode ?? 0

        let resultObj = JSValue(newObjectIn: ctx)
        let bodyBlock: @convention(block) () -> String = { respBody }
        let codeBlock: @convention(block) () -> Int = { respCode }
        let urlBlock: @convention(block) () -> String = { url }
        resultObj?.setValue(bodyBlock, forProperty: "body")
        resultObj?.setValue(codeBlock, forProperty: "statusCode")
        resultObj?.setValue(urlBlock, forProperty: "url")
        resultObj?.setValue(respBody, forProperty: "text")
        return resultObj ?? JSValue(nullIn: ctx)
    }

    public func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return kvStore[key]
    }

    public func put(_ key: String, _ value: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        kvStore[key] = value
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
    public var onLoginHeaderUpdated: ((String) -> Void)?
    public var onBookVariableUpdated: ((String?) -> Void)?

    private static let variableLock = NSLock()
    private static var bookVariableCache: [String: String] = [:]
    private static var sourceVariableCache: [String: String] = [:]

    public init(bookSource: BookSource? = nil, book: Book? = nil, baseUrl: String? = nil) {
        self.context = JSContext()
        self.javaShim = JavaShim(context: context)

        setupEnvironment(bookSource: bookSource, book: book, baseUrl: baseUrl)
    }

    /// Extracts the script body from a Legado rule that wraps it in `<js>…</js>` or prefixes it
    /// with `@js:`; `nil` when the rule carries no script. The same extraction was copy-pasted
    /// across search-URL rendering, explore categories, header evaluation and the rule engine.
    public static func extractJSScript(from rule: String) -> String? {
        if let start = rule.range(of: "<js>")?.upperBound,
           let end = rule.range(of: "</js>")?.lowerBound, start <= end {
            return String(rule[start..<end])
        }
        if rule.hasPrefix("@js:") {
            return String(rule.dropFirst(4))
        }
        return nil
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
                guard let evaluated = evalEngine.context.evaluateScript(script)?.toString(),
                      !evaluated.isEmpty, evaluated != "undefined", evaluated != "null" else { continue }
                json = evaluated
            }
            if let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in dict {
                    merged[key] = "\(value)"
                }
            } else if json.contains(":") {
                for line in json.components(separatedBy: .newlines) {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        merged[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
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
        context.exceptionHandler = { _, exception in
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
            if let info = loginInfoStr, let data = info.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    mapObj?.setValue(v, forProperty: k)
                }
            }
            let getBlock: @convention(block) (String) -> String = { key in
                return mapObj?.forProperty(key)?.toString() ?? ""
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
        bookObj?.setValue(currentBook.name, forProperty: "name")
        bookObj?.setValue(currentBook.author, forProperty: "author")
        bookObj?.setValue(currentBook.bookUrl, forProperty: "bookUrl")
        bookObj?.setValue(currentBook.tocUrl, forProperty: "tocUrl")
        bookObj?.setValue(bookSource?.bookSourceUrl ?? currentBook.origin, forProperty: "origin")
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
        if let result = result {
            context.setObject(result, forKeyedSubscript: "result" as NSString)
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

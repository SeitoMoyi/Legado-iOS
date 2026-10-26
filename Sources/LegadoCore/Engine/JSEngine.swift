import Foundation
import CoreFoundation
import SwiftSoup
#if canImport(LegadoRuntime)
import LegadoRuntime
#endif

public protocol HeaderRuleProviding {
    var bookSourceUrl: String { get }
    var header: String? { get }
    var loginHeader: String? { get }
}
extension BookSource: HeaderRuleProviding {}
extension RssSource: HeaderRuleProviding {
    public var bookSourceUrl: String { sourceUrl }
    public var loginHeader: String? {
        if case let .string(value)? = extra["loginHeader"] { return value }
        return nil
    }
}

/// Legado's synchronous script surface, backed by a bounded QuickJS context. All Swift
/// host bridges pass JSON values and execute on the same serialized evaluation thread.
public final class JSEngine {
    public private(set) var runtime: QuickJSRuntime?
    public private(set) var initializationError: Error?
    public private(set) var lastScriptError: String?
    public private(set) var lastExecutionError: Error?
    public var onLoginHeaderUpdated: ((String) -> Void)?
    public var onBookVariableUpdated: ((String?) -> Void)?
    public var timeout: TimeInterval = 15
    public var cancellationCheck: () -> Bool
    private var source: BookSource?
    private var currentBook: Book
    private let hasBookContext: Bool
    private var baseUrl: String?
    private var loginHeader: String?
    private var loginInfo: String?
    private var sourceVariable: String?
    private var kvStore: [String: String] = [:]
    private var isResolvingHeader = false
    private var refreshAction: ((Book) throws -> Book)?
    private var reGetAction: ((Book) throws -> Book)?
    private static let variableLock = NSLock()
    private static var bookVariableCache: [String: String] = [:]
    private static var sourceVariableCache: [String: String] = [:]

    public init(bookSource: BookSource? = nil, book: Book? = nil, baseUrl: String? = nil,
                shouldCancel: @escaping () -> Bool = { Task.isCancelled }) {
        self.source = bookSource
        self.baseUrl = baseUrl ?? bookSource?.bookSourceUrl
        self.hasBookContext = book != nil
        self.cancellationCheck = shouldCancel
        self.loginHeader = bookSource.flatMap { SourceSessionStore.header(for: $0.bookSourceUrl) ?? $0.loginHeader }
        self.loginInfo = bookSource?.loginInfo
        let sourceKey = bookSource?.bookSourceUrl ?? ""
        self.currentBook = book ?? Book(bookUrl: baseUrl ?? sourceKey, name: "", author: "", origin: sourceKey)
        Self.variableLock.lock()
        if currentBook.variable == nil, !currentBook.bookUrl.isEmpty {
            currentBook.variable = Self.bookVariableCache[currentBook.bookUrl]
                ?? UserDefaults.standard.string(forKey: "legado_book_var_\(currentBook.bookUrl)")
        }
        self.sourceVariable = bookSource?.variable ?? Self.sourceVariableCache[sourceKey]
            ?? UserDefaults.standard.string(forKey: "legado_source_var_\(sourceKey)")
        Self.variableLock.unlock()
        do {
            let runtime = try QuickJSRuntime(limits: .init(memoryBytes: 64 * 1024 * 1024,
                                                          sourceBytes: 2 * 1024 * 1024, outputBytes: 8 * 1024 * 1024))
            self.runtime = runtime
            runtime.hostCall = { [weak self] action, arguments in
                guard let self = self else { throw CancellationError() }
                return try self.callHost(action, arguments)
            }
            try runtime.setGlobal("book", value: Self.bookBindings(currentBook))
            var sourceBindings: [String: Any] = [:]
            if let source = bookSource, let data = try? JSONEncoder().encode(source),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { sourceBindings = object }
            sourceBindings["bookSourceUrl"] = sourceKey
            try runtime.setGlobal("source", value: sourceBindings)
            if let baseUrl = self.baseUrl { try runtime.setGlobal("baseUrl", value: baseUrl) }
            _ = try runtime.evaluate(Self.environment, timeout: timeout, shouldCancel: shouldCancel)
            let legacy: String?
            if case let .string(value)? = bookSource?.extra["jsLib"] { legacy = value } else { legacy = nil }
            if let library = bookSource?.jsLib ?? legacy {
                for script in try SourceLibraryStore.shared.scripts(for: library, shouldCancel: shouldCancel) {
                    _ = try evalChecked(script: Self.extractJSScript(from: script) ?? script, stage: "jsLib")
                }
            }
        } catch { initializationError = error }
    }

    public func setGlobal(_ value: Any, for name: String) {
        do { try runtime?.setGlobal(name, value: Self.scriptValue(value)) }
        catch { initializationError = error }
    }

    public func eval(script: String, result: Any? = nil) -> Any? {
        lastScriptError = nil
        lastExecutionError = nil
        do {
            try checkReady()
            if let result = result { try runtime?.setGlobal("result", value: Self.scriptValue(result)) }
            guard let json = try runtime?.evaluate(script, timeout: timeout, shouldCancel: cancellationCheck),
                  let data = json.data(using: .utf8) else { return nil }
            let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            lastScriptError = nil
            lastExecutionError = nil
            return value is NSNull ? nil : value
        } catch {
            lastExecutionError = error
            lastScriptError = error.localizedDescription
            return nil
        }
    }

    public var didTimeOut: Bool { (lastExecutionError as? QuickJSRuntimeError) == .timeout }

    public func evalString(_ script: String, result: Any? = nil) -> String? {
        eval(script: script, result: result).map(Self.stringValue)
    }

    public func checkReady() throws {
        if let error = initializationError { throw error }
        guard runtime != nil else { throw SourceRuntimeError.bridge("Script runtime unavailable") }
    }

    /// Android WebBook executes loginCheckJs against the response before extracting rules.
    /// The script can return the original response or java.connect's replacement, once per
    /// fetched page. Runtime and host waits retain the engine's deadline/cancellation budget.
    public func checkedResponse(_ response: NetworkResponse, requestedURL: URL) throws -> NetworkResponse {
        baseUrl = response.url?.absoluteString ?? requestedURL.absoluteString
        setGlobal(baseUrl ?? "", for: "baseUrl")
        guard let script = source?.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty else { return response }
        let previous = onLoginHeaderUpdated
        var captured: String?
        onLoginHeaderUpdated = { value in captured = value; previous?(value) }
        defer { onLoginHeaderUpdated = previous }
        let raw: [String: Any] = ["text": response.bodyString, "code": response.statusCode,
                                  "url": response.url?.absoluteString ?? requestedURL.absoluteString]
        setGlobal(raw, for: "__checkedResponse")
        _ = try evalChecked(script: "result = __response(__checkedResponse)", stage: "loginCheckJs")
        guard let result = try evalChecked(script: Self.extractJSScript(from: script) ?? script, stage: "loginCheckJs") as? [String: Any],
              let text = result["text"] as? String else {
            throw SourceRuntimeError.bridge("loginCheckJs 必须返回响应对象")
        }
        if let key = source?.bookSourceUrl, let header = captured { SourceSessionStore.save(header: header, for: key) }
        let finalURL = (result["url"] as? String).flatMap(URL.init(string:)) ?? response.url ?? requestedURL
        baseUrl = finalURL.absoluteString
        setGlobal(finalURL.absoluteString, for: "baseUrl")
        return NetworkResponse(statusCode: (result["code"] as? NSNumber)?.intValue ?? response.statusCode,
            bodyString: text, data: Data(text.utf8), headers: response.headers,
            url: finalURL)
    }

    @discardableResult
    public func evalChecked(script: String, result: Any? = nil, stage: String) throws -> Any? {
        try checkReady()
        let value = eval(script: script, result: result)
        if let message = lastScriptError { throw SourceRuntimeError.script(stage: stage, message: message) }
        return value
    }

    func bookSnapshot() -> Book? {
        guard let values = eval(script: "book") as? [String: Any] else { return nil }
        var book = currentBook
        book.name = values["name"] as? String ?? book.name
        book.author = values["author"] as? String ?? book.author
        book.bookUrl = values["bookUrl"] as? String ?? book.bookUrl
        book.tocUrl = values["tocUrl"] as? String ?? book.tocUrl
        return book
    }

    func installPreUpdateActions(refresh: @escaping (Book) throws -> Book, reGet: @escaping (Book) throws -> Book) {
        refreshAction = refresh
        reGetAction = reGet
    }

    private func persistBookVariable() {
        let key = currentBook.bookUrl
        guard !key.isEmpty else { return }
        Self.variableLock.lock()
        Self.bookVariableCache[key] = currentBook.variable
        Self.variableLock.unlock()
        UserDefaults.standard.set(currentBook.variable, forKey: "legado_book_var_\(key)")
        onBookVariableUpdated?(currentBook.variable)
    }

    private func callHost(_ action: String, _ args: [Any]) throws -> Any? {
        func string(_ index: Int) -> String { index < args.count ? Self.stringValue(args[index]) : "" }
        func optional(_ index: Int) -> String? { index < args.count && !(args[index] is NSNull) ? Self.stringValue(args[index]) : nil }
        guard !cancellationCheck(), runtime?.shouldStop != true else { throw CancellationError() }
        switch action {
        case "java.get": return hasBookContext ? (string(0) == "bookName" ? (bookSnapshot()?.name ?? currentBook.name) : currentBook.getVariable(string(0))) : kvStore[string(0)]
        case "java.put":
            if hasBookContext { currentBook.putVariable(key: string(0), value: string(1)); persistBookVariable() }
            else { kvStore[string(0)] = string(1) }
            return string(1)
        case "java.md5Encode": return CryptoUtils.md5(string(0))
        case "java.base64Encode": return CryptoUtils.base64Encode(string(0))
        case "java.base64Decode": return CryptoUtils.base64Decode(string(0))
        case "java.timeFormat":
            var value = Double(string(0)) ?? 0
            guard value.isFinite, value > 0 else { return "" }
            if value > 10_000_000_000 { value /= 1000 }
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: Date(timeIntervalSince1970: value))
        case "java.getString":
            guard args.count > 1 else { return "" }
            let value: Any
            if let text = args[1] as? String, let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { value = json }
            else { value = args[1] }
            return JSONPath.evaluate(path: string(0), json: value).map(Self.stringValue) ?? ""
        case "source.getLoginHeader": return loginHeader
        case "source.putLoginHeader": loginHeader = string(0); onLoginHeaderUpdated?(string(0)); return nil
        case "source.getLoginInfo": return loginInfo
        case "source.putLoginInfo": loginInfo = string(0); return nil
        case "source.getVariable": return sourceVariable ?? ""
        case "source.setVariable":
            sourceVariable = string(0)
            let key = source?.bookSourceUrl ?? ""
            if !key.isEmpty {
                Self.variableLock.lock(); Self.sourceVariableCache[key] = string(0); Self.variableLock.unlock()
                UserDefaults.standard.set(string(0), forKey: "legado_source_var_\(key)")
            }
            return nil
        case "book.getVariable": return currentBook.getVariable(optional(0))
        case "book.putVariable": currentBook.putVariable(key: optional(0), value: optional(1)); persistBookVariable(); return nil
        case "java.refreshTocUrl", "java.reGetBook":
            guard let operation = action == "java.refreshTocUrl" ? refreshAction : reGetAction else {
                throw SourceRuntimeError.bridge("只能在 preUpdateJs 中调用此方法")
            }
            let updated = try operation(bookSnapshot() ?? currentBook)
            currentBook = updated
            let data = try JSONSerialization.data(withJSONObject: Self.bookBindings(updated))
            let json = String(decoding: data, as: UTF8.self)
            _ = try evalChecked(script: "Object.assign(book, \(json))", stage: "book")
            return nil
        case "java.ajax", "java.connect", "java.post":
            let header = source.flatMap { Self.resolvedSourceHeader($0, engine: self, loginHeaderOverride: loginHeader) }
            guard let parsed = NetworkClient.parseLegadoUrl(string(0), defaultHeader: header, baseUrl: baseUrl) else { return nil }
            var headers = parsed.headers
            var method = parsed.method
            var body = parsed.body
            if action == "java.connect", let supplied = optional(1), !supplied.isEmpty,
               let data = supplied.data(using: .utf8), let values = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                NetworkClient.mergeHeaders(values, into: &headers)
            }
            if action == "java.post" {
                method = "POST"; body = string(1).data(using: .utf8)
                if args.count > 2 {
                    var values = args[2] as? [String: Any]
                    if values == nil, let data = optional(2)?.data(using: .utf8) { values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
                    for (key, value) in values ?? [:] { NetworkClient.mergeHeaders([key: Self.stringValue(value)], into: &headers) }
                }
                if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                    headers["Content-Type"] = "application/json"
                }
            }
            let request = NetworkClient.ParsedRequest(url: parsed.url, method: method, headers: headers, body: body, charset: parsed.charset, retry: parsed.retry)
            let response = NetworkClient.shared.requestSync(parsed: request, timeout: min(15, runtime?.remainingTime ?? 15),
                                                           shouldCancel: { self.cancellationCheck() || self.runtime?.shouldStop == true })
            guard !cancellationCheck(), runtime?.shouldStop != true else { throw CancellationError() }
            if action == "java.ajax" { return response?.bodyString ?? "" }
            return ["text": response?.bodyString ?? "", "code": response?.statusCode ?? 0, "url": response?.url?.absoluteString ?? request.url.absoluteString]
        default: throw SourceRuntimeError.bridge("Unsupported host call: \(action)")
        }
    }

    private static func bookBindings(_ book: Book) -> [String: Any] {
        ["name": book.name, "author": book.author, "bookUrl": book.bookUrl,
         "tocUrl": book.tocUrl, "origin": book.origin]
    }

    public static func stringValue(_ value: Any) -> String {
        if value is NSNull { return "" }
        if let value = value as? String { return value }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        if let array = value as? [Any] { return array.map(stringValue).joined(separator: ",") }
        if value is [String: Any] { return "[object Object]" }
        return String(describing: value)
    }

    private static let environment = """
    function __response(r) {
      if (!r) return null;
      return {text:r.text, body:function(){return r.text}, statusCode:function(){return r.code}, url:function(){return r.url},
        toJSON:function(){return {text:this.text,code:r.code,url:r.url}}};
    }
    var java = {
      ajax:function(u){return __legadoHost('java.ajax',String(u))},
      connect:function(u,h){return __response(__legadoHost('java.connect',String(u),h == null ? null : (typeof h==='string' ? h : JSON.stringify(h))))},
      post:function(u,b,h){return __response(__legadoHost('java.post',String(u),String(b),h))},
      get:function(k){return __legadoHost('java.get',String(k))},
      put:function(k,v){return __legadoHost('java.put',String(k),String(v))},
      md5Encode:function(v){return __legadoHost('java.md5Encode',String(v))},
      base64Encode:function(v){return __legadoHost('java.base64Encode',String(v))},
      base64Decode:function(v){return __legadoHost('java.base64Decode',String(v))},
      timeFormat:function(v){return __legadoHost('java.timeFormat',v)},
      getString:function(p){return __legadoHost('java.getString',String(p),typeof result==='undefined'?null:result)},
      refreshTocUrl:function(){__legadoHost('java.refreshTocUrl')},
      reGetBook:function(){__legadoHost('java.reGetBook')}
    };
    ['getLoginHeader','putLoginHeader','getLoginInfo','putLoginInfo','getVariable','setVariable'].forEach(function(name){
      source[name]=function(v){return __legadoHost('source.'+name,v)};
    });
    source.getLoginInfoMap=function(){
      var info={}; try {info=JSON.parse(source.getLoginInfo()||'{}')} catch(e){}
      info.get=function(k){return info[k]==null?'':String(info[k])}; return info;
    };
    book.getVariable=function(k){return __legadoHost('book.getVariable',k==null?null:String(k))};
    book.putVariable=function(k,v){__legadoHost('book.putVariable',String(k),v==null?null:String(v))};
    book.setVariable=function(k,v){
      if(arguments.length===1) __legadoHost('book.putVariable',null,k==null?null:String(k));
      else __legadoHost('book.putVariable',String(k),v==null?null:String(v));
    };
    var console={log:function(){},error:function(){}};
    function format(s){return Array.isArray(s)?s.join('\\n\\n'):(s||'')}
    function regex(s){return s||''}
    function annotate(t,k){return t||''}
    function update(u,t){}
    """

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
        for raw in [source.header, loginHeaderOverride ?? SourceSessionStore.header(for: source.bookSourceUrl) ?? source.loginHeader] {
            guard var json = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !json.isEmpty else { continue }
            if let script = extractJSScript(from: json) {
                let evalEngine = engine ?? JSEngine(bookSource: source as? BookSource, baseUrl: source.bookSourceUrl)
                // Header scripts may themselves call java.ajax. Do not recursively re-evaluate
                // that same header while preparing the nested request.
                guard !evalEngine.isResolvingHeader else { continue }
                evalEngine.isResolvingHeader = true
                defer { evalEngine.isResolvingHeader = false }
                guard let evaluated = evalEngine.evalString(script),
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

    /// HTML nodes cross the JSON bridge as source text, matching the existing rule surface.
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
            setGlobal(v, for: k)
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

            let replacement = evalString(expression) ?? ""
            result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
        }

        return result
    }
}

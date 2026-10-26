import Foundation

public struct NetworkResponse {
    public let statusCode: Int
    public let bodyString: String
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, bodyString: String, data: Data, headers: [String: String]) {
        self.statusCode = statusCode
        self.bodyString = bodyString
        self.data = data
        self.headers = headers
    }
}

public class NetworkClient {
    /// Swap this in tests to point every service at a mocked `URLSession`.
    public static var shared = NetworkClient()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public struct ParsedRequest {
        public let url: URL
        public let method: String
        public let headers: [String: String]
        public let body: Data?
        /// `charset` from the URL options. Android uses it for request encoding; we also
        /// pass it to `CharsetDetector` as a decode hint.
        public let charset: String?
        /// `retry` from the URL options, clamped to `maxRetry`.
        public let retry: Int

        public init(url: URL, method: String, headers: [String: String], body: Data?,
                    charset: String? = nil, retry: Int = 0) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
            self.charset = charset
            self.retry = min(max(0, retry), NetworkClient.maxRetry)
        }
    }

    /// Source authors routinely mistype `retry`; cap it so a bad rule cannot hammer a site.
    static let maxRetry = 3

    /// Per-request ceiling. Without it `URLSession.shared` waits 60s, so a dead source turned
    /// "open a book" into a two-minute spinner (TOC call + body call). Android bounds one call
    /// with `HttpHelper.kt:58-61` `callTimeout(60)`; 30s is the same order of magnitude while
    /// keeping the wait survivable. Only the async path needs it — `requestSync` sets its own.
    static let requestTimeout: TimeInterval = 30

    public static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

    /// Header names are case-insensitive; preserve the most recent spelling and value.
    static func mergeHeaders(_ additions: [String: String], into headers: inout [String: String]) {
        for (key, value) in additions {
            for existing in headers.keys.filter({ $0.caseInsensitiveCompare(key) == .orderedSame }) {
                headers.removeValue(forKey: existing)
            }
            headers[key] = value
        }
    }

    /// A cookie domain must end at a DNS label boundary, not just occur inside a host.
    public static func cookieDomain(_ domain: String, matchesHost host: String) -> Bool {
        let domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return !domain.isEmpty && !host.isEmpty && (host == domain || host.hasSuffix("." + domain))
    }

    /// Parses Legado's custom URL syntax:
    /// e.g. "https://domain.com/search,{\"method\":\"POST\",\"body\":{\"key\":\"val\"},\"headers\":{\"X\":\"Y\"}}"
    public static func parseLegadoUrl(_ rawUrl: String, defaultHeader: String? = nil, baseUrl: String? = nil) -> ParsedRequest? {
        var cleanUrl = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        var method = "GET"
        var headers: [String: String] = [
            "User-Agent": defaultUserAgent
        ]
        var bodyData: Data? = nil

        // Merge default headers from book source if present
        if let defaultHeader = defaultHeader?.trimmingCharacters(in: .whitespacesAndNewlines), !defaultHeader.isEmpty {
            if let headerData = defaultHeader.data(using: .utf8),
               let headerDict = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                for (k, v) in headerDict {
                    mergeHeaders([k: "\(v)"], into: &headers)
                }
            } else if defaultHeader.hasPrefix("Cookie:") {
                let cookieVal = String(defaultHeader.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                headers["Cookie"] = cookieVal
            } else if defaultHeader.contains("=") && !defaultHeader.contains("{") {
                headers["Cookie"] = defaultHeader
            } else if defaultHeader.contains(":") {
                let lines = defaultHeader.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let k = parts[0].trimmingCharacters(in: .whitespaces)
                        let v = parts[1].trimmingCharacters(in: .whitespaces)
                        mergeHeaders([k: v], into: &headers)
                    }
                }
            }
        }

        // Check if there is an options JSON appended with a comma
        var declaredCharset: String? = nil
        var retryCount = 0
        if let optionsStart = cleanUrl.range(of: #",\s*\{"#, options: .regularExpression) {
            let commaIndex = optionsStart.lowerBound
            let urlPart = String(cleanUrl[..<commaIndex]).trimmingCharacters(in: .whitespaces)
            let jsonPart = String(cleanUrl[cleanUrl.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
            cleanUrl = urlPart

            if let jsonData = jsonPart.data(using: .utf8),
               let options = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let m = options["method"] as? String {
                    method = m.uppercased()
                }
                if let c = options["charset"] as? String, !c.isEmpty {
                    declaredCharset = c
                }
                if let r = options["retry"] as? NSNumber {
                    retryCount = min(max(0, r.intValue), NetworkClient.maxRetry)
                }
                if let h = options["headers"] as? [String: Any] {
                    for (k, v) in h {
                        mergeHeaders([k: "\(v)"], into: &headers)
                    }
                }
                if let b = options["body"] {
                    if let strBody = b as? String {
                        let encoding = declaredCharset.flatMap(CharsetDetector.encoding(named:)) ?? .utf8
                        guard let encoded = strBody.data(using: encoding) else { return nil }
                        bodyData = encoded
                    } else if let jsonBody = try? JSONSerialization.data(withJSONObject: b) {
                        bodyData = jsonBody
                        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                            headers["Content-Type"] = "application/json; charset=utf-8"
                        }
                    }
                }
            }
        }

        guard !cleanUrl.isEmpty else { return nil }
        let base = baseUrl.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        func resolve(_ raw: String) -> URL? {
            URL(string: raw, relativeTo: base)?.absoluteURL
        }
        let targetUrl = resolve(cleanUrl) ?? cleanUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(resolve)
        guard let url = targetUrl, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return ParsedRequest(url: url, method: method, headers: headers, body: bodyData,
                             charset: declaredCharset, retry: retryCount)
    }

    /// Performs an asynchronous HTTP request, honouring the `retry` option.
    public func request(parsed: ParsedRequest) async throws -> NetworkResponse {
        for attempt in 0...parsed.retry {
            try Task.checkCancellation()
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            do {
                let response = try await performOnce(parsed: parsed)
                // Keep 4xx visible to callers; transient server failures can be retried.
                if response.statusCode >= 500 && attempt < parsed.retry { continue }
                return response
            } catch {
                try Task.checkCancellation()
                if (error as? URLError)?.code == .cancelled || attempt >= parsed.retry { throw error }
            }
        }
        throw URLError(.unknown)
    }

    private func performOnce(parsed: ParsedRequest) async throws -> NetworkResponse {
        var req = URLRequest(url: parsed.url)
        req.httpMethod = parsed.method
        req.httpBody = parsed.body
        req.timeoutInterval = Self.requestTimeout
        for (k, v) in parsed.headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: req)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 200

        var respHeaders: [String: String] = [:]
        if let allHeaderFields = httpResponse?.allHeaderFields {
            for (k, v) in allHeaderFields {
                respHeaders["\(k)"] = "\(v)"
            }
        }

        let bodyStr = CharsetDetector.decode(data, headers: respHeaders, declared: parsed.charset)
        return NetworkResponse(statusCode: statusCode, bodyString: bodyStr, data: data, headers: respHeaders)
    }

    /// Performs a synchronous HTTP request (useful for JS rule evaluation)
    public func requestSync(parsed: ParsedRequest, timeout: TimeInterval = 15.0) -> NetworkResponse? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        var req = URLRequest(url: parsed.url)
        req.httpMethod = parsed.method
        req.httpBody = parsed.body
        req.timeoutInterval = timeout
        for (k, v) in parsed.headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var result: NetworkResponse?
        let resultLock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: req) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil, let data = data else { return }
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 200

            var respHeaders: [String: String] = [:]
            if let allHeaderFields = httpResponse?.allHeaderFields {
                for (k, v) in allHeaderFields {
                    respHeaders["\(k)"] = "\(v)"
                }
            }

            let bodyStr = CharsetDetector.decode(data, headers: respHeaders, declared: parsed.charset)
            resultLock.lock()
            result = NetworkResponse(statusCode: statusCode, bodyString: bodyStr, data: data, headers: respHeaders)
            resultLock.unlock()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            return nil
        }
        resultLock.lock()
        defer { resultLock.unlock() }
        return result
    }
}

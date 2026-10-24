import Foundation
import Network

/// Lightweight Local WiFi HTTP Server for WiFi Book Transfer and LAN APIs.
/// Powered by Apple Network.framework (NWListener), pure Swift, zero C dependencies.
public final class LocalWebServer: ObservableObject {
    public static let shared = LocalWebServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 1122
    @Published public private(set) var localIPAddress: String = "127.0.0.1"

    private var listener: NWListener?
    public var onBookUploaded: ((String, Data) -> Void)?

    public init() {}

    public var serverURLString: String {
        "http://\(localIPAddress):\(port)"
    }

    public func start(port: UInt16 = 1122) {
        guard !isRunning else { return }
        self.port = port
        self.localIPAddress = getWiFiAddress() ?? "127.0.0.1"

        do {
            let parameters = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port) ?? 1122
            listener = try NWListener(using: parameters, on: nwPort)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self?.isRunning = true
                    }
                case .failed, .cancelled:
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                default:
                    break
                }
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            print("[LocalWebServer] Failed to start: \(error)")
            isRunning = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    /// Ceiling for one request. A browser upload is bounded by the file the user picked; without
    /// a cap a client could stream until the app is killed.
    private static let maxRequestBytes = 64 * 1024 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(connection: connection, buffer: Data())
    }

    /// Reads until the declared `Content-Length` has arrived, then routes.
    ///
    /// A single `receive` only returns one TCP segment (at most `maximumLength` bytes), so a
    /// 200 KB book arrived as the first 64 KB plus a truncated body — the file on disk was cut
    /// short and the closing multipart boundary was never seen. Accumulating to the declared
    /// length is what makes uploads of any realistic size correct.
    private func receiveRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] content, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            var buffer = buffer
            if let content = content, !content.isEmpty {
                buffer.append(content)
            }

            if buffer.count > Self.maxRequestBytes {
                self.sendHTMLResponse(connection: connection,
                                      html: "<h3>413 Payload Too Large</h3>", statusCode: 413)
                return
            }

            if let headerEnd = buffer.range(of: Self.headerTerminator) {
                let head = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
                let expected = Self.contentLength(inHead: head)
                let bodyStart = headerEnd.upperBound
                let receivedBody = buffer.distance(from: bodyStart, to: buffer.endIndex)

                if receivedBody >= expected {
                    self.route(connection: connection, head: head,
                               body: Data(buffer[bodyStart..<buffer.index(bodyStart, offsetBy: expected)]))
                    return
                }
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveRequest(connection: connection, buffer: buffer)
        }
    }

    private static func contentLength(inHead head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            return max(0, Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0)
        }
        return 0
    }

    private func route(connection: NWConnection, head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let tokens = requestLine.components(separatedBy: " ")
        guard tokens.count >= 2 else {
            connection.cancel()
            return
        }

        let method = tokens[0]
        let path = tokens[1].components(separatedBy: "?").first ?? tokens[1]

        switch (method, path) {
        case ("GET", let p) where p == "/" || p.hasPrefix("/index"):
            sendHTMLResponse(connection: connection, html: uploadPortalHTML())
        case ("POST", let p) where p.hasPrefix("/upload"):
            handleUploadPost(connection: connection, headers: lines, body: body)
        case ("GET", let p) where p.hasPrefix("/books"):
            sendJSONResponse(connection: connection, json: bookshelfJSON())
        default:
            sendHTMLResponse(connection: connection, html: "<h3>404 Not Found</h3>", statusCode: 404)
        }
    }

    struct MultipartPart {
        let filename: String?
        let data: Data
    }

    /// Splits a `multipart/form-data` body into its parts.
    ///
    /// The previous version handed the raw body to the importer, so every uploaded book began
    /// with `------WebKitFormBoundary…` / `Content-Disposition:` and ended with the closing
    /// boundary — unparseable as TXT or EPUB.
    static func parseMultipart(body: Data, boundary: String) -> [MultipartPart] {
        let delimiter = Data("--\(boundary)".utf8)
        let nextMarker = Data("\r\n--\(boundary)".utf8)
        let partHeaderTerminator = Data("\r\n\r\n".utf8)

        var parts: [MultipartPart] = []
        var cursor = body.startIndex

        while let delimiterRange = body.range(of: delimiter, in: cursor..<body.endIndex) {
            var contentCursor = delimiterRange.upperBound
            // A trailing `--` after the delimiter closes the body.
            if body[contentCursor...].starts(with: Data("--".utf8)) { break }
            if body[contentCursor...].starts(with: Data("\r\n".utf8)) {
                contentCursor = body.index(contentCursor, offsetBy: 2)
            }

            guard let headerEnd = body.range(of: partHeaderTerminator, in: contentCursor..<body.endIndex) else { break }
            let partHead = String(decoding: body[contentCursor..<headerEnd.lowerBound], as: UTF8.self)
            let contentStart = headerEnd.upperBound

            guard let nextRange = body.range(of: nextMarker, in: contentStart..<body.endIndex) else { break }
            let payload = Data(body[contentStart..<nextRange.lowerBound])
            parts.append(MultipartPart(filename: filename(inPartHead: partHead), data: payload))
            cursor = body.index(nextRange.lowerBound, offsetBy: 2)
        }

        return parts
    }

    private static func filename(inPartHead head: String) -> String? {
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-disposition") {
            guard let match = line.range(of: #"filename="([^"]+)""#, options: .regularExpression) else { continue }
            let quoted = String(line[match])
            return quoted.replacingOccurrences(of: "filename=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private static func boundary(inHead headers: [String]) -> String? {
        for line in headers where line.lowercased().hasPrefix("content-type:") {
            guard let range = line.range(of: #"boundary="?([^";]+)"?"#, options: .regularExpression) else { continue }
            let value = String(line[range])
                .replacingOccurrences(of: "boundary=", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func handleUploadPost(connection: NWConnection, headers: [String], body: Data) {
        var filename = "upload_\(Int(Date().timeIntervalSince1970)).txt"
        var payload = body

        if let boundary = Self.boundary(inHead: headers),
           let part = Self.parseMultipart(body: body, boundary: boundary).first(where: { $0.filename != nil }) {
            filename = part.filename ?? filename
            payload = part.data
        }

        // Strip any path components a browser may have attached (old IE sent full paths).
        filename = (filename as NSString).lastPathComponent
        guard !filename.isEmpty, !payload.isEmpty else {
            sendHTMLResponse(connection: connection,
                             html: "<h3>400 Bad Request：未收到文件内容</h3>", statusCode: 400)
            return
        }

        DispatchQueue.main.async {
            self.onBookUploaded?(filename, payload)
        }

        sendHTMLResponse(connection: connection, html: """
        <html><head><meta charset="utf-8"><title>上传成功</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 50px;">
            <h2 style="color: #4CAF50;">✅ 书籍上传成功！</h2>
            <p>已成功放入 iOS 书架：\(filename)</p>
            <a href="/" style="color: #2196F3; text-decoration: none;">继续上传</a>
        </body></html>
        """)
    }

    private func sendHTMLResponse(connection: NWConnection, html: String, statusCode: Int = 200) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        default: statusText = "Error"
        }
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        if let respData = response.data(using: .utf8) {
            connection.send(content: respData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }

    private func sendJSONResponse(connection: NWConnection, json: String) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(json.utf8.count)\r
        Connection: close\r
        \r
        \(json)
        """
        if let respData = response.data(using: .utf8) {
            connection.send(content: respData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }

    private func uploadPortalHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Legado iOS - WiFi 传书</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; text-align: center; background: #f7f7f8; }
                .card { background: white; padding: 30px; border-radius: 16px; box-shadow: 0 4px 16px rgba(0,0,0,0.06); }
                h1 { font-size: 24px; color: #1c1c1e; margin-bottom: 8px; }
                p { color: #8e8e93; font-size: 14px; margin-bottom: 24px; }
                .upload-box { border: 2px dashed #007aff; border-radius: 12px; padding: 40px 20px; background: #f0f7ff; cursor: pointer; }
                input[type=file] { display: none; }
                button { background: #007aff; color: white; border: none; border-radius: 10px; padding: 12px 28px; font-size: 16px; font-weight: 600; cursor: pointer; margin-top: 20px; }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>📚 Legado iOS - WiFi 传书服务</h1>
                <p>将电脑或手机中的 TXT / EPUB 小说直接传至 iOS App 书架</p>
                <form id="form" action="/upload" method="post" enctype="multipart/form-data">
                    <label class="upload-box" id="box" onclick="document.getElementById('f').click()">
                        <div style="font-size: 36px; margin-bottom: 10px;">📄</div>
                        <div style="color: #007aff; font-weight: 500;">点击选择或拖拽 TXT/EPUB 文件</div>
                        <input id="f" type="file" name="file" onchange="showName(this.files[0])">
                    </label>
                    <div id="fn" style="margin-top: 15px; font-size: 14px; color: #333; font-weight: 500;"></div>
                    <button type="submit">立即上传到手机</button>
                </form>
            </div>
            <script>
                // The box advertises drag-and-drop, so it has to accept a drop: assign the
                // dropped file to the real <input> and submit the form normally.
                var box = document.getElementById('box');
                var input = document.getElementById('f');
                function showName(file) {
                    document.getElementById('fn').innerText = file ? file.name : '';
                }
                ['dragenter', 'dragover'].forEach(function (type) {
                    box.addEventListener(type, function (e) {
                        e.preventDefault();
                        box.style.background = '#dcecff';
                    });
                });
                ['dragleave', 'drop'].forEach(function (type) {
                    box.addEventListener(type, function (e) {
                        e.preventDefault();
                        box.style.background = '';
                    });
                });
                box.addEventListener('drop', function (e) {
                    var files = e.dataTransfer && e.dataTransfer.files;
                    if (!files || files.length === 0) { return; }
                    var dt = new DataTransfer();
                    dt.items.add(files[0]);
                    input.files = dt.files;
                    showName(files[0]);
                    document.getElementById('form').submit();
                });
            </script>
        </body>
        </html>
        """
    }

    private func bookshelfJSON() -> String {
        "{\"status\": \"ok\", \"server\": \"Legado iOS LocalWebServer\"}"
    }

    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "pdp_ip0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

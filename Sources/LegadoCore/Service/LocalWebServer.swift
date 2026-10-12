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

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        readRequest(connection: connection)
    }

    private func readRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] content, _, isComplete, _ in
            guard let self = self, let data = content, !data.isEmpty else {
                connection.cancel()
                return
            }

            if let requestString = String(data: data, encoding: .utf8) {
                let lines = requestString.components(separatedBy: "\r\n")
                guard let firstLine = lines.first else {
                    connection.cancel()
                    return
                }

                let tokens = firstLine.components(separatedBy: " ")
                guard tokens.count >= 2 else {
                    connection.cancel()
                    return
                }

                let method = tokens[0]
                let path = tokens[1]

                if method == "GET" && (path == "/" || path.hasPrefix("/index")) {
                    self.sendHTMLResponse(connection: connection, html: self.uploadPortalHTML())
                } else if method == "POST" && path.hasPrefix("/upload") {
                    // Extract uploaded multipart or raw body
                    self.handleUploadPost(connection: connection, requestData: data, headerLines: lines)
                } else if method == "GET" && path.hasPrefix("/books") {
                    self.sendJSONResponse(connection: connection, json: self.bookshelfJSON())
                } else {
                    self.sendHTMLResponse(connection: connection, html: "<h3>404 Not Found</h3>", statusCode: 404)
                }
            } else {
                connection.cancel()
            }
        }
    }

    private func handleUploadPost(connection: NWConnection, requestData: Data, headerLines: [String]) {
        // Find double CRLF delimiter separating HTTP headers from body
        let crlfDelimiter = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let delimiterRange = requestData.range(of: crlfDelimiter) else {
            sendHTMLResponse(connection: connection, html: "400 Bad Request", statusCode: 400)
            return
        }

        let bodyData = requestData.subdata(in: delimiterRange.upperBound..<requestData.count)

        // Find boundary from Content-Type if multipart
        var filename = "upload_\(Int(Date().timeIntervalSince1970)).txt"
        for line in headerLines {
            if line.lowercased().contains("filename=") {
                if let r = line.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
                    let matched = String(line[r])
                    filename = matched.replacingOccurrences(of: "filename=", with: "").replacingOccurrences(of: "\"", with: "")
                }
            }
        }

        DispatchQueue.main.async {
            self.onBookUploaded?(filename, bodyData)
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
        let statusText = (statusCode == 200) ? "OK" : "Not Found"
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
                <form action="/upload" method="post" enctype="multipart/form-data">
                    <label class="upload-box" onclick="document.getElementById('f').click()">
                        <div style="font-size: 36px; margin-bottom: 10px;">📄</div>
                        <div style="color: #007aff; font-weight: 500;">点击选择或拖拽 TXT/EPUB 文件</div>
                        <input id="f" type="file" name="file" onchange="document.getElementById('fn').innerText = this.files[0].name">
                    </label>
                    <div id="fn" style="margin-top: 15px; font-size: 14px; color: #333; font-weight: 500;"></div>
                    <button type="submit">立即上传到手机</button>
                </form>
            </div>
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

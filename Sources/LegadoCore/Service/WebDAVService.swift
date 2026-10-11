import Foundation
import ZIPFoundation

public struct WebDAVConfig: Codable, Equatable {
    public var url: String
    public var username: String
    public var password: String
    public var remotePath: String
    public var lastSyncTime: Date?

    public init(
        url: String = "https://dav.jianguoyun.com/dav/",
        username: String = "",
        password: String = "",
        remotePath: String = "legado",
        lastSyncTime: Date? = nil
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.remotePath = remotePath
        self.lastSyncTime = lastSyncTime
    }

    /// Computes the base URL for syncing (ensures trailing slash and appends remotePath)
    public var directoryURL: URL? {
        var rawUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawUrl.isEmpty else { return nil }
        if !rawUrl.hasPrefix("http://") && !rawUrl.hasPrefix("https://") {
            rawUrl = "https://" + rawUrl
        }
        if !rawUrl.hasSuffix("/") {
            rawUrl += "/"
        }
        let cleanPath = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !cleanPath.isEmpty {
            rawUrl += cleanPath + "/"
        }
        return URL(string: rawUrl)
    }

    public var serverRootURL: URL? {
        var rawUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawUrl.isEmpty else { return nil }
        if !rawUrl.hasPrefix("http://") && !rawUrl.hasPrefix("https://") {
            rawUrl = "https://" + rawUrl
        }
        if !rawUrl.hasSuffix("/") {
            rawUrl += "/"
        }
        return URL(string: rawUrl)
    }

    public var basicAuthHeader: String {
        let credentials = "\(username):\(password)"
        let encoded = credentials.data(using: .utf8)?.base64EncodedString() ?? ""
        return "Basic \(encoded)"
    }
}

public enum WebDAVError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case backupNotFound
    case decodingFailed(String)
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "WebDAV 服务器地址无效，请检查配置"
        case .unauthorized:
            return "WebDAV 认证失败：用户名或密码错误 (401)"
        case .serverError(let code, let msg):
            return "WebDAV 服务器错误 (HTTP \(code)): \(msg)"
        case .backupNotFound:
            return "未在远程目录找到备份文件 (bookshelf.json 或 bookSource.json)"
        case .decodingFailed(let detail):
            return "备份数据解析失败: \(detail)"
        case .custom(let msg):
            return msg
        }
    }
}

public class WebDAVService {
    public static let shared = WebDAVService()
    private let configKey = "legado_webdav_config_v1"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func loadConfig() -> WebDAVConfig {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let config = try? JSONDecoder().decode(WebDAVConfig.self, from: data) {
            return config
        }
        return WebDAVConfig()
    }

    public func saveConfig(_ config: WebDAVConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    /// Creates an authenticated URLRequest with WebDAV headers
    private func makeRequest(url: URL, method: String, config: WebDAVConfig, body: Data? = nil, contentType: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(config.basicAuthHeader, forHTTPHeaderField: "Authorization")
        req.setValue("Legado-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let contentType = contentType {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Tests the connection to the WebDAV server. If the remote directory does not exist, attempts to create it via MKCOL.
    public func testConnection(config: WebDAVConfig) async throws -> String {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        // Try PROPFIND on the directory
        var req = makeRequest(url: dirUrl, method: "PROPFIND", config: config)
        req.setValue("0", forHTTPHeaderField: "Depth")

        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.custom("无法连接到服务器")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebDAVError.unauthorized
        }

        if httpResponse.statusCode == 404 {
            // Directory does not exist yet, try to create it with MKCOL
            try await createDirectoryIfNeeded(config: config)
            return "连接成功，已自动创建远程同步目录：\(config.remotePath)"
        }

        if httpResponse.statusCode == 200 || httpResponse.statusCode == 207 {
            return "连接成功！WebDAV 服务器已就绪。"
        }

        // In case PROPFIND is not supported (HTTP 405), fallback to GET / HEAD
        if httpResponse.statusCode == 405 {
            let getReq = makeRequest(url: dirUrl, method: "GET", config: config)
            let (_, getResponse) = try await session.data(for: getReq)
            if let gRes = getResponse as? HTTPURLResponse {
                if gRes.statusCode == 401 || gRes.statusCode == 403 {
                    throw WebDAVError.unauthorized
                }
                if (200...299).contains(gRes.statusCode) || gRes.statusCode == 301 || gRes.statusCode == 302 {
                    return "连接成功！"
                }
            }
        }

        return "连接成功 (HTTP \(httpResponse.statusCode))"
    }

    /// Creates the directory via MKCOL if it doesn't exist
    public func createDirectoryIfNeeded(config: WebDAVConfig) async throws {
        guard let dirUrl = config.directoryURL else { throw WebDAVError.invalidURL }
        let req = makeRequest(url: dirUrl, method: "MKCOL", config: config)
        let (_, response) = try await session.data(for: req)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            // 201 Created or 405 Method Not Allowed (already exists) are fine
        }
    }

    /// Backs up bookshelf and sources to WebDAV server
    public func backup(books: [Book], sources: [BookSource], config: WebDAVConfig) async throws -> (booksCount: Int, sourcesCount: Int) {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        // Try ensuring directory exists
        try? await createDirectoryIfNeeded(config: config)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        // 1. Upload bookshelf.json
        let booksData = try encoder.encode(books)
        let booksUrl = dirUrl.appendingPathComponent("bookshelf.json")
        let booksReq = makeRequest(url: booksUrl, method: "PUT", config: config, body: booksData, contentType: "application/json; charset=utf-8")
        let (_, booksResponse) = try await session.data(for: booksReq)
        guard let httpBooks = booksResponse as? HTTPURLResponse else {
            throw WebDAVError.custom("上传书架数据无响应")
        }
        if httpBooks.statusCode == 401 || httpBooks.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(httpBooks.statusCode) else {
            throw WebDAVError.serverError(httpBooks.statusCode, "上传书架失败")
        }

        // 2. Upload bookSource.json
        let sourcesData = try encoder.encode(sources)
        let sourcesUrl = dirUrl.appendingPathComponent("bookSource.json")
        let sourcesReq = makeRequest(url: sourcesUrl, method: "PUT", config: config, body: sourcesData, contentType: "application/json; charset=utf-8")
        let (_, sourcesResponse) = try await session.data(for: sourcesReq)
        guard let httpSources = sourcesResponse as? HTTPURLResponse else {
            throw WebDAVError.custom("上传书源数据无响应")
        }
        if httpSources.statusCode == 401 || httpSources.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(httpSources.statusCode) else {
            throw WebDAVError.serverError(httpSources.statusCode, "上传书源失败")
        }

        // Update last sync time
        var updatedConfig = config
        updatedConfig.lastSyncTime = Date()
        saveConfig(updatedConfig)

        return (books.count, sources.count)
    }

    /// Restores bookshelf and sources from WebDAV server (supports both direct JSON files and Android backup*.zip)
    public func restore(config: WebDAVConfig) async throws -> (books: [Book]?, sources: [BookSource]?) {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        var restoredBooks: [Book]? = nil
        var restoredSources: [BookSource]? = nil

        // 1. Try downloading bookshelf.json
        let booksUrl = dirUrl.appendingPathComponent("bookshelf.json")
        let booksReq = makeRequest(url: booksUrl, method: "GET", config: config)
        let (booksData, booksResponse) = try await session.data(for: booksReq)
        if let httpBooks = booksResponse as? HTTPURLResponse {
            if httpBooks.statusCode == 401 || httpBooks.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            if (200...299).contains(httpBooks.statusCode) {
                if let decodedBooks = try? JSONDecoder().decode([Book].self, from: booksData) {
                    restoredBooks = decodedBooks
                }
            }
        }

        // 2. Try downloading bookSource.json
        let sourcesUrl = dirUrl.appendingPathComponent("bookSource.json")
        let sourcesReq = makeRequest(url: sourcesUrl, method: "GET", config: config)
        let (sourcesData, sourcesResponse) = try await session.data(for: sourcesReq)
        if let httpSources = sourcesResponse as? HTTPURLResponse {
            if httpSources.statusCode == 401 || httpSources.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            if (200...299).contains(httpSources.statusCode) {
                if let decodedSources = try? JSONDecoder().decode([BookSource].self, from: sourcesData) {
                    restoredSources = decodedSources
                }
            }
        }

        // 3. Fallback: Check for Android backup*.zip files on remote WebDAV if no JSON found
        if restoredBooks == nil && restoredSources == nil {
            var propReq = makeRequest(url: dirUrl, method: "PROPFIND", config: config)
            propReq.setValue("1", forHTTPHeaderField: "Depth")
            if let (propData, propResp) = try? await session.data(for: propReq),
               let httpProp = propResp as? HTTPURLResponse, (200...299).contains(httpProp.statusCode),
               let propXml = String(data: propData, encoding: .utf8) {
                // Find all backup*.zip occurrences in href
                let pattern = #"href>([^<]+backup[^<]*\.zip)<"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(propXml.startIndex..<propXml.endIndex, in: propXml)
                    let matches = regex.matches(in: propXml, options: [], range: range)
                    var zipUrls: [URL] = []
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: propXml) {
                            let rawPath = String(propXml[r])
                            if let fullUrl = URL(string: rawPath, relativeTo: dirUrl)?.absoluteURL {
                                zipUrls.append(fullUrl)
                            }
                        }
                    }
                    if let latestZipUrl = zipUrls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
                        let zipReq = makeRequest(url: latestZipUrl, method: "GET", config: config)
                        if let (zipData, zipResp) = try? await session.data(for: zipReq),
                           let httpZip = zipResp as? HTTPURLResponse, (200...299).contains(httpZip.statusCode) {
                            let zipResult = try? restoreFromZip(data: zipData)
                            restoredBooks = zipResult?.books
                            restoredSources = zipResult?.sources
                        }
                    }
                }
            }
        }

        if restoredBooks == nil && restoredSources == nil {
            throw WebDAVError.backupNotFound
        }

        // Update last sync time
        var updatedConfig = config
        updatedConfig.lastSyncTime = Date()
        saveConfig(updatedConfig)

        return (restoredBooks, restoredSources)
    }

    // MARK: - Zip Archive Restoration (Android Legado Compatible)

    /// Restores books and sources from a ZIP archive data (e.g. backup*.zip)
    public func restoreFromZip(data: Data) throws -> (books: [Book]?, sources: [BookSource]?) {
        guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw WebDAVError.decodingFailed("无法解析 Zip 压缩包数据")
        }
        return try parseArchive(archive)
    }

    /// Restores books and sources from a local ZIP file URL, and merges adjacent bookProgress if found
    public func restoreFromZip(fileUrl: URL) throws -> (books: [Book]?, sources: [BookSource]?) {
        guard let archive = try? Archive(url: fileUrl, accessMode: .read, pathEncoding: nil) else {
            throw WebDAVError.decodingFailed("无法读取 Zip 备份文件: \(fileUrl.lastPathComponent)")
        }
        var result = try parseArchive(archive)

        // Also check if an adjacent bookProgress directory exists (e.g. in user's Downloads directory)
        let parentDir = fileUrl.deletingLastPathComponent()
        let progressDir = parentDir.appendingPathComponent("bookProgress")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: progressDir.path, isDirectory: &isDir), isDir.boolValue {
            if var books = result.books {
                applyBookProgress(books: &books, fromDirectory: progressDir)
                result.books = books
            }
        }

        return result
    }

    /// Parses bookshelf.json, bookSource.json, and internal bookProgress from a ZIP archive
    public func parseArchive(_ archive: Archive) throws -> (books: [Book]?, sources: [BookSource]?) {
        var restoredBooks: [Book]? = nil
        var restoredSources: [BookSource]? = nil

        // 1. Locate and extract bookshelf.json
        if let entry = archive["bookshelf.json"] ?? archive.first(where: { $0.path.hasSuffix("bookshelf.json") }) {
            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            if let decoded = try? JSONDecoder().decode([Book].self, from: data) {
                restoredBooks = decoded
            }
        }

        // 2. Locate and extract bookSource.json
        if let entry = archive["bookSource.json"] ?? archive.first(where: { $0.path.hasSuffix("bookSource.json") }) {
            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            if let decoded = try? JSONDecoder().decode([BookSource].self, from: data) {
                restoredSources = decoded
            }
        }

        // 3. Extract any internal bookProgress/*.json
        var progressMap: [String: BookProgress] = [:]
        for entry in archive {
            let path = entry.path
            if (path.hasPrefix("bookProgress/") || path.contains("/bookProgress/")) && path.hasSuffix(".json") {
                var pData = Data()
                _ = try? archive.extract(entry) { chunk in
                    pData.append(chunk)
                }
                if let prog = try? JSONDecoder().decode(BookProgress.self, from: pData) {
                    let key = "\(prog.name)_\(prog.author)"
                    progressMap[key] = prog
                }
            }
        }

        // Apply progress updates to books
        if var books = restoredBooks, !progressMap.isEmpty {
            for i in 0..<books.count {
                let key = "\(books[i].name)_\(books[i].author)"
                if let prog = progressMap[key] {
                    if prog.durChapterIndex >= books[i].durChapterIndex {
                        books[i].durChapterIndex = prog.durChapterIndex
                        books[i].durChapterPos = prog.durChapterPos
                        if let title = prog.durChapterTitle, !title.isEmpty {
                            books[i].durChapterTitle = title
                        }
                        if let time = prog.durChapterTime {
                            books[i].durChapterTime = time
                            books[i].lastCheckTime = time
                        }
                    }
                }
            }
            restoredBooks = books
        }

        if restoredBooks == nil && restoredSources == nil {
            throw WebDAVError.backupNotFound
        }

        return (restoredBooks, restoredSources)
    }

    /// Reads an external bookProgress directory and updates reading progress for matching books
    public func applyBookProgress(books: inout [Book], fromDirectory dirUrl: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dirUrl, includingPropertiesForKeys: nil) else {
            return
        }

        var progressMap: [String: BookProgress] = [:]
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let prog = try? JSONDecoder().decode(BookProgress.self, from: data) {
                let key = "\(prog.name)_\(prog.author)"
                progressMap[key] = prog
            }
        }

        guard !progressMap.isEmpty else { return }

        for i in 0..<books.count {
            let key = "\(books[i].name)_\(books[i].author)"
            if let prog = progressMap[key] {
                if prog.durChapterIndex >= books[i].durChapterIndex {
                    books[i].durChapterIndex = prog.durChapterIndex
                    books[i].durChapterPos = prog.durChapterPos
                    if let title = prog.durChapterTitle, !title.isEmpty {
                        books[i].durChapterTitle = title
                    }
                    if let time = prog.durChapterTime {
                        books[i].durChapterTime = time
                        books[i].lastCheckTime = time
                    }
                }
            }
        }
    }
}

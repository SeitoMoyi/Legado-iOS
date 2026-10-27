import Foundation
import ZIPFoundation

#if canImport(UIKit)
import UIKit
#endif

public struct WebDAVConfig: Codable, Equatable {
    public var url: String
    public var username: String
    public var password: String
    public var remotePath: String
    public var deviceName: String
    public var lastSyncTime: Date?

    public static var defaultDeviceName: String {
        #if canImport(UIKit)
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return "iOS"
        #elseif os(macOS)
        if let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Mac"
        #else
        return "Device"
        #endif
    }

    public static func generateBackupFileName(date: Date = Date(), deviceName: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)

        let rawDevice = (deviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDevice = rawDevice
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))

        if !cleanDevice.isEmpty {
            return "backup\(dateStr)-\(cleanDevice).zip"
        } else {
            return "backup\(dateStr).zip"
        }
    }

    public init(
        url: String = WebDAVService.presetJianguoyunURL,
        username: String = "",
        password: String = "",
        remotePath: String = "legado",
        deviceName: String = WebDAVConfig.defaultDeviceName,
        lastSyncTime: Date? = nil
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.remotePath = remotePath
        self.deviceName = deviceName.isEmpty ? Self.defaultDeviceName : deviceName
        self.lastSyncTime = lastSyncTime
    }

    enum CodingKeys: String, CodingKey {
        case url, username, password, remotePath, deviceName, lastSyncTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? WebDAVService.presetJianguoyunURL
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        self.remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath) ?? "legado"
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? Self.defaultDeviceName
        self.lastSyncTime = try container.decodeIfPresent(Date.self, forKey: .lastSyncTime)
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


    public var basicAuthHeader: String {
        let credentials = "\(username):\(password)"
        let encoded = credentials.data(using: .utf8)?.base64EncodedString() ?? ""
        return "Basic \(encoded)"
    }
}

public struct RemoteBackupInfo: Identifiable, Equatable {
    public var id: String { fileName }
    public var fileName: String
    public var url: URL
    public var lastModified: Date?
    public var size: Int64?

    public init(fileName: String, url: URL, lastModified: Date? = nil, size: Int64? = nil) {
        self.fileName = fileName
        self.url = url
        self.lastModified = lastModified
        self.size = size
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
    /// 服务商预设地址（坚果云 / InfiniCLOUD），UI 快捷填入与默认配置共用。
    public static let presetJianguoyunURL = "https://dav.jianguoyun.com/dav/"
    public static let presetInfiniCLOUDURL = "https://teracloud.jp/dav/"

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
    private func makeRequest(url: URL, method: String, config: WebDAVConfig, body: Data? = nil, contentType: String? = nil) throws -> URLRequest {
        guard let base = config.directoryURL, Self.isSameOrigin(url, base) else { throw WebDAVError.invalidURL }
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

    static func isSameOrigin(_ url: URL, _ base: URL) -> Bool {
        func port(_ value: URL) -> Int { value.port ?? (value.scheme?.lowercased() == "https" ? 443 : 80) }
        return url.user == nil && url.password == nil && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.scheme?.lowercased() == base.scheme?.lowercased() && url.host?.lowercased() == base.host?.lowercased()
            && url.host?.isEmpty == false && port(url) == port(base)
    }

    private func send(_ request: URLRequest, config: WebDAVConfig) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: WebDAVRedirectGuard(config: config))
    }

    /// Tests the connection to the WebDAV server. If the remote directory does not exist, attempts to create it via MKCOL.
    public func testConnection(config: WebDAVConfig) async throws -> String {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        // Try PROPFIND on the directory
        var req = try makeRequest(url: dirUrl, method: "PROPFIND", config: config)
        req.setValue("0", forHTTPHeaderField: "Depth")

        let (_, response) = try await self.send(req, config: config)
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
            let getReq = try makeRequest(url: dirUrl, method: "GET", config: config)
            let (_, getResponse) = try await self.send(getReq, config: config)
            if let gRes = getResponse as? HTTPURLResponse {
                if gRes.statusCode == 401 || gRes.statusCode == 403 {
                    throw WebDAVError.unauthorized
                }
                if (200...299).contains(gRes.statusCode) || gRes.statusCode == 301 || gRes.statusCode == 302 {
                    return "连接成功！"
                }
            }
        }

        throw WebDAVError.serverError(httpResponse.statusCode, "连接测试失败")
    }

    /// Creates the directory via MKCOL if it doesn't exist
    public func createDirectoryIfNeeded(config: WebDAVConfig) async throws {
        guard let dirUrl = config.directoryURL else { throw WebDAVError.invalidURL }
        try await createDirectoryIfNeeded(url: dirUrl, config: config)
    }

    public func createDirectoryIfNeeded(url: URL, config: WebDAVConfig) async throws {
        let req = try makeRequest(url: url, method: "MKCOL", config: config)
        let (_, response) = try await self.send(req, config: config)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.custom("创建远程目录无响应")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw WebDAVError.unauthorized }
        guard (200...299).contains(http.statusCode) || http.statusCode == 405 else {
            throw WebDAVError.serverError(http.statusCode, "创建远程目录失败")
        }
    }

    public func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    /// Uploads reading progress for a single book to WebDAV (e.g. legado/bookProgress/name_author.json)
    public func uploadBookProgress(book: Book, config: WebDAVConfig) async throws {
        guard let dirUrl = config.directoryURL else { return }
        let progressDirUrl = dirUrl.appendingPathComponent("bookProgress")
        try? await createDirectoryIfNeeded(url: progressDirUrl, config: config)

        let prog = BookProgress(
            name: book.name,
            author: book.author,
            durChapterIndex: book.durChapterIndex,
            durChapterPos: book.durChapterPos,
            durChapterTime: book.durChapterTime > 0 ? book.durChapterTime : Int64(Date().timeIntervalSince1970 * 1000),
            durChapterTitle: book.durChapterTitle
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let progData = try encoder.encode(prog)
        let cleanFileName = sanitizeFileName("\(book.name)_\(book.author).json")
        let progFileUrl = progressDirUrl.appendingPathComponent(cleanFileName)
        let progReq = try makeRequest(url: progFileUrl, method: "PUT", config: config, body: progData, contentType: "application/json; charset=utf-8")
        let (_, response) = try await self.send(progReq, config: config)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
    }

    /// Downloads reading progress for a single book from WebDAV (e.g. legado/bookProgress/name_author.json)
    public func downloadBookProgress(book: Book, config: WebDAVConfig) async throws -> BookProgress? {
        guard let dirUrl = config.directoryURL else { return nil }
        let progressDirUrl = dirUrl.appendingPathComponent("bookProgress")
        let cleanFileName = sanitizeFileName("\(book.name)_\(book.author).json")
        let progFileUrl = progressDirUrl.appendingPathComponent(cleanFileName)
        let progReq = try makeRequest(url: progFileUrl, method: "GET", config: config)
        let (data, response) = try await self.send(progReq, config: config)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            if http.statusCode == 401 || http.statusCode == 403 { throw WebDAVError.unauthorized }
            guard (200...299).contains(http.statusCode) else { return nil }
        }
        return try? JSONDecoder().decode(BookProgress.self, from: data)
    }

    /// Full payload restored from an Android/iOS Legado backup archive.
    public struct BackupRestorePayload {
        public var books: [Book]?
        public var sources: [BookSource]?
        public var bookmarks: [Bookmark]?
        public var replaceRules: [ReplaceRule]?
        public var searchHistory: [SearchKeyword]?
        public var readConfig: ReadStyleConfig?
        public var ruleSubscriptions: [RuleSub]?
        public var readStyles: [ReadStyleConfig]?
        public var readerSettings: ReaderBackupSettings?
        public var preservedMembers: [String: Data] = [:]
        public var txtTocRules: [TxtTocRule]?
        public var readRecords: [ReadRecord]?
        public var rssSources: [RssSource]?
        public var rssStars: [RssStar]?
        public var bookGroups: [BookGroup]?
        public var dictRules: [DictRule]?
        public var httpTTS: [HttpTTS]?
        public var backupName: String?

        var hasSupportedMembers: Bool {
            books != nil || sources != nil || bookmarks != nil || replaceRules != nil || searchHistory != nil
                || readConfig != nil || txtTocRules != nil || readRecords != nil || rssSources != nil || rssStars != nil
                || bookGroups != nil || dictRules != nil || httpTTS != nil || readStyles != nil
                || readerSettings != nil || ruleSubscriptions != nil || !preservedMembers.isEmpty
        }

        public init(
            books: [Book]? = nil,
            sources: [BookSource]? = nil,
            bookmarks: [Bookmark]? = nil,
            replaceRules: [ReplaceRule]? = nil,
            searchHistory: [SearchKeyword]? = nil,
            readConfig: ReadStyleConfig? = nil,
            ruleSubscriptions: [RuleSub]? = nil,
            readStyles: [ReadStyleConfig]? = nil,
            readerSettings: ReaderBackupSettings? = nil,
            preservedMembers: [String: Data] = [:],
            txtTocRules: [TxtTocRule]? = nil,
            readRecords: [ReadRecord]? = nil,
            rssSources: [RssSource]? = nil,
            rssStars: [RssStar]? = nil,
            bookGroups: [BookGroup]? = nil,
            dictRules: [DictRule]? = nil,
            httpTTS: [HttpTTS]? = nil,
            backupName: String? = nil
        ) {
            self.books = books
            self.sources = sources
            self.bookmarks = bookmarks
            self.replaceRules = replaceRules
            self.searchHistory = searchHistory
            self.readConfig = readConfig
            self.ruleSubscriptions = ruleSubscriptions
            self.readStyles = readStyles
            self.readerSettings = readerSettings
            self.preservedMembers = preservedMembers
            self.txtTocRules = txtTocRules
            self.readRecords = readRecords
            self.rssSources = rssSources
            self.rssStars = rssStars
            self.bookGroups = bookGroups
            self.dictRules = dictRules
            self.httpTTS = httpTTS
            self.backupName = backupName
        }
    }

    /// Builds from a captured snapshot. Missing optional collections mean empty, not another store.
    public func createBackupZip(payload: BackupRestorePayload, deviceName: String = WebDAVConfig.defaultDeviceName, date: Date = Date()) throws -> (data: Data, fileName: String) {
        try createBackupZip(books: payload.books ?? [], sources: payload.sources ?? [],
            bookmarks: payload.bookmarks ?? [], replaceRules: payload.replaceRules ?? [], searchHistory: payload.searchHistory ?? [],
            readConfig: payload.readConfig, ruleSubscriptions: payload.ruleSubscriptions ?? [],
            readStyles: payload.readStyles ?? payload.readConfig.map { [$0] } ?? [],
            readerSettings: payload.readerSettings ?? ReaderBackupSettings(), preservedMembers: payload.preservedMembers,
            txtTocRules: payload.txtTocRules ?? [], readRecords: payload.readRecords ?? [], rssSources: payload.rssSources ?? [],
            rssStars: payload.rssStars ?? [], bookGroups: payload.bookGroups ?? [], dictRules: payload.dictRules ?? [],
            httpTTS: payload.httpTTS ?? [], deviceName: deviceName, date: date)
    }

    /// Creates a native Android member layout with an iOS-only reader settings sidecar.
    public func createBackupZip(
        books: [Book],
        sources: [BookSource],
        bookmarks: [Bookmark]? = nil,
        replaceRules: [ReplaceRule]? = nil,
        searchHistory: [SearchKeyword]? = nil,
        readConfig: ReadStyleConfig? = nil,
        ruleSubscriptions: [RuleSub]? = nil,
        readStyles: [ReadStyleConfig]? = nil,
        readerSettings: ReaderBackupSettings? = nil,
        preservedMembers: [String: Data]? = nil,
        txtTocRules: [TxtTocRule]? = nil,
        readRecords: [ReadRecord]? = nil,
        rssSources: [RssSource]? = nil,
        rssStars: [RssStar]? = nil,
        bookGroups: [BookGroup]? = nil,
        dictRules: [DictRule]? = nil,
        httpTTS: [HttpTTS]? = nil,
        deviceName: String = WebDAVConfig.defaultDeviceName,
        date: Date = Date()
    ) throws -> (data: Data, fileName: String) {
        let fileName = WebDAVConfig.generateBackupFileName(date: date, deviceName: deviceName)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        var entryNames: [String] = []

        func writeEntry<T: Encodable>(_ value: T, name: String) throws {
            let data = try encoder.encode(value)
            let fileURL = tempDir.appendingPathComponent(name)
            try data.write(to: fileURL)
            entryNames.append(name)
        }

        try writeEntry(books, name: "bookshelf.json")
        try writeEntry(sources, name: "bookSource.json")

        let resolvedBookmarks = bookmarks ?? BookmarkStore.load()
        if !resolvedBookmarks.isEmpty {
            try writeEntry(resolvedBookmarks, name: "bookmark.json")
        }

        let resolvedRules = replaceRules ?? ReplaceRuleStore.load()
        if !resolvedRules.isEmpty {
            try writeEntry(resolvedRules, name: "replaceRule.json")
        }

        let resolvedHistory = searchHistory ?? SearchHistoryStore.load()
        if !resolvedHistory.isEmpty {
            try writeEntry(resolvedHistory, name: "searchHistory.json")
        }
        let styles = readStyles ?? readConfig.map { [$0] } ?? ReaderStore.loadStyles()
        try writeEntry(styles, name: "readConfig.json")
        try writeEntry(readerSettings ?? ReaderBackupSettings(selectedStyle: ReaderStore.selectedStyleIndex(), prefs: ReaderStore.loadPrefs()), name: "iosReaderSettings.json")

        let resolvedTxtRules = txtTocRules ?? TxtTocRuleStore.load()
        if !resolvedTxtRules.isEmpty {
            try writeEntry(resolvedTxtRules, name: "txtTocRule.json")
        }

        let resolvedRecords = readRecords ?? ReadRecordStore.load()
        if !resolvedRecords.isEmpty {
            try writeEntry(resolvedRecords, name: "readRecord.json")
        }

        let resolvedRssSources = rssSources ?? RssStore.loadSources()
        if !resolvedRssSources.isEmpty {
            try writeEntry(resolvedRssSources, name: "rssSources.json")
        }

        let resolvedRssStars = rssStars ?? RssStore.loadStars()
        if !resolvedRssStars.isEmpty {
            try writeEntry(resolvedRssStars, name: "rssStar.json")
        }
        let groups = (bookGroups ?? BookGroupStore.load()).filter { $0.groupId != BookGroup.idNet }
        if !groups.isEmpty { try writeEntry(groups, name: "bookGroup.json") }
        let dictionaries = dictRules ?? DictRuleStore.load()
        if !dictionaries.isEmpty { try writeEntry(dictionaries, name: "dictRule.json") }
        let engines = (httpTTS ?? HttpTTSStore.load()).filter { $0.contentType != "system" }
        if !engines.isEmpty { try writeEntry(engines, name: "httpTTS.json") }

        try writeEntry(ruleSubscriptions ?? RuleSubStore.load(), name: "sourceSub.json")

        let opaque = preservedMembers ?? BackupCompatibilityStore.load()
        try BackupCompatibilityStore.validate(opaque)
        for (name, data) in opaque.sorted(by: { $0.key < $1.key }) where !entryNames.contains(name) && !Self.supportedBackupMembers.contains(name) {
            let url = tempDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            entryNames.append(name)
        }

        let zipFile = tempDir.appendingPathComponent(fileName)
        try {
            let archive = try Archive(url: zipFile, accessMode: .create)
            for name in entryNames {
                try archive.addEntry(with: name, relativeTo: tempDir, compressionMethod: .deflate)
            }
        }()

        let zipData = try Data(contentsOf: zipFile)
        return (zipData, fileName)
    }

    /// Backs up bookshelf, sources, bookmarks, replace rules, search history, and read config to WebDAV server
    public func backup(
        books: [Book],
        sources: [BookSource],
        bookmarks: [Bookmark]? = nil,
        replaceRules: [ReplaceRule]? = nil,
        searchHistory: [SearchKeyword]? = nil,
        readConfig: ReadStyleConfig? = nil,
        payload: BackupRestorePayload? = nil,
        config: WebDAVConfig
    ) async throws -> (booksCount: Int, sourcesCount: Int, backupFileName: String) {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        // Try ensuring directory exists
        try? await createDirectoryIfNeeded(config: config)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        // 1. Create and upload Android Legado compatible ZIP archive: backupYYYY-MM-DD-deviceName.zip
        let (zipData, zipFileName) = try payload.map { try createBackupZip(payload: $0, deviceName: config.deviceName) } ?? createBackupZip(
            books: books,
            sources: sources,
            bookmarks: bookmarks,
            replaceRules: replaceRules,
            searchHistory: searchHistory,
            readConfig: readConfig,
            deviceName: config.deviceName
        )
        let zipUrl = dirUrl.appendingPathComponent(zipFileName)
        let zipReq = try makeRequest(url: zipUrl, method: "PUT", config: config, body: zipData, contentType: "application/zip")
        let (_, zipResponse) = try await self.send(zipReq, config: config)
        guard let httpZip = zipResponse as? HTTPURLResponse else {
            throw WebDAVError.custom("上传备份压缩包无响应")
        }
        if httpZip.statusCode == 401 || httpZip.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(httpZip.statusCode) else {
            throw WebDAVError.serverError(httpZip.statusCode, "上传备份文件失败")
        }

        // 2. Also upload standalone bookshelf.json & bookSource.json for convenience and backwards compatibility
        let booksData = try encoder.encode(books)
        let booksUrl = dirUrl.appendingPathComponent("bookshelf.json")
        let booksReq = try makeRequest(url: booksUrl, method: "PUT", config: config, body: booksData, contentType: "application/json; charset=utf-8")
        _ = try? await self.send(booksReq, config: config)

        let sourcesData = try encoder.encode(sources)
        let sourcesUrl = dirUrl.appendingPathComponent("bookSource.json")
        let sourcesReq = try makeRequest(url: sourcesUrl, method: "PUT", config: config, body: sourcesData, contentType: "application/json; charset=utf-8")
        _ = try? await self.send(sourcesReq, config: config)

        // Update last sync time
        var updatedConfig = config
        updatedConfig.lastSyncTime = Date()
        saveConfig(updatedConfig)

        return (books.count, sources.count, zipFileName)
    }

    /// Lists all backup*.zip archives in the WebDAV directory, sorted descending (latest first)
    public func listRemoteBackups(config: WebDAVConfig) async throws -> [RemoteBackupInfo] {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        var propReq = try makeRequest(url: dirUrl, method: "PROPFIND", config: config)
        propReq.setValue("1", forHTTPHeaderField: "Depth")
        let (data, response) = try await self.send(propReq, config: config)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.custom("无法连接到 WebDAV 服务器")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) || http.statusCode == 207 else {
            return []
        }

        guard let xml = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseBackupsFromPropfindXML(xml, baseURL: dirUrl)
    }

    public func parseBackupsFromPropfindXML(_ xml: String, baseURL: URL) -> [RemoteBackupInfo] {
        var results: [RemoteBackupInfo] = []

        let responsePattern = #"(?is)<(?:[a-zA-Z0-9_-]+:)?response\b[^>]*>(.*?)</(?:[a-zA-Z0-9_-]+:)?response>"#
        guard let responseRegex = try? NSRegularExpression(pattern: responsePattern) else {
            return []
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = responseRegex.matches(in: xml, options: [], range: range)

        let hrefPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?href\b[^>]*>([^<]+)</(?:[a-zA-Z0-9_-]+:)?href>"#
        let hrefRegex = try? NSRegularExpression(pattern: hrefPattern)

        let lengthPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?getcontentlength\b[^>]*>([0-9]+)</(?:[a-zA-Z0-9_-]+:)?getcontentlength>"#
        let lengthRegex = try? NSRegularExpression(pattern: lengthPattern)

        let modPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?getlastmodified\b[^>]*>([^<]+)</(?:[a-zA-Z0-9_-]+:)?getlastmodified>"#
        let modRegex = try? NSRegularExpression(pattern: modPattern)

        let rfc822Formatter = DateFormatter()
        rfc822Formatter.locale = Locale(identifier: "en_US_POSIX")
        rfc822Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        for match in matches {
            guard let responseRange = Range(match.range(at: 1), in: xml) else { continue }
            let responseChunk = String(xml[responseRange])

            guard let hrefMatch = hrefRegex?.firstMatch(in: responseChunk, range: NSRange(responseChunk.startIndex..<responseChunk.endIndex, in: responseChunk)),
                  let hrefR = Range(hrefMatch.range(at: 1), in: responseChunk) else { continue }
            let rawHref = String(responseChunk[hrefR]).trimmingCharacters(in: .whitespacesAndNewlines)
            let decodedHref = rawHref.removingPercentEncoding ?? rawHref
            let fileName = URL(fileURLWithPath: decodedHref).lastPathComponent

            guard fileName.lowercased().hasPrefix("backup") && fileName.lowercased().hasSuffix(".zip") else {
                continue
            }

            guard let fullUrl = URL(string: rawHref, relativeTo: baseURL)?.absoluteURL, Self.isSameOrigin(fullUrl, baseURL) else {
                continue
            }

            var size: Int64? = nil
            if let lenMatch = lengthRegex?.firstMatch(in: responseChunk, range: NSRange(responseChunk.startIndex..<responseChunk.endIndex, in: responseChunk)),
               let lenR = Range(lenMatch.range(at: 1), in: responseChunk) {
                size = Int64(String(responseChunk[lenR]))
            }

            var lastModified: Date? = nil
            if let modMatch = modRegex?.firstMatch(in: responseChunk, range: NSRange(responseChunk.startIndex..<responseChunk.endIndex, in: responseChunk)),
               let modR = Range(modMatch.range(at: 1), in: responseChunk) {
                let modStr = String(responseChunk[modR]).trimmingCharacters(in: .whitespacesAndNewlines)
                lastModified = rfc822Formatter.date(from: modStr)
            }

            results.append(RemoteBackupInfo(
                fileName: fileName,
                url: fullUrl,
                lastModified: lastModified,
                size: size
            ))
        }

        return results.sorted { a, b in
            if let d1 = a.lastModified, let d2 = b.lastModified, abs(d1.timeIntervalSince(d2)) > 1.0 {
                return d1 > d2
            }
            return a.fileName > b.fileName
        }
    }

    /// Restores bookshelf and sources from WebDAV server (supports both Android backup*.zip and direct JSON files)
    // MARK: - Remote File Browsing (Plan 第一批 书架二级菜单 ④: 远程书籍)

    /// One entry of a WebDAV directory listing.
    public struct RemoteDirectoryEntry: Identifiable, Equatable {
        public var id: String { url.absoluteString }
        public let name: String
        public let url: URL
        public let isDirectory: Bool
        public let size: Int64?
    }

    /// Depth-1 PROPFIND listing of an arbitrary directory URL, used by the 远程书籍 browser.
    public func listDirectory(url directoryURL: URL, config: WebDAVConfig) async throws -> [RemoteDirectoryEntry] {
        var req = try makeRequest(url: directoryURL, method: "PROPFIND", config: config)
        req.setValue("1", forHTTPHeaderField: "Depth")
        let (data, response) = try await self.send(req, config: config)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.custom("无法连接到 WebDAV 服务器")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) || http.statusCode == 207 else {
            throw WebDAVError.custom("目录读取失败 (HTTP \(http.statusCode))")
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            return []
        }
        return Self.parseDirectoryEntries(from: xml, baseURL: directoryURL)
    }

    /// Shared regex parsing for PROPFIND multistatus: href + collection marker + size.
    static func parseDirectoryEntries(from xml: String, baseURL: URL) -> [RemoteDirectoryEntry] {
        let responsePattern = #"(?is)<(?:[a-zA-Z0-9_-]+:)?response\b[^>]*>(.*?)</(?:[a-zA-Z0-9_-]+:)?response>"#
        guard let responseRegex = try? NSRegularExpression(pattern: responsePattern) else { return [] }
        let hrefPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?href\b[^>]*>([^<]+)</(?:[a-zA-Z0-9_-]+:)?href>"#
        let hrefRegex = try? NSRegularExpression(pattern: hrefPattern)
        let collectionPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?collection\s*/?>"#
        let collectionRegex = try? NSRegularExpression(pattern: collectionPattern)
        let lengthPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?getcontentlength\b[^>]*>([0-9]+)</(?:[a-zA-Z0-9_-]+:)?getcontentlength>"#
        let lengthRegex = try? NSRegularExpression(pattern: lengthPattern)

        let baseDir = baseURL.hasDirectoryPath ? baseURL
            : baseURL.deletingLastPathComponent()

        var entries: [RemoteDirectoryEntry] = []
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        for match in responseRegex.matches(in: xml, options: [], range: range) {
            guard let chunkRange = Range(match.range(at: 1), in: xml) else { continue }
            let chunk = String(xml[chunkRange])
            guard let hrefMatch = hrefRegex?.firstMatch(in: chunk, range: NSRange(chunk.startIndex..<chunk.endIndex, in: chunk)),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: chunk) else { continue }
            let rawHref = String(chunk[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let decoded = rawHref.removingPercentEncoding ?? rawHref
            let name = URL(fileURLWithPath: decoded).lastPathComponent
            guard !name.isEmpty else { continue }
            guard let fullURL = URL(string: rawHref, relativeTo: baseDir)?.absoluteURL, Self.isSameOrigin(fullURL, baseURL) else { continue }

            let isDirectory = (collectionRegex?.firstMatch(
                in: chunk, range: NSRange(chunk.startIndex..<chunk.endIndex, in: chunk)) != nil)
            var size: Int64? = nil
            if !isDirectory,
               let lenMatch = lengthRegex?.firstMatch(in: chunk, range: NSRange(chunk.startIndex..<chunk.endIndex, in: chunk)),
               let lenRange = Range(lenMatch.range(at: 1), in: chunk) {
                size = Int64(String(chunk[lenRange]))
            }
            // The listing always echoes the requested directory itself; hide it. Servers
            // disagree about the trailing slash, so compare scheme+host+trimmed path.
            if Self.isSameDirectory(fullURL, baseDir) { continue }
            entries.append(RemoteDirectoryEntry(name: name, url: fullURL,
                                                isDirectory: isDirectory, size: size))
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func isSameDirectory(_ a: URL, _ b: URL) -> Bool {
        func key(_ u: URL) -> String {
            (u.scheme ?? "") + "://" + (u.host ?? "")
                + u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return key(a) == key(b)
    }

    /// Downloads one remote file (authenticated GET) — the 远程书籍 import step.
    public func downloadFileData(url fileURL: URL, config: WebDAVConfig) async throws -> Data {
        let req = try makeRequest(url: fileURL, method: "GET", config: config)
        let (data, response) = try await self.send(req, config: config)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.custom("无法连接到 WebDAV 服务器")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebDAVError.custom("文件下载失败 (HTTP \(http.statusCode))")
        }
        return data
    }

    public func restore(config: WebDAVConfig, backupFileName: String? = nil) async throws -> (books: [Book]?, sources: [BookSource]?, backupName: String?) {
        let payload = try await restorePayload(config: config, backupFileName: backupFileName)
        return (payload.books, payload.sources, payload.backupName)
    }

    /// Restores the full `BackupRestorePayload` (books, sources, bookmarks, replaceRules, searchHistory, readConfig) from WebDAV.
    public func restorePayload(config: WebDAVConfig, backupFileName: String? = nil) async throws -> BackupRestorePayload {
        guard let dirUrl = config.directoryURL else {
            throw WebDAVError.invalidURL
        }

        var payload = BackupRestorePayload()

        // 1. Try finding and downloading Android-compatible backup*.zip files first
        if let remoteBackups = try? await listRemoteBackups(config: config), !remoteBackups.isEmpty {
            let targetBackup: RemoteBackupInfo
            if let specificName = backupFileName {
                guard let found = remoteBackups.first(where: { $0.fileName == specificName }) else {
                    throw WebDAVError.backupNotFound
                }
                targetBackup = found
            } else {
                targetBackup = remoteBackups[0]
            }

            let zipReq = try makeRequest(url: targetBackup.url, method: "GET", config: config)
            let (zipData, zipResp) = try await self.send(zipReq, config: config)
            guard let httpZip = zipResp as? HTTPURLResponse else { throw WebDAVError.custom("无效的备份响应") }
            if [401, 403].contains(httpZip.statusCode) { throw WebDAVError.unauthorized }
            guard (200..<300).contains(httpZip.statusCode) else { throw WebDAVError.serverError(httpZip.statusCode, targetBackup.fileName) }
            payload = try restorePayloadFromZip(data: zipData)
            payload.backupName = targetBackup.fileName
        }

        if backupFileName != nil && payload.backupName == nil { throw WebDAVError.backupNotFound }
        let restoredArchive = payload.backupName?.hasSuffix(".zip") == true
        // An archive is one snapshot. Only use loose metadata when no archive was selected.
        if !restoredArchive {
            let entries = try await withThrowingTaskGroup(of: (String, Data?).self) { group in
                for name in Self.supportedBackupMembers + Self.preservedAndroidBackupMembers {
                    group.addTask {
                        var request = try self.makeRequest(url: dirUrl.appendingPathComponent(name), method: "GET", config: config)
                        request.timeoutInterval = 15
                        let (data, response) = try await self.send(request, config: config)
                        guard let response = response as? HTTPURLResponse else { throw WebDAVError.custom("无效的备份响应") }
                        if [401, 403].contains(response.statusCode) { throw WebDAVError.unauthorized }
                        if response.statusCode == 404 { return (name, nil) }
                        guard (200..<300).contains(response.statusCode) else { throw WebDAVError.serverError(response.statusCode, name) }
                        return (name, data)
                    }
                }
                var entries: [String: Data] = [:]
                for try await (name, data) in group { if let data = data { entries[name] = data } }
                return entries
            }
            payload = try decodeBackupMembers { entries[$0] }
            payload.preservedMembers = entries.filter { !Self.supportedBackupMembers.contains($0.key) }
            try BackupCompatibilityStore.validate(payload.preservedMembers)
            payload.backupName = (Self.supportedBackupMembers + Self.preservedAndroidBackupMembers).first { entries[$0] != nil }
        }

        // 3. Sync any latest progress from remote bookProgress/ folder using single PROPFIND + concurrent batch fetch
        if var books = payload.books {
            let progressDirUrl = dirUrl.appendingPathComponent("bookProgress")
            var propReq = try makeRequest(url: progressDirUrl, method: "PROPFIND", config: config)
            propReq.setValue("1", forHTTPHeaderField: "Depth")
            if let (propData, propResp) = try? await self.send(propReq, config: config),
               let httpProp = propResp as? HTTPURLResponse, (200...299).contains(httpProp.statusCode) || httpProp.statusCode == 207,
               let propXml = String(data: propData, encoding: .utf8) {

                let hrefPattern = #"(?i)<(?:[a-zA-Z0-9_-]+:)?href\b[^>]*>([^<]+\.json)</(?:[a-zA-Z0-9_-]+:)?href>"#
                if let regex = try? NSRegularExpression(pattern: hrefPattern) {
                    let range = NSRange(propXml.startIndex..<propXml.endIndex, in: propXml)
                    let matches = regex.matches(in: propXml, options: [], range: range)
                    var remoteFiles: [String: URL] = [:]
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: propXml) {
                            let rawPath = String(propXml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let decoded = rawPath.removingPercentEncoding ?? rawPath
                            let fn = URL(fileURLWithPath: decoded).lastPathComponent
                            if let full = URL(string: rawPath, relativeTo: progressDirUrl)?.absoluteURL, Self.isSameOrigin(full, dirUrl) {
                                remoteFiles[fn] = full
                            }
                        }
                    }

                    if !remoteFiles.isEmpty {
                        var tasks: [(index: Int, url: URL)] = []
                        for i in 0..<books.count {
                            let expectedName = sanitizeFileName("\(books[i].name)_\(books[i].author).json")
                            if let fUrl = remoteFiles[expectedName] {
                                tasks.append((i, fUrl))
                            }
                        }

                        if !tasks.isEmpty {
                            await withTaskGroup(of: (Int, BookProgress?).self) { group in
                                for item in tasks {
                                    group.addTask {
                                        guard let pReq = try? self.makeRequest(url: item.url, method: "GET", config: config) else { return (item.index, nil) }
                                        if let (pData, pResp) = try? await self.send(pReq, config: config),
                                           let httpP = pResp as? HTTPURLResponse, (200...299).contains(httpP.statusCode),
                                           let prog = try? JSONDecoder().decode(BookProgress.self, from: pData) {
                                            return (item.index, prog)
                                        }
                                        return (item.index, nil)
                                    }
                                }

                                for await (idx, progOpt) in group {
                                    if let progress = progOpt, idx < books.count {
                                        books[idx] = progress.applying(to: books[idx])
                                    }
                                }
                            }
                            payload.books = books
                        }
                    }
                }
            }
        }

        if !payload.hasSupportedMembers {
            throw WebDAVError.backupNotFound
        }

        // Update last sync time
        var updatedConfig = config
        updatedConfig.lastSyncTime = Date()
        saveConfig(updatedConfig)

        return payload
    }

    // MARK: - Zip Archive Restoration (Android Legado Compatible)

    /// Restores books and sources from a ZIP archive data (e.g. backup*.zip)
    public func restoreFromZip(data: Data) throws -> (books: [Book]?, sources: [BookSource]?) {
        let p = try restorePayloadFromZip(data: data)
        return (p.books, p.sources)
    }

    /// Restores full payload from a ZIP archive data (e.g. backup*.zip)
    public func restorePayloadFromZip(data: Data) throws -> BackupRestorePayload {
        guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw WebDAVError.decodingFailed("无法解析 Zip 压缩包数据")
        }
        return try parseArchivePayload(archive)
    }

    /// Restores books and sources from a local ZIP file URL, and merges adjacent bookProgress if found
    public func restoreFromZip(fileUrl: URL) throws -> (books: [Book]?, sources: [BookSource]?) {
        let p = try restorePayloadFromZip(fileUrl: fileUrl)
        return (p.books, p.sources)
    }

    /// Restores full payload from a local ZIP file URL, and merges adjacent bookProgress if found
    public func restorePayloadFromZip(fileUrl: URL) throws -> BackupRestorePayload {
        guard let archive = try? Archive(url: fileUrl, accessMode: .read, pathEncoding: nil) else {
            throw WebDAVError.decodingFailed("无法读取 Zip 备份文件: \(fileUrl.lastPathComponent)")
        }
        var result = try parseArchivePayload(archive)

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

    public static let supportedBackupMembers = [
        "bookshelf.json", "bookSource.json", "bookmark.json", "replaceRule.json", "searchHistory.json",
        "readConfig.json", "txtTocRule.json", "readRecord.json", "rssSources.json", "rssStar.json",
        "bookGroup.json", "dictRule.json", "httpTTS.json", "sourceSub.json", "iosReaderSettings.json"
    ]
    public static let preservedAndroidBackupMembers = [
        "servers.json", "keyboardAssists.json", "directLinkUploadRule.json", "shareReadConfig.json",
        "themeConfig.json", "coverRule.json", "config.xml"
    ]

    private func decodeBackupMembers(_ extractData: (String) throws -> Data?) throws -> BackupRestorePayload {
        var payload = BackupRestorePayload()
        // 1. bookshelf.json
        if let data = try extractData("bookshelf.json"),
           let decoded = Book.decodeListWithExtras(from: data) {
            payload.books = decoded
        }

        // 2. bookSource.json
        if let data = try extractData("bookSource.json"),
           let decoded = BookSource.decodeListWithExtras(from: data) {
            payload.sources = decoded
        }

        // 3. bookmark.json
        if let data = try extractData("bookmark.json"),
           let decoded = TolerantJSON.decodeList(Bookmark.self, from: data, fallback: Bookmark(bookName: "")) {
            payload.bookmarks = decoded
        }

        // 4. replaceRule.json
        if let data = try extractData("replaceRule.json"),
           let decoded = TolerantJSON.decodeList(ReplaceRule.self, from: data, fallback: ReplaceRule()) {
            payload.replaceRules = decoded
        }

        // 5. searchHistory.json
        if let data = try extractData("searchHistory.json"),
           let decoded = TolerantJSON.decodeList(SearchKeyword.self, from: data, fallback: SearchKeyword(word: "")) {
            payload.searchHistory = decoded
        }

        // Android exports every style; the iOS sidecar carries its selected index.
        if let data = try extractData("readConfig.json") {
            if let list = try? JSONDecoder().decode([ReadStyleConfig].self, from: data) {
                payload.readStyles = list
                payload.readConfig = list.first
            } else if let single = ReadStyleConfig.decodeWithExtras(from: data) {
                payload.readStyles = [single]
                payload.readConfig = single
            } else { throw WebDAVError.decodingFailed("阅读样式无效") }
        }
        if let data = try extractData("iosReaderSettings.json") {
            payload.readerSettings = try JSONDecoder().decode(ReaderBackupSettings.self, from: data)
        }

        if let data = try extractData("sourceSub.json") {
            guard let list = try? JSONDecoder().decode([RuleSub].self, from: data) else { throw WebDAVError.decodingFailed("规则订阅无效") }
            payload.ruleSubscriptions = list
        }

        // 7. txtTocRule.json
        if let data = try extractData("txtTocRule.json"),
           let decoded = TolerantJSON.decodeList(TxtTocRule.self, from: data, fallback: TxtTocRule()) {
            payload.txtTocRules = decoded
        }

        // 8. readRecord.json
        if let data = try extractData("readRecord.json"),
           let decoded = TolerantJSON.decodeList(ReadRecord.self, from: data, fallback: ReadRecord()) {
            payload.readRecords = decoded
        }

        // 9. rssSources.json
        if let data = try extractData("rssSources.json"),
           let decoded = TolerantJSON.decodeList(RssSource.self, from: data, fallback: RssSource()) {
            payload.rssSources = decoded
        }

        // 10. rssStar.json
        if let data = try extractData("rssStar.json"),
           let decoded = TolerantJSON.decodeList(RssStar.self, from: data, fallback: RssStar()) {
            payload.rssStars = decoded
        }
        if let data = try extractData("bookGroup.json") {
            guard let groups = BookGroup.decodeListWithExtras(from: data) else { throw WebDAVError.decodingFailed("分组数据无效") }
            for group in groups where group.groupId > 0 && !BookGroupCompatibility.isSingleBit(group.groupId) {
                throw BookGroupCompatibilityError.invalidIdentifier(group.groupId)
            }
            payload.bookGroups = groups
        }
        if let data = try extractData("dictRule.json") {
            guard let rules = DictRule.decodeListWithExtras(from: data) else { throw WebDAVError.decodingFailed("字典规则无效") }
            payload.dictRules = rules
        }
        if let data = try extractData("httpTTS.json") {
            guard let engines = HttpTTS.decodeListWithExtras(from: data) else { throw WebDAVError.decodingFailed("朗读规则无效") }
            payload.httpTTS = engines
        }

        // A malformed known member must fail before any store is changed. Import tools
        // can be tolerant, but a backup must not silently discard invalid array rows.
        let counts: [(String, Int?)] = [
            ("bookshelf.json", payload.books?.count), ("bookSource.json", payload.sources?.count),
            ("bookmark.json", payload.bookmarks?.count), ("replaceRule.json", payload.replaceRules?.count),
            ("searchHistory.json", payload.searchHistory?.count), ("txtTocRule.json", payload.txtTocRules?.count),
            ("readRecord.json", payload.readRecords?.count), ("rssSources.json", payload.rssSources?.count),
            ("rssStar.json", payload.rssStars?.count), ("bookGroup.json", payload.bookGroups?.count),
            ("dictRule.json", payload.dictRules?.count), ("httpTTS.json", payload.httpTTS?.count)
        ]
        for (name, count) in counts {
            guard let data = try extractData(name) else { continue }
            guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], count == array.count else {
                throw WebDAVError.decodingFailed("\(name) 包含无效数据，未执行恢复")
            }
        }

        return payload
    }

    /// Parses all supported Legado JSON members (bookshelf, bookSource, bookmark, replaceRule, searchHistory, readConfig, bookProgress) from a ZIP archive
    public func parseArchivePayload(_ archive: Archive) throws -> BackupRestorePayload {
        var payload = BackupRestorePayload()

        // Extract into bounded memory, never into paths supplied by an archive.
        var entries: [String: Data] = [:]
        var total = 0
        for entry in archive {
            guard entry.type == .file else {
                if entry.type == .directory { continue }
                throw WebDAVError.decodingFailed("备份包含不支持的链接")
            }
            try BackupCompatibilityStore.validate(path: entry.path)
            guard entries[entry.path] == nil, entry.uncompressedSize <= UInt64(BackupCompatibilityStore.maximumMemberSize) else {
                throw WebDAVError.decodingFailed("备份条目重复或过大")
            }
            var bytes = Data()
            _ = try archive.extract(entry) { chunk in
                guard bytes.count <= BackupCompatibilityStore.maximumMemberSize - chunk.count,
                      total <= BackupCompatibilityStore.maximumTotalSize - chunk.count else {
                    throw WebDAVError.decodingFailed("备份数据超过大小限制")
                }
                bytes.append(chunk)
                total += chunk.count
            }
            entries[entry.path] = bytes
        }
        var consumed = Set<String>()
        payload = try decodeBackupMembers { name in
            let candidates = entries.keys.filter { $0 == name || $0.hasSuffix("/" + name) }.sorted()
            guard candidates.count <= 1 else { throw WebDAVError.decodingFailed("备份包含重复的数据文件") }
            guard let path = candidates.first else { return nil }
            consumed.insert(path)
            return entries[path]
        }
        payload.preservedMembers = entries.filter { !consumed.contains($0.key) }

        // 11. Extract any internal bookProgress/*.json
        var progressMap: [String: BookProgress] = [:]
        for (path, pData) in entries {
            if (path.hasPrefix("bookProgress/") || path.contains("/bookProgress/")) && path.hasSuffix(".json"),
               let prog = try? JSONDecoder().decode(BookProgress.self, from: pData) {
                progressMap["\(prog.name)_\(prog.author)"] = prog
            }
        }

        // Apply progress updates to books
        if var books = payload.books, !progressMap.isEmpty {
            for i in 0..<books.count {
                let key = "\(books[i].name)_\(books[i].author)"
                if let progress = progressMap[key] {
                    books[i] = progress.applying(to: books[i])
                }
            }
            payload.books = books
        }

        if !payload.hasSupportedMembers {
            throw WebDAVError.backupNotFound
        }

        return payload
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
            if let progress = progressMap[key] {
                books[i] = progress.applying(to: books[i])
            }
        }
    }
}

/// A PROPFIND href or HTTP redirect must never send WebDAV credentials to another origin.
final class WebDAVRedirectGuard: NSObject, URLSessionTaskDelegate {
    private let config: WebDAVConfig
    init(config: WebDAVConfig) { self.config = config }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, let base = config.directoryURL, WebDAVService.isSameOrigin(url, base) else { completionHandler(nil); return }
        var authorized = request
        authorized.setValue(config.basicAuthHeader, forHTTPHeaderField: "Authorization")
        completionHandler(authorized)
    }
}

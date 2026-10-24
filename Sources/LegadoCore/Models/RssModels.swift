import Foundation

/// RSS / 订阅源实体，字段与 Android `data/entities/RssSource.kt` 完全一致
public struct RssSource: Codable, Identifiable, Equatable, JSONExtraPreserving {
    public var id: String { sourceUrl }
    public var sourceUrl: String
    public var sourceName: String
    public var sourceIcon: String?
    public var sourceGroup: String?
    public var sourceComment: String?
    public var enabled: Bool
    public var variableComment: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var header: String?
    public var sortUrl: String?
    public var singleUrl: Bool
    public var articleStyle: Int
    public var ruleArticles: String?
    public var ruleNextPage: String?
    public var ruleTitle: String?
    public var rulePubDate: String?
    public var ruleDescription: String?
    public var ruleImage: String?
    public var ruleLink: String?
    public var ruleContent: String?
    public var style: String?
    public var enableJs: Bool
    public var loadWithBaseUrl: Bool
    public var lastUpdateTime: Int64
    public var customOrder: Int
    public var variable: String?

    /// Android-only fields this model does not declare (`enabledCookieJar`, `concurrentRate` …),
    /// kept verbatim so订阅源 import → export/backup round-trips without loss.
    public var extra: [String: JSONValue] = [:]

    public init(
        sourceUrl: String = "",
        sourceName: String = "",
        sourceIcon: String? = nil,
        sourceGroup: String? = nil,
        sourceComment: String? = nil,
        enabled: Bool = true,
        variableComment: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        header: String? = nil,
        sortUrl: String? = nil,
        singleUrl: Bool = false,
        articleStyle: Int = 0,
        ruleArticles: String? = nil,
        ruleNextPage: String? = nil,
        ruleTitle: String? = nil,
        rulePubDate: String? = nil,
        ruleDescription: String? = nil,
        ruleImage: String? = nil,
        ruleLink: String? = nil,
        ruleContent: String? = nil,
        style: String? = nil,
        enableJs: Bool = true,
        loadWithBaseUrl: Bool = true,
        lastUpdateTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        customOrder: Int = 0,
        variable: String? = nil
    ) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.sourceIcon = sourceIcon
        self.sourceGroup = sourceGroup
        self.sourceComment = sourceComment
        self.enabled = enabled
        self.variableComment = variableComment
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.header = header
        self.sortUrl = sortUrl
        self.singleUrl = singleUrl
        self.articleStyle = articleStyle
        self.ruleArticles = ruleArticles
        self.ruleNextPage = ruleNextPage
        self.ruleTitle = ruleTitle
        self.rulePubDate = rulePubDate
        self.ruleDescription = ruleDescription
        self.ruleImage = ruleImage
        self.ruleLink = ruleLink
        self.ruleContent = ruleContent
        self.style = style
        self.enableJs = enableJs
        self.loadWithBaseUrl = loadWithBaseUrl
        self.lastUpdateTime = lastUpdateTime
        self.customOrder = customOrder
        self.variable = variable
    }

    enum CodingKeys: String, CodingKey {
        case sourceUrl, sourceName, sourceIcon, sourceGroup, sourceComment, enabled
        case variableComment, loginUrl, loginUi, header, sortUrl, singleUrl, articleStyle
        case ruleArticles, ruleNextPage, ruleTitle, rulePubDate, ruleDescription
        case ruleImage, ruleLink, ruleContent, style, enableJs, loadWithBaseUrl
        case lastUpdateTime, customOrder, variable
    }

    public static let modeledJSONKeys: Set<String> = [
        "sourceUrl", "sourceName", "sourceIcon", "sourceGroup", "sourceComment", "enabled",
        "variableComment", "loginUrl", "loginUi", "header", "sortUrl", "singleUrl",
        "articleStyle", "ruleArticles", "ruleNextPage", "ruleTitle", "rulePubDate",
        "ruleDescription", "ruleImage", "ruleLink", "ruleContent", "style", "enableJs",
        "loadWithBaseUrl", "lastUpdateTime", "customOrder", "variable"
    ]

    /// Tolerant decode: every non-optional field falls back to its default when absent, so a
    /// hand-written or partial `RssSource` JSON no longer fails the whole import.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceUrl = (try? container.decode(String.self, forKey: .sourceUrl)) ?? ""
        self.sourceName = (try? container.decode(String.self, forKey: .sourceName)) ?? ""
        self.sourceIcon = try? container.decodeIfPresent(String.self, forKey: .sourceIcon)
        self.sourceGroup = try? container.decodeIfPresent(String.self, forKey: .sourceGroup)
        self.sourceComment = try? container.decodeIfPresent(String.self, forKey: .sourceComment)
        self.enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        self.variableComment = try? container.decodeIfPresent(String.self, forKey: .variableComment)
        self.loginUrl = try? container.decodeIfPresent(String.self, forKey: .loginUrl)
        self.loginUi = try? container.decodeIfPresent(String.self, forKey: .loginUi)
        self.header = try? container.decodeIfPresent(String.self, forKey: .header)
        self.sortUrl = try? container.decodeIfPresent(String.self, forKey: .sortUrl)
        self.singleUrl = (try? container.decodeIfPresent(Bool.self, forKey: .singleUrl)) ?? false
        self.articleStyle = (try? container.decodeIfPresent(Int.self, forKey: .articleStyle)) ?? 0
        self.ruleArticles = try? container.decodeIfPresent(String.self, forKey: .ruleArticles)
        self.ruleNextPage = try? container.decodeIfPresent(String.self, forKey: .ruleNextPage)
        self.ruleTitle = try? container.decodeIfPresent(String.self, forKey: .ruleTitle)
        self.rulePubDate = try? container.decodeIfPresent(String.self, forKey: .rulePubDate)
        self.ruleDescription = try? container.decodeIfPresent(String.self, forKey: .ruleDescription)
        self.ruleImage = try? container.decodeIfPresent(String.self, forKey: .ruleImage)
        self.ruleLink = try? container.decodeIfPresent(String.self, forKey: .ruleLink)
        self.ruleContent = try? container.decodeIfPresent(String.self, forKey: .ruleContent)
        self.style = try? container.decodeIfPresent(String.self, forKey: .style)
        self.enableJs = (try? container.decodeIfPresent(Bool.self, forKey: .enableJs)) ?? true
        self.loadWithBaseUrl = (try? container.decodeIfPresent(Bool.self, forKey: .loadWithBaseUrl)) ?? true
        self.lastUpdateTime = (try? container.decodeIfPresent(Int64.self, forKey: .lastUpdateTime))
            ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.customOrder = (try? container.decodeIfPresent(Int.self, forKey: .customOrder)) ?? 0
        self.variable = try? container.decodeIfPresent(String.self, forKey: .variable)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceUrl, forKey: .sourceUrl)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encodeIfPresent(sourceIcon, forKey: .sourceIcon)
        try container.encodeIfPresent(sourceGroup, forKey: .sourceGroup)
        try container.encodeIfPresent(sourceComment, forKey: .sourceComment)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(variableComment, forKey: .variableComment)
        try container.encodeIfPresent(loginUrl, forKey: .loginUrl)
        try container.encodeIfPresent(loginUi, forKey: .loginUi)
        try container.encodeIfPresent(header, forKey: .header)
        try container.encodeIfPresent(sortUrl, forKey: .sortUrl)
        try container.encode(singleUrl, forKey: .singleUrl)
        try container.encode(articleStyle, forKey: .articleStyle)
        try container.encodeIfPresent(ruleArticles, forKey: .ruleArticles)
        try container.encodeIfPresent(ruleNextPage, forKey: .ruleNextPage)
        try container.encodeIfPresent(ruleTitle, forKey: .ruleTitle)
        try container.encodeIfPresent(rulePubDate, forKey: .rulePubDate)
        try container.encodeIfPresent(ruleDescription, forKey: .ruleDescription)
        try container.encodeIfPresent(ruleImage, forKey: .ruleImage)
        try container.encodeIfPresent(ruleLink, forKey: .ruleLink)
        try container.encodeIfPresent(ruleContent, forKey: .ruleContent)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encode(enableJs, forKey: .enableJs)
        try container.encode(loadWithBaseUrl, forKey: .loadWithBaseUrl)
        try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
        try container.encode(customOrder, forKey: .customOrder)
        try container.encodeIfPresent(variable, forKey: .variable)
        try encodeJSONExtras(extra, to: encoder)
    }

    public var groups: [String] {
        guard let group = sourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty else {
            return []
        }
        return group.components(separatedBy: CharacterSet(charactersIn: ",;，；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// RSS 文章实体，对应 Android `data/entities/RssArticle.kt`
public struct RssArticle: Codable, Identifiable, Equatable {
    public var id: String { "\(origin)_\(link)" }
    public var origin: String
    public var sort: String
    public var title: String
    public var order: Int64
    public var link: String
    public var pubDate: String?
    public var description: String?
    public var content: String?
    public var image: String?
    public var group: String
    public var read: Bool
    public var variable: String?

    public init(
        origin: String = "",
        sort: String = "",
        title: String = "",
        order: Int64 = 0,
        link: String = "",
        pubDate: String? = nil,
        description: String? = nil,
        content: String? = nil,
        image: String? = nil,
        group: String = "默认分组",
        read: Bool = false,
        variable: String? = nil
    ) {
        self.origin = origin
        self.sort = sort
        self.title = title
        self.order = order
        self.link = link
        self.pubDate = pubDate
        self.description = description
        self.content = content
        self.image = image
        self.group = group
        self.read = read
        self.variable = variable
    }
}

/// 已读状态判定：瞬态 `read` 标记或持久化 read-state 命中任一即为已读。
extension RssArticle {
    public func isRead(in state: [String: Int64]) -> Bool {
        read || state[RssStore.articleKey(origin: origin, link: link)] != nil
    }
}

/// RSS 收藏项实体，对应 Android `data/entities/RssStar.kt`
public struct RssStar: Codable, Identifiable, Equatable {
    public var id: String { "\(origin)_\(link)" }
    public var origin: String
    public var sort: String
    public var title: String
    public var starTime: Int64
    public var link: String
    public var pubDate: String?
    public var description: String?
    public var content: String?
    public var image: String?
    public var group: String
    public var variable: String?

    public init(
        origin: String = "",
        sort: String = "",
        title: String = "",
        starTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        link: String = "",
        pubDate: String? = nil,
        description: String? = nil,
        content: String? = nil,
        image: String? = nil,
        group: String = "默认分组",
        variable: String? = nil
    ) {
        self.origin = origin
        self.sort = sort
        self.title = title
        self.starTime = starTime
        self.link = link
        self.pubDate = pubDate
        self.description = description
        self.content = content
        self.image = image
        self.group = group
        self.variable = variable
    }
}

/// RSS 源与文章持久化 Store
public enum RssStore {
    public static let sourcesKey = "legado_rss_sources_v1"
    public static let starsKey = "legado_rss_stars_v1"
    public static let readKey = "legado_rss_read_v1"
    public static let historyKey = "legado_rss_history_v1"

    /// 阅读历史记录条目（Plan Phase 1 Part 1.5：文章已读状态与历史落盘追踪）。
    public struct RssReadRecord: Codable, Identifiable, Equatable {
        public var id: String { "\(origin)_\(link)" }
        public var origin: String
        public var link: String
        public var title: String
        public var readTime: Int64

        public init(origin: String, link: String, title: String, readTime: Int64) {
            self.origin = origin
            self.link = link
            self.title = title
            self.readTime = readTime
        }
    }

    /// Stable key for an article across sessions: origin + link.
    public static func articleKey(origin: String, link: String) -> String {
        origin + "\u{1}" + link
    }

    /// Read marks keyed by `articleKey`, value = epoch millis when read. Capped so the store
    /// cannot grow without bound; oldest entries are evicted first.
    public static func loadReadState(from defaults: UserDefaults = .standard) -> [String: Int64] {
        guard let data = defaults.data(forKey: readKey),
              let dict = try? JSONDecoder().decode([String: Int64].self, from: data) else {
            return [:]
        }
        return dict
    }

    public static func saveReadState(_ state: [String: Int64], to defaults: UserDefaults = .standard) {
        var trimmed = state
        let maxEntries = 2_000
        if trimmed.count > maxEntries {
            let sorted = trimmed.sorted { $0.value < $1.value }
            let drop = Set(sorted.prefix(trimmed.count - maxEntries).map { $0.key })
            trimmed = trimmed.filter { !drop.contains($0.key) }
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: readKey)
        }
    }

    /// Marks one article read and appends it to the persisted reading history (newest first).
    public static func markArticleRead(_ article: RssArticle, to defaults: UserDefaults = .standard) {
        let key = articleKey(origin: article.origin, link: article.link)
        var state = loadReadState(from: defaults)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if state[key] == nil {
            state[key] = now
            saveReadState(state, to: defaults)

            var history = loadReadHistory(from: defaults)
            history.removeAll { $0.id == key }
            history.insert(
                RssReadRecord(origin: article.origin, link: article.link, title: article.title, readTime: now),
                at: 0
            )
            if history.count > 500 {
                history = Array(history.prefix(500))
            }
            if let data = try? JSONEncoder().encode(history) {
                defaults.set(data, forKey: historyKey)
            }
        }
    }

    public static func loadReadHistory(from defaults: UserDefaults = .standard) -> [RssReadRecord] {
        guard let data = defaults.data(forKey: historyKey),
              let list = try? JSONDecoder().decode([RssReadRecord].self, from: data) else {
            return []
        }
        return list
    }

    public static let defaultSources: [RssSource] = [
        RssSource(
            sourceUrl: "https://sspai.com/feed",
            sourceName: "少数派 (RSS Feed)",
            sourceIcon: "https://sspai.com/favicon.ico",
            sourceGroup: "科技资讯",
            enabled: true,
            sortUrl: "全部::https://sspai.com/feed",
            ruleArticles: "//item",
            ruleTitle: "//title/text()",
            rulePubDate: "//pubDate/text()",
            ruleDescription: "//description/text()",
            ruleLink: "//link/text()",
            ruleContent: "//description/text()"
        ),
        RssSource(
            sourceUrl: "https://www.v2ex.com/index.xml",
            sourceName: "V2EX (主题精选)",
            sourceIcon: "https://www.v2ex.com/favicon.ico",
            sourceGroup: "社区讨论",
            enabled: true,
            sortUrl: "精选::https://www.v2ex.com/index.xml",
            ruleArticles: "//entry",
            ruleTitle: "//title/text()",
            rulePubDate: "//published/text()",
            ruleDescription: "//content/text()",
            ruleLink: "//link/@href",
            ruleContent: "//content/text()"
        )
    ]

    public static func loadSources(from defaults: UserDefaults = .standard) -> [RssSource] {
        guard let data = defaults.data(forKey: sourcesKey) else {
            return defaultSources
        }
        let list = TolerantJSON.decodeList(RssSource.self, from: data, fallback: RssSource()) ?? []
        return list.isEmpty ? defaultSources : list
    }

    public static func saveSources(_ sources: [RssSource], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: sourcesKey)
        }
    }

    public static func loadStars(from defaults: UserDefaults = .standard) -> [RssStar] {
        guard let data = defaults.data(forKey: starsKey) else { return [] }
        return TolerantJSON.decodeList(RssStar.self, from: data, fallback: RssStar()) ?? []
    }

    public static func saveStars(_ stars: [RssStar], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(stars) {
            defaults.set(data, forKey: starsKey)
        }
    }

    public static func exportSourcesJSON(_ sources: [RssSource]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(sources) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func importSourcesJSON(_ json: String, into current: [RssSource]) -> [RssSource] {
        guard let data = json.data(using: .utf8) else { return current }
        var imported: [RssSource] = []
        let list = RssSource.decodeListWithExtras(from: data) ?? []
        if list.count > 1 {
            imported = list
        } else if let single = RssSource.decodeWithExtras(from: data) {
            imported = [single]
        } else if let first = list.first {
            imported = [first]
        }
        guard !imported.isEmpty else { return current }
        var result = current
        for s in imported {
            if let idx = result.firstIndex(where: { $0.sourceUrl == s.sourceUrl }) {
                result[idx] = s
            } else {
                result.append(s)
            }
        }
        return result
    }
}

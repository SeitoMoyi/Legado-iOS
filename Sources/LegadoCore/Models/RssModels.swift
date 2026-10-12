import Foundation

/// RSS / 订阅源实体，字段与 Android `data/entities/RssSource.kt` 完全一致
public struct RssSource: Codable, Identifiable, Equatable {
    public var id: String { sourceUrl }
    public var sourceUrl: String
    public var sourceName: String
    public var sourceIcon: String?
    public var sourceGroup: String?
    public var sourceComment: String?
    public var enabled: Bool
    public var variableComment: String?
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

    public init(
        sourceUrl: String = "",
        sourceName: String = "",
        sourceIcon: String? = nil,
        sourceGroup: String? = nil,
        sourceComment: String? = nil,
        enabled: Bool = true,
        variableComment: String? = nil,
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
        customOrder: Int = 0
    ) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.sourceIcon = sourceIcon
        self.sourceGroup = sourceGroup
        self.sourceComment = sourceComment
        self.enabled = enabled
        self.variableComment = variableComment
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
        if let list = try? JSONDecoder().decode([RssSource].self, from: data) {
            imported = list
        } else if let single = try? JSONDecoder().decode(RssSource.self, from: data) {
            imported = [single]
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

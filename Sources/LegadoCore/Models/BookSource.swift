import Foundation

public struct BookSource: Codable, Identifiable, Equatable {
    public var id: String { bookSourceUrl }

    public var bookSourceUrl: String
    public var bookSourceName: String
    public var bookSourceGroup: String?
    public var bookSourceType: Int?
    public var bookUrlPattern: String?
    public var customOrder: Int?
    public var enabled: Bool?
    public var enabledExplore: Bool?
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    public var coverDecodeJs: String?
    public var bookSourceComment: String?
    public var variableComment: String?
    public var lastUpdateTime: Int64?
    public var respondTime: Int64?
    public var weight: Int?
    public var exploreUrl: String?
    public var exploreScreen: String?
    public var searchUrl: String?

    public var ruleExplore: ExploreRule?
    public var ruleSearch: SearchRule?
    public var ruleBookInfo: BookInfoRule?
    public var ruleToc: TocRule?
    public var ruleContent: ContentRule?

    public var loginInfo: String?
    public var loginHeader: String?
    public var variable: String?

    /// Android splits group lists with `AppPattern.splitGroupRegex = Regex("[,;，；]")`.
    /// `\n` is added because hand-edited source JSON frequently puts one group per line.
    public var groups: [String] {
        (bookSourceGroup ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",;，；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var isLogged: Bool {
        guard let h = loginHeader, !h.isEmpty else { return false }
        return true
    }

    /// `CheckSource.timeout` default. When a 校验 fails, Android stores
    /// `respondTime = CheckSource.timeout + spendingTime`, so anything at or above this floor is a
    /// failure marker rather than a latency (ESJ ships `185203` = `180000 + 5203`).
    public static let androidFailureRespondTimeMs: Int64 = 180_000

    /// True when `respondTime` looks like a measurement worth showing, rather than Android's
    /// 校验失败 marker or a missing value. Display-side only — the stored field is never rewritten.
    public static func isMeasuredRespondTime(_ ms: Int64) -> Bool {
        ms > 0 && ms < androidFailureRespondTimeMs
    }

    /// Tokens that sit inside `bookSourceGroup` without being group names.
    ///
    /// Two sources of noise, both inherited from source JSON that circulates among Android users:
    ///
    /// 1. `CheckSourceService` treats the group column as scratch space while 校验书源 runs
    ///    (`source.addGroup("搜索失效")`), so a JSON exported right after a check carries its
    ///    verdicts as if they were groups — 11 literals, `${bookType}` being 搜索 / 发现.
    /// 2. `good`, a curatorial marker used by hand-maintained third-party source collections. It is
    ///    **not** a Legado construct: no Android or iOS code writes it, and Android's own bundled
    ///    `assets/defaultData/bookSources.json` uses 听书 for its single default source.
    ///
    /// Only exact matches are hidden: a bare 「失效」 is what *this* app's 校验 writes, and genuine
    /// categories such as 轻小说 are untouched.
    public static let groupNoiseTags: Set<String> = [
        // 1. Android 校验书源 verdicts
        "校验超时", "js失效", "网站失效",
        "搜索失效", "发现失效",
        "搜索目录失效", "发现目录失效",
        "搜索正文失效", "发现正文失效",
        "搜索链接规则为空", "发现规则为空",
        // 2. third-party curatorial marker
        "good"
    ]

    /// The source's categories as they should be **shown**; `nil` when only noise is left.
    ///
    /// Display-only by design. `bookSourceGroup` is Android-compatible data that has to round-trip
    /// verbatim through import/export, so the app filters at render time instead of rewriting the
    /// source: 校验 verdicts and the third-party `good` marker are hidden, every real category —
    /// including ones this app knows nothing about — is passed through untouched.
    public var displayGroup: String? {
        let kept = groups.filter { !Self.groupNoiseTags.contains($0) }
        return kept.isEmpty ? nil : kept.joined(separator: ",")
    }

    public enum CodingKeys: String, CodingKey {
        case bookSourceUrl
        case bookSourceName
        case bookSourceGroup
        case bookSourceType
        case bookUrlPattern
        case customOrder
        case enabled
        case enabledExplore
        case header
        case loginUrl
        case loginUi
        case loginCheckJs
        case coverDecodeJs
        case bookSourceComment
        case variableComment
        case lastUpdateTime
        case respondTime
        case weight
        case exploreUrl
        case exploreScreen
        case searchUrl
        case ruleExplore
        case ruleSearch
        case ruleBookInfo
        case ruleToc
        case ruleContent
        case loginInfo
        case loginHeader
        case variable
    }

    public init(
        bookSourceUrl: String,
        bookSourceName: String,
        bookSourceGroup: String? = nil,
        bookSourceType: Int? = 0,
        bookUrlPattern: String? = nil,
        customOrder: Int? = 0,
        enabled: Bool? = true,
        enabledExplore: Bool? = true,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        coverDecodeJs: String? = nil,
        bookSourceComment: String? = nil,
        variableComment: String? = nil,
        lastUpdateTime: Int64? = nil,
        respondTime: Int64? = nil,
        weight: Int? = 0,
        exploreUrl: String? = nil,
        exploreScreen: String? = nil,
        searchUrl: String? = nil,
        ruleExplore: ExploreRule? = nil,
        ruleSearch: SearchRule? = nil,
        ruleBookInfo: BookInfoRule? = nil,
        ruleToc: TocRule? = nil,
        ruleContent: ContentRule? = nil
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.bookUrlPattern = bookUrlPattern
        self.customOrder = customOrder
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.coverDecodeJs = coverDecodeJs
        self.bookSourceComment = bookSourceComment
        self.variableComment = variableComment
        self.lastUpdateTime = lastUpdateTime
        self.respondTime = respondTime
        self.weight = weight
        self.exploreUrl = exploreUrl
        self.exploreScreen = exploreScreen
        self.searchUrl = searchUrl
        self.ruleExplore = ruleExplore
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bookSourceUrl = try container.decodeIfPresent(String.self, forKey: .bookSourceUrl) ?? ""
        self.bookSourceName = try container.decodeIfPresent(String.self, forKey: .bookSourceName) ?? ""
        self.bookSourceGroup = try container.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        self.bookSourceType = try container.decodeIfPresent(Int.self, forKey: .bookSourceType)
        self.bookUrlPattern = try container.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        self.customOrder = try container.decodeIfPresent(Int.self, forKey: .customOrder)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        self.enabledExplore = try container.decodeIfPresent(Bool.self, forKey: .enabledExplore)
        self.header = try container.decodeIfPresent(String.self, forKey: .header)
        self.loginUrl = try container.decodeIfPresent(String.self, forKey: .loginUrl)
        self.loginUi = try container.decodeIfPresent(String.self, forKey: .loginUi)
        self.loginCheckJs = try container.decodeIfPresent(String.self, forKey: .loginCheckJs)
        self.coverDecodeJs = try container.decodeIfPresent(String.self, forKey: .coverDecodeJs)
        self.bookSourceComment = try container.decodeIfPresent(String.self, forKey: .bookSourceComment)
        self.variableComment = try container.decodeIfPresent(String.self, forKey: .variableComment)
        self.lastUpdateTime = try container.decodeIfPresent(Int64.self, forKey: .lastUpdateTime)
        self.respondTime = try container.decodeIfPresent(Int64.self, forKey: .respondTime)
        self.weight = try container.decodeIfPresent(Int.self, forKey: .weight)
        self.exploreUrl = try container.decodeIfPresent(String.self, forKey: .exploreUrl)
        self.exploreScreen = try container.decodeIfPresent(String.self, forKey: .exploreScreen)
        self.searchUrl = try container.decodeIfPresent(String.self, forKey: .searchUrl)

        self.ruleExplore = decodeRule(ExploreRule.self, from: container, forKey: .ruleExplore)
        self.ruleSearch = decodeRule(SearchRule.self, from: container, forKey: .ruleSearch)
        self.ruleBookInfo = decodeRule(BookInfoRule.self, from: container, forKey: .ruleBookInfo)
        self.ruleToc = decodeRule(TocRule.self, from: container, forKey: .ruleToc)
        self.ruleContent = decodeRule(ContentRule.self, from: container, forKey: .ruleContent)

        self.loginInfo = try container.decodeIfPresent(String.self, forKey: .loginInfo)
        self.loginHeader = try container.decodeIfPresent(String.self, forKey: .loginHeader)
        self.variable = try container.decodeIfPresent(String.self, forKey: .variable)
    }
}

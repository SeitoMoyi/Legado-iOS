import Foundation

public enum RuleSubscriptionError: LocalizedError {
    case invalidURL, duplicateURL, unsupportedType, invalidData, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的 HTTP 或 HTTPS 订阅地址"
        case .duplicateURL: return "此订阅地址已存在"
        case .unsupportedType: return "此订阅类型暂不支持导入，已保留原始配置"
        case .invalidData: return "订阅没有包含有效的对应规则"
        case .tooLarge: return "订阅超过大小限制"
        }
    }
}

public enum RuleSubStore {
    public static let key = "legado_rule_subscriptions_v1"
    public static func load(from defaults: UserDefaults = .standard) -> [RuleSub] {
        guard let data = defaults.data(forKey: key), let list = try? JSONDecoder().decode([RuleSub].self, from: data) else { return [] }
        return list.enumerated().sorted {
            $0.element.customOrder == $1.element.customOrder ? $0.offset < $1.offset : $0.element.customOrder < $1.element.customOrder
        }.map(\.element)
    }
    public static func save(_ list: [RuleSub], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }
    public static func upsert(_ value: RuleSub, into list: [RuleSub]) throws -> [RuleSub] {
        guard RuleSubscriptionService.validURL(value.url) != nil else { throw RuleSubscriptionError.invalidURL }
        guard !list.contains(where: { $0.url == value.url && $0.id != value.id }) else { throw RuleSubscriptionError.duplicateURL }
        var result = list
        if let index = result.firstIndex(where: { $0.id == value.id }) { result[index] = value }
        else {
            var newValue = value
            let highest = result.map(\.customOrder).max() ?? -1
            newValue.customOrder = highest == Int.max ? Int.max : highest + 1
            result.append(newValue)
        }
        return result
    }
    public static func merge(_ incoming: [RuleSub], into list: [RuleSub]) -> [RuleSub] {
        var result = list
        for value in incoming {
            if let index = result.firstIndex(where: { $0.id == value.id || $0.url == value.url }) { result[index] = value }
            else { result.append(value) }
        }
        return result
    }
}

public enum RuleSubscriptionPreview {
    case bookSources([BookSource])
    case rssSources([RssSource])
    case replaceRules([ReplaceRule])

    public var names: [String] {
        switch self {
        case .bookSources(let list): return list.map(\.bookSourceName)
        case .rssSources(let list): return list.map(\.sourceName)
        case .replaceRules(let list): return list.map(\.name)
        }
    }
}

public final class RuleSubscriptionService {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public static func validURL(_ string: String) -> URL? {
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public func fetch(_ subscription: RuleSub) async throws -> RuleSubscriptionPreview {
        try Task.checkCancellation()
        guard (0...2).contains(subscription.type) else { throw RuleSubscriptionError.unsupportedType }
        guard let url = Self.validURL(subscription.url) else { throw RuleSubscriptionError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WebDAVError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, "订阅下载失败")
        }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= BackupCompatibilityStore.maximumMemberSize else { throw RuleSubscriptionError.tooLarge }
        return try Self.preview(data: Data(contentsOf: file), type: subscription.type)
    }
    public static func preview(data: Data, type: Int) throws -> RuleSubscriptionPreview {
        guard data.count <= BackupCompatibilityStore.maximumMemberSize else { throw RuleSubscriptionError.tooLarge }
        switch type {
        case 0:
            guard let list = BookSource.decodeListOrObjectWithExtras(from: data), !list.isEmpty,
                  list.allSatisfy({ !$0.bookSourceUrl.isEmpty }) else { throw RuleSubscriptionError.invalidData }
            return .bookSources(list)
        case 1:
            guard let list = RssSource.decodeListOrObjectWithExtras(from: data), !list.isEmpty,
                  list.allSatisfy({ !$0.sourceUrl.isEmpty }) else { throw RuleSubscriptionError.invalidData }
            return .rssSources(list)
        case 2:
            guard let list = TolerantJSON.decodeList(ReplaceRule.self, from: data, fallback: ReplaceRule()),
                  !list.isEmpty, list.allSatisfy({ !$0.pattern.isEmpty }) else { throw RuleSubscriptionError.invalidData }
            return .replaceRules(list)
        default: throw RuleSubscriptionError.unsupportedType
        }
    }
}

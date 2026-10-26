import Foundation

/// Android RuleSub.kt. autoUpdate is metadata; the reference snapshot executes imports manually.
public struct RuleSub: Codable, Equatable, Identifiable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]
    public var id: Int64
    public var name: String
    public var url: String
    public var type: Int
    public var customOrder: Int
    public var autoUpdate: Bool
    public var update: Int64
    public init(id: Int64 = Int64(Date().timeIntervalSince1970 * 1000), name: String = "", url: String = "", type: Int = 0, customOrder: Int = 0, autoUpdate: Bool = false, update: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
        self.customOrder = customOrder
        self.autoUpdate = autoUpdate
        self.update = update
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case id, name, url, type, customOrder, autoUpdate, update }
    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? url
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? type
        customOrder = try c.decodeIfPresent(Int.self, forKey: .customOrder) ?? customOrder
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? autoUpdate
        update = try c.decodeIfPresent(Int64.self, forKey: .update) ?? update
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encode(type, forKey: .type)
        try c.encode(customOrder, forKey: .customOrder)
        try c.encode(autoUpdate, forKey: .autoUpdate)
        try c.encode(update, forKey: .update)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }
}

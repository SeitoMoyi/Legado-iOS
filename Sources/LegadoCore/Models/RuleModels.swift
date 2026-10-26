import Foundation

// MARK: - Helper for Flexible Object-or-String Decoding

public func decodeRule<T: Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<BookSource.CodingKeys>, forKey key: BookSource.CodingKeys) -> T? {
    if let object = try? container.decodeIfPresent(T.self, forKey: key) {
        return object
    }
    if let jsonString = try? container.decodeIfPresent(String.self, forKey: key),
       let data = jsonString.data(using: .utf8) {
        return try? JSONDecoder().decode(T.self, from: data)
    }
    return nil
}

// MARK: - SearchRule

public struct SearchRule: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        checkKeyWord: String? = nil,
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.checkKeyWord = checkKeyWord
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case checkKeyWord, bookList, name, author, intro, kind, lastChapter, updateTime, bookUrl, coverUrl, wordCount
    }

    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkKeyWord = try container.decodeIfPresent(String.self, forKey: .checkKeyWord)
        bookList = try container.decodeIfPresent(String.self, forKey: .bookList)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        bookUrl = try container.decodeIfPresent(String.self, forKey: .bookUrl)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        wordCount = try container.decodeIfPresent(String.self, forKey: .wordCount)
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(checkKeyWord, forKey: .checkKeyWord)
        try container.encodeIfPresent(bookList, forKey: .bookList)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(intro, forKey: .intro)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(lastChapter, forKey: .lastChapter)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(bookUrl, forKey: .bookUrl)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

// MARK: - ExploreRule

public struct ExploreRule: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case bookList, name, author, intro, kind, lastChapter, updateTime, bookUrl, coverUrl, wordCount
    }

    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookList = try container.decodeIfPresent(String.self, forKey: .bookList)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        bookUrl = try container.decodeIfPresent(String.self, forKey: .bookUrl)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        wordCount = try container.decodeIfPresent(String.self, forKey: .wordCount)
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(bookList, forKey: .bookList)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(intro, forKey: .intro)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(lastChapter, forKey: .lastChapter)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(bookUrl, forKey: .bookUrl)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

// MARK: - TocRule

public struct TocRule: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

    public var preUpdateJs: String?
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var formatJs: String?
    public var isVolume: String?
    public var isVip: String?
    public var isPay: String?
    public var updateTime: String?
    public var nextTocUrl: String?

    public init(
        preUpdateJs: String? = nil,
        chapterList: String? = nil,
        chapterName: String? = nil,
        chapterUrl: String? = nil,
        formatJs: String? = nil,
        isVolume: String? = nil,
        isVip: String? = nil,
        isPay: String? = nil,
        updateTime: String? = nil,
        nextTocUrl: String? = nil
    ) {
        self.preUpdateJs = preUpdateJs
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.formatJs = formatJs
        self.isVolume = isVolume
        self.isVip = isVip
        self.isPay = isPay
        self.updateTime = updateTime
        self.nextTocUrl = nextTocUrl
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case preUpdateJs, chapterList, chapterName, chapterUrl, formatJs, isVolume, isVip, isPay, updateTime, nextTocUrl
    }

    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preUpdateJs = try container.decodeIfPresent(String.self, forKey: .preUpdateJs)
        chapterList = try container.decodeIfPresent(String.self, forKey: .chapterList)
        chapterName = try container.decodeIfPresent(String.self, forKey: .chapterName)
        chapterUrl = try container.decodeIfPresent(String.self, forKey: .chapterUrl)
        formatJs = try container.decodeIfPresent(String.self, forKey: .formatJs)
        isVolume = try container.decodeIfPresent(String.self, forKey: .isVolume)
        isVip = try container.decodeIfPresent(String.self, forKey: .isVip)
        isPay = try container.decodeIfPresent(String.self, forKey: .isPay)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        nextTocUrl = try container.decodeIfPresent(String.self, forKey: .nextTocUrl)
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(preUpdateJs, forKey: .preUpdateJs)
        try container.encodeIfPresent(chapterList, forKey: .chapterList)
        try container.encodeIfPresent(chapterName, forKey: .chapterName)
        try container.encodeIfPresent(chapterUrl, forKey: .chapterUrl)
        try container.encodeIfPresent(formatJs, forKey: .formatJs)
        try container.encodeIfPresent(isVolume, forKey: .isVolume)
        try container.encodeIfPresent(isVip, forKey: .isVip)
        try container.encodeIfPresent(isPay, forKey: .isPay)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(nextTocUrl, forKey: .nextTocUrl)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

// MARK: - ContentRule

public struct ContentRule: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

    public var content: String?
    public var title: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
    public var imageStyle: String?
    public var imageDecode: String?
    public var payAction: String?

    public init(
        content: String? = nil,
        title: String? = nil,
        nextContentUrl: String? = nil,
        webJs: String? = nil,
        sourceRegex: String? = nil,
        replaceRegex: String? = nil,
        imageStyle: String? = nil,
        imageDecode: String? = nil,
        payAction: String? = nil
    ) {
        self.content = content
        self.title = title
        self.nextContentUrl = nextContentUrl
        self.webJs = webJs
        self.sourceRegex = sourceRegex
        self.replaceRegex = replaceRegex
        self.imageStyle = imageStyle
        self.imageDecode = imageDecode
        self.payAction = payAction
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case content, title, nextContentUrl, webJs, sourceRegex, replaceRegex, imageStyle, imageDecode, payAction
    }

    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        nextContentUrl = try container.decodeIfPresent(String.self, forKey: .nextContentUrl)
        webJs = try container.decodeIfPresent(String.self, forKey: .webJs)
        sourceRegex = try container.decodeIfPresent(String.self, forKey: .sourceRegex)
        replaceRegex = try container.decodeIfPresent(String.self, forKey: .replaceRegex)
        imageStyle = try container.decodeIfPresent(String.self, forKey: .imageStyle)
        imageDecode = try container.decodeIfPresent(String.self, forKey: .imageDecode)
        payAction = try container.decodeIfPresent(String.self, forKey: .payAction)
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(nextContentUrl, forKey: .nextContentUrl)
        try container.encodeIfPresent(webJs, forKey: .webJs)
        try container.encodeIfPresent(sourceRegex, forKey: .sourceRegex)
        try container.encodeIfPresent(replaceRegex, forKey: .replaceRegex)
        try container.encodeIfPresent(imageStyle, forKey: .imageStyle)
        try container.encodeIfPresent(imageDecode, forKey: .imageDecode)
        try container.encodeIfPresent(payAction, forKey: .payAction)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

// MARK: - BookInfoRule

public struct BookInfoRule: Codable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]

    public var initRule: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case initRule = "init"
        case name, author, intro, kind, lastChapter, updateTime, coverUrl, tocUrl, wordCount
    }

    private enum LegacyCodingKeys: String, CodingKey { case initRule }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        initRule = try container.decodeIfPresent(String.self, forKey: .initRule)
            ?? legacy.decodeIfPresent(String.self, forKey: .initRule)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        tocUrl = try container.decodeIfPresent(String.self, forKey: .tocUrl)
        wordCount = try container.decodeIfPresent(String.self, forKey: .wordCount)
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public init(
        initRule: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        coverUrl: String? = nil,
        tocUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.initRule = initRule
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.coverUrl = coverUrl
        self.tocUrl = tocUrl
        self.wordCount = wordCount
    }

    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue)).union(["initRule"])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(initRule, forKey: .initRule)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(intro, forKey: .intro)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(lastChapter, forKey: .lastChapter)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(tocUrl, forKey: .tocUrl)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

// MARK: - TxtTocRule (Android TxtTocRule.kt Counterpart)

public struct TxtTocRule: Codable, Identifiable, Equatable {
    public var id: Int64
    public var name: String
    public var rule: String
    public var example: String?
    public var serialNumber: Int
    public var enable: Bool

    public init(
        id: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        name: String = "",
        rule: String = "",
        example: String? = nil,
        serialNumber: Int = 0,
        enable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.example = example
        self.serialNumber = serialNumber
        self.enable = enable
    }
}

public enum TxtTocRuleStore {
    public static let key = "legado_txt_toc_rules_v1"

    public static let defaultRules: [TxtTocRule] = [
        TxtTocRule(id: 1, name: "标准章回节卷", rule: "^[\\s\\t]*(第[0-9一二三四五六七八九十百千]+[章回节卷].*)$", example: "第一章 初始", serialNumber: 0, enable: true),
        TxtTocRule(id: 2, name: "数字章节序号 (Chapter)", rule: "^[\\s\\t]*(Chapter\\s*\\d+.*)$", example: "Chapter 1", serialNumber: 1, enable: true),
        TxtTocRule(id: 3, name: "纯数字章节", rule: "^[\\s\\t]*(\\d+[\\.\\s、]+.*)$", example: "1. 启程", serialNumber: 2, enable: true),
        TxtTocRule(id: 4, name: "大写序号分卷", rule: "^[\\s\\t]*([【〔\\[]?第?[一二三四五六七八九十百]+[、卷部集].*)$", example: "第一卷 少年游", serialNumber: 3, enable: true)
    ]

    public static func load(from defaults: UserDefaults = .standard) -> [TxtTocRule] {
        guard let data = defaults.data(forKey: key) else {
            return defaultRules
        }
        let list = TolerantJSON.decodeList(TxtTocRule.self, from: data, fallback: TxtTocRule()) ?? []
        return list.isEmpty ? defaultRules : list
    }

    public static func save(_ rules: [TxtTocRule], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: key)
        }
    }

    public static func exportJSON(_ rules: [TxtTocRule]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func importJSON(_ json: String, into current: [TxtTocRule]) -> [TxtTocRule] {
        guard let data = json.data(using: .utf8) else { return current }
        var imported: [TxtTocRule] = []
        if let list = try? JSONDecoder().decode([TxtTocRule].self, from: data) {
            imported = list
        } else if let single = try? JSONDecoder().decode(TxtTocRule.self, from: data) {
            imported = [single]
        }
        guard !imported.isEmpty else { return current }
        var result = current
        for r in imported {
            if let idx = result.firstIndex(where: { $0.id == r.id || $0.name == r.name }) {
                result[idx] = r
            } else {
                result.append(r)
            }
        }
        return result
    }
}

// MARK: - ReadRecord (Android ReadRecord.kt Counterpart)

public struct ReadRecord: Codable, Identifiable, Equatable {
    public var id: String { "\(deviceId)_\(bookName)" }
    public var deviceId: String
    public var bookName: String
    public var readTime: Int64 // milliseconds
    public var lastRead: Int64 // timestamp

    public init(
        deviceId: String = "iOS",
        bookName: String = "",
        readTime: Int64 = 0,
        lastRead: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.deviceId = deviceId
        self.bookName = bookName
        self.readTime = readTime
        self.lastRead = lastRead
    }
}

public enum ReadRecordStore {
    public static let key = "legado_read_record_v1"

    public static func load(from defaults: UserDefaults = .standard) -> [ReadRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return TolerantJSON.decodeList(ReadRecord.self, from: data, fallback: ReadRecord()) ?? []
    }

    public static func save(_ records: [ReadRecord], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }

    public static func addDuration(bookName: String, durationMs: Int64, defaults: UserDefaults = .standard) {
        let name = bookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, durationMs > 0 else { return }
        var records = load(from: defaults)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let idx = records.firstIndex(where: { $0.bookName == name }) {
            records[idx].readTime += durationMs
            records[idx].lastRead = now
        } else {
            records.append(ReadRecord(bookName: name, readTime: durationMs, lastRead: now))
        }
        save(records, to: defaults)
    }
}

// MARK: - DictRule (Android DictRule.kt Counterpart)

public struct DictRule: Codable, Identifiable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]
    public var id: String { name }
    public var name: String
    public var urlRule: String
    public var showRule: String
    public var enabled: Bool
    public var sortNumber: Int

    public init(
        name: String = "",
        urlRule: String = "",
        showRule: String = "",
        enabled: Bool = true,
        sortNumber: Int = 0
    ) {
        self.name = name
        self.urlRule = urlRule
        self.showRule = showRule
        self.enabled = enabled
        self.sortNumber = sortNumber
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case name, urlRule, showRule, enabled, sortNumber }
    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        urlRule = try container.decodeIfPresent(String.self, forKey: .urlRule) ?? ""
        showRule = try container.decodeIfPresent(String.self, forKey: .showRule) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sortNumber = try container.decodeIfPresent(Int.self, forKey: .sortNumber) ?? 0
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(urlRule, forKey: .urlRule)
        try container.encode(showRule, forKey: .showRule)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(sortNumber, forKey: .sortNumber)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

public enum DictRuleStore {
    public static let key = "legado_dict_rules_v1"

    public static let defaultRules: [DictRule] = [
        DictRule(
            name: "百度汉语",
            urlRule: "https://dict.baidu.com/s?wd={{key}}",
            showRule: "class.tab-content@html || class.word-details@html || body@text",
            enabled: true,
            sortNumber: 0
        ),
        DictRule(
            name: "汉典",
            urlRule: "https://www.zdic.net/hans/{{key}}",
            showRule: "class.content@html || body@text",
            enabled: true,
            sortNumber: 1
        )
    ]

    public static func load(from defaults: UserDefaults = .standard) -> [DictRule] {
        guard let data = defaults.data(forKey: key) else {
            return defaultRules
        }
        return TolerantJSON.decodeList(DictRule.self, from: data, fallback: DictRule()) ?? defaultRules
    }

    public static func save(_ rules: [DictRule], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: key)
        }
    }

    public static func exportJSON(_ rules: [DictRule]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func importJSON(_ json: String, into current: [DictRule]) -> [DictRule] {
        guard let data = json.data(using: .utf8) else { return current }
        var imported: [DictRule] = []
        if let list = try? JSONDecoder().decode([DictRule].self, from: data) {
            imported = list
        } else if let single = try? JSONDecoder().decode(DictRule.self, from: data) {
            imported = [single]
        }
        guard !imported.isEmpty else { return current }
        var result = current
        for r in imported {
            if let idx = result.firstIndex(where: { $0.name == r.name }) {
                result[idx] = r
            } else {
                result.append(r)
            }
        }
        return result
    }
}

// MARK: - HttpTTS (Android HttpTTS.kt Counterpart)

public struct HttpTTS: Codable, Identifiable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]
    public var id: Int64
    public var name: String
    public var url: String
    public var contentType: String?
    public var concurrentRate: String?
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    public var enabled: Bool

    public init(
        id: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        name: String = "",
        url: String = "",
        contentType: String? = "audio/mpeg",
        concurrentRate: String? = "0",
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.contentType = contentType
        self.concurrentRate = concurrentRate
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.enabled = enabled
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case id, name, url, contentType, concurrentRate, header, loginUrl, loginUi, loginCheckJs, enabled }
    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id) ?? Int64(Date().timeIntervalSince1970 * 1000)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        concurrentRate = try container.decodeIfPresent(String.self, forKey: .concurrentRate)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        loginUrl = try container.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi = try container.decodeIfPresent(String.self, forKey: .loginUi)
        loginCheckJs = try container.decodeIfPresent(String.self, forKey: .loginCheckJs)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(concurrentRate, forKey: .concurrentRate)
        try container.encodeIfPresent(header, forKey: .header)
        try container.encodeIfPresent(loginUrl, forKey: .loginUrl)
        try container.encodeIfPresent(loginUi, forKey: .loginUi)
        try container.encodeIfPresent(loginCheckJs, forKey: .loginCheckJs)
        try container.encode(enabled, forKey: .enabled)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

public enum HttpTTSStore {
    public static let key = "legado_http_tts_v1"

    /// System speech is a virtual UI choice, not an Android HttpTTS database row.
    public static let defaultEngines: [HttpTTS] = []

    public static func engine(id: Int64?, in engines: [HttpTTS]) -> HttpTTS? {
        guard let id = id else { return nil }
        return engines.first { $0.id == id && $0.enabled && $0.contentType != "system" }
    }

    private static func normalized(_ engines: [HttpTTS]) -> [HttpTTS] {
        var result: [HttpTTS] = []
        for engine in engines where engine.contentType != "system" {
            if let index = result.firstIndex(where: { $0.id == engine.id }) { result[index] = engine }
            else { result.append(engine) }
        }
        return result
    }

    public static func load(from defaults: UserDefaults = .standard) -> [HttpTTS] {
        guard let data = defaults.data(forKey: key) else {
            return defaultEngines
        }
        return normalized(TolerantJSON.decodeList(HttpTTS.self, from: data, fallback: HttpTTS()) ?? defaultEngines)
    }

    public static func save(_ engines: [HttpTTS], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized(engines)) { defaults.set(data, forKey: key) }
    }

    public static func exportJSON(_ engines: [HttpTTS]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(normalized(engines)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func importJSON(_ json: String, into current: [HttpTTS]) -> [HttpTTS] {
        guard let data = json.data(using: .utf8) else { return current }
        var imported: [HttpTTS] = []
        if let list = try? JSONDecoder().decode([HttpTTS].self, from: data) {
            imported = list
        } else if let single = try? JSONDecoder().decode(HttpTTS.self, from: data) {
            imported = [single]
        }
        guard !imported.isEmpty else { return current }
        var result = normalized(current)
        for item in normalized(imported) {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                result[idx] = item
            } else {
                result.append(item)
            }
        }
        return result
    }
}

// MARK: - BookGroup (Android BookGroup.kt Counterpart)

public struct BookGroup: Codable, Identifiable, Equatable, JSONExtraPreserving {
    public var extra: [String: JSONValue] = [:]
    public var id: Int64 { groupId }
    public var groupId: Int64
    public var groupName: String
    public var cover: String?
    public var order: Int
    public var enableRefresh: Bool
    public var show: Bool
    public var bookSort: Int

    public static let idRoot: Int64 = -100
    public static let idAll: Int64 = -1
    public static let idLocal: Int64 = -2
    public static let idAudio: Int64 = -3
    public static let idNetNone: Int64 = -4
    public static let idLocalNone: Int64 = -5
    /// iOS-only virtual group: every book that came from a network book source.
    ///
    /// Android answers this with 「网络未分组」 plus per-group rows; iOS keeps one basket, so the
    /// shelf offers 全部 / 书源书籍 / 本地书籍 and filters by `Book.isLocalBook`.
    public static let idNet: Int64 = -6
    public static let idError: Int64 = -11

    public init(
        groupId: Int64 = 1,
        groupName: String = "",
        cover: String? = nil,
        order: Int = 0,
        enableRefresh: Bool = true,
        show: Bool = true,
        bookSort: Int = -1
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.cover = cover
        self.order = order
        self.enableRefresh = enableRefresh
        self.show = show
        self.bookSort = bookSort
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case groupId, groupName, cover, order, enableRefresh, show, bookSort }
    public static let modeledJSONKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.decodeIfPresent(Int64.self, forKey: .groupId) ?? 1
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        enableRefresh = try container.decodeIfPresent(Bool.self, forKey: .enableRefresh) ?? true
        show = try container.decodeIfPresent(Bool.self, forKey: .show) ?? true
        bookSort = try container.decodeIfPresent(Int.self, forKey: .bookSort) ?? -1
        extra = try decodeJSONExtras(from: decoder, excluding: Self.modeledJSONKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(groupName, forKey: .groupName)
        try container.encodeIfPresent(cover, forKey: .cover)
        try container.encode(order, forKey: .order)
        try container.encode(enableRefresh, forKey: .enableRefresh)
        try container.encode(show, forKey: .show)
        try container.encode(bookSort, forKey: .bookSort)
        try encodeJSONExtras(extra.filter { !Self.modeledJSONKeys.contains($0.key) }, to: encoder)
    }

}

public enum BookGroupStore {
    public static let key = "legado_book_groups_v2"
    public static let bitmaskVersionKey = "legado_book_groups_bitmask_v1"
    public static let migrationKey = "legado_book_groups_pending_migration_v1"
    public static let legacyIDsKey = "legado_book_groups_legacy_ids_v1"

    /// v1 shipped 「养肥中」/「已完结」 as the two seed groups; they are gone, so any persisted copy
    /// is migrated away instead of lingering on the shelf tabs.
    private static let legacyKey = "legado_book_groups_v1"

    public static let defaultGroups: [BookGroup] = [
        BookGroup(groupId: BookGroup.idAll, groupName: "全部", order: 0),
        BookGroup(groupId: BookGroup.idNet, groupName: "书源书籍", order: 1),
        BookGroup(groupId: BookGroup.idLocal, groupName: "本地书籍", order: 2)
    ]

    /// Groups that older builds seeded and that nothing should own any more. Compared by id *and*
    /// name so a user-created group that happens to be called 养肥中 is left alone.
    private static func isRetiredDefault(_ group: BookGroup) -> Bool {
        (group.groupId == 1 && group.groupName == "养肥中")
            || (group.groupId == 2 && group.groupName == "已完结")
    }

    public static func load(from defaults: UserDefaults = .standard) -> [BookGroup] {
        if let data = defaults.data(forKey: key),
           let list = TolerantJSON.decodeList(BookGroup.self, from: data, fallback: BookGroup()),
           !list.isEmpty {
            return normalized(list, persistedIn: defaults, alreadyStored: true)
        }

        if let legacy = defaults.data(forKey: legacyKey) {
            defaults.removeObject(forKey: legacyKey)
            if let list = TolerantJSON.decodeList(BookGroup.self, from: legacy, fallback: BookGroup()),
               !list.isEmpty {
                return normalized(list, persistedIn: defaults, alreadyStored: false)
            }
        }

        return defaultGroups
    }

    /// Drops retired seed groups and guarantees the three virtual groups exist, in shelf order and
    /// without disturbing user-created groups. Writes back only when something actually changed.
    private static func normalized(
        _ groups: [BookGroup],
        persistedIn defaults: UserDefaults,
        alreadyStored: Bool
    ) -> [BookGroup] {
        var result = defaults.bool(forKey: bitmaskVersionKey) ? groups : groups.filter { !isRetiredDefault($0) }

        if !result.contains(where: { $0.groupId == BookGroup.idAll }) {
            result.insert(defaultGroups[0], at: 0)
        }
        if !result.contains(where: { $0.groupId == BookGroup.idNet }) {
            result.insert(defaultGroups[1], at: min(1, result.count))
        }
        if !result.contains(where: { $0.groupId == BookGroup.idLocal }) {
            result.append(defaultGroups[2])
        }

        result = result.enumerated().sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.map(\.element)
        if !alreadyStored || result != groups {
            save(result, to: defaults)
        }
        return result
    }

    public static func save(_ groups: [BookGroup], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(groups) {
            defaults.set(data, forKey: key)
        }
    }

    public static func exportJSON(_ groups: [BookGroup]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(groups) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func importJSON(_ json: String, into current: [BookGroup]) -> [BookGroup] {
        guard let data = json.data(using: .utf8) else { return current }
        var imported: [BookGroup] = []
        if let list = try? JSONDecoder().decode([BookGroup].self, from: data) {
            imported = list
        } else if let single = try? JSONDecoder().decode(BookGroup.self, from: data) {
            imported = [single]
        }
        guard !imported.isEmpty else { return current }
        return (try? BookGroupCompatibility.mergeAndroid(groups: imported, books: [], into: current).groups) ?? current
    }
}

/// Which books a bookshelf tab shows.
///
/// Android resolves the virtual group ids inside `BookDao.flowGroupBooks`; iOS keeps the same idea in
/// one place so the 书架 view stays a pure rendering layer and the rule can be exercised directly.
public enum ShelfFilter {
    public static func books(_ books: [Book], inGroup groupId: Int64,
                             groups: [BookGroup] = BookGroupStore.load(), legacyAssignments: Bool = false) -> [Book] {
        let visible = books.filter { $0.androidType & AndroidBookType.notShelf == 0 }
        let knownMask = groups.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
        switch groupId {
        case BookGroup.idAll: return visible
        case BookGroup.idLocal: return visible.filter { $0.isLocalBook }
        case BookGroup.idNet: return visible.filter { !$0.isLocalBook }
        case BookGroup.idAudio: return visible.filter { $0.isAudioBook }
        case BookGroup.idError: return visible.filter { $0.androidType & AndroidBookType.updateError != 0 }
        case BookGroup.idNetNone: return visible.filter { !$0.isLocalBook && !$0.isAudioBook && $0.group & knownMask == 0 }
        case BookGroup.idLocalNone: return visible.filter { $0.isLocalBook && $0.group & knownMask == 0 }
        case BookGroup.idRoot:
            guard !groups.contains(where: { $0.groupId == BookGroup.idNetNone && $0.show }) else { return [] }
            return visible.filter { !$0.isLocalBook && !$0.isAudioBook && ($0.androidType == 0 || $0.androidType & AndroidBookType.text != 0) && $0.group & knownMask == 0 }
        default:
            guard groupId > 0 else { return [] }
            return visible.filter { legacyAssignments ? $0.group == groupId : ($0.group > 0 && $0.group & groupId != 0) }
        }
    }
}

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

public struct SearchRule: Codable, Equatable {
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
}

// MARK: - ExploreRule

public struct ExploreRule: Codable, Equatable {
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
}

// MARK: - TocRule

public struct TocRule: Codable, Equatable {
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
}

// MARK: - ContentRule

public struct ContentRule: Codable, Equatable {
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
}

// MARK: - BookInfoRule

public struct BookInfoRule: Codable, Equatable {
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

public struct DictRule: Codable, Identifiable, Equatable {
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
        let list = TolerantJSON.decodeList(DictRule.self, from: data, fallback: DictRule()) ?? []
        return list.isEmpty ? defaultRules : list
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

public struct HttpTTS: Codable, Identifiable, Equatable {
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
}

public enum HttpTTSStore {
    public static let key = "legado_http_tts_v1"

    public static let defaultEngines: [HttpTTS] = [
        HttpTTS(
            id: 1,
            name: "系统原生 TTS (本地离线)",
            url: "",
            contentType: "system",
            enabled: true
        )
    ]

    public static func load(from defaults: UserDefaults = .standard) -> [HttpTTS] {
        guard let data = defaults.data(forKey: key) else {
            return defaultEngines
        }
        let list = TolerantJSON.decodeList(HttpTTS.self, from: data, fallback: HttpTTS()) ?? []
        return list.isEmpty ? defaultEngines : list
    }

    public static func save(_ engines: [HttpTTS], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(engines) {
            defaults.set(data, forKey: key)
        }
    }

    public static func exportJSON(_ engines: [HttpTTS]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(engines) else { return nil }
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
        var result = current
        for item in imported {
            if let idx = result.firstIndex(where: { $0.id == item.id || $0.name == item.name }) {
                result[idx] = item
            } else {
                result.append(item)
            }
        }
        return result
    }
}

// MARK: - BookGroup (Android BookGroup.kt Counterpart)

public struct BookGroup: Codable, Identifiable, Equatable {
    public var id: Int64 { groupId }
    public var groupId: Int64
    public var groupName: String
    public var cover: String?
    public var order: Int
    public var enableRefresh: Bool
    public var show: Bool
    public var bookSort: Int

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
}

public enum BookGroupStore {
    public static let key = "legado_book_groups_v2"

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
        var result = groups.filter { !isRetiredDefault($0) }

        if !result.contains(where: { $0.groupId == BookGroup.idAll }) {
            result.insert(defaultGroups[0], at: 0)
        }
        if !result.contains(where: { $0.groupId == BookGroup.idNet }) {
            result.insert(defaultGroups[1], at: min(1, result.count))
        }
        if !result.contains(where: { $0.groupId == BookGroup.idLocal }) {
            result.append(defaultGroups[2])
        }

        if !alreadyStored || result.count != groups.count {
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
        var result = current
        for item in imported {
            if let idx = result.firstIndex(where: { $0.groupId == item.groupId || $0.groupName == item.groupName }) {
                result[idx] = item
            } else {
                result.append(item)
            }
        }
        return result
    }
}

/// Which books a bookshelf tab shows.
///
/// Android resolves the virtual group ids inside `BookDao.flowGroupBooks`; iOS keeps the same idea in
/// one place so the 书架 view stays a pure rendering layer and the rule can be exercised directly.
public enum ShelfFilter {
    public static func books(_ books: [Book], inGroup groupId: Int64) -> [Book] {
        switch groupId {
        case BookGroup.idAll:
            return books
        case BookGroup.idLocal:
            return books.filter { $0.isLocalBook }
        case BookGroup.idNet:
            return books.filter { !$0.isLocalBook }
        default:
            return books.filter { $0.group == groupId }
        }
    }
}

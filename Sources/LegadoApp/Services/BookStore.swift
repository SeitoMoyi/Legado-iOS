import Foundation
#if canImport(LegadoCore)
import LegadoCore
#endif

public class BookStore: ObservableObject {
    public static let shared = BookStore()

    @Published public var bookshelf: [Book] = []
    @Published public var sources: [BookSource] = []
    @Published public var replaceRules: [ReplaceRule] = []
    @Published public var bookmarks: [Bookmark] = []
    @Published public var searchHistory: [SearchKeyword] = []
    @Published public private(set) var groupMigrationIssue: String?
    public var usesGroupBitmasks: Bool { defaults.bool(forKey: BookGroupStore.bitmaskVersionKey) }

    private let defaults: UserDefaults
    private let booksKey = "legado_bookshelf_v1"
    private let sourcesKey = "legado_sources_v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadData()
        bindContentProcessor()
    }

    /// Keeps the core pipeline pointed at the live rule list and lets a rule that times out
    /// disable itself here rather than in the core layer.
    private func bindContentProcessor() {
        ContentProcessor.shared.rules = replaceRules
        ContentProcessor.shared.onRuleAutoDisabled = { [weak self] disabled in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let index = self.replaceRules.firstIndex(where: { $0.id == disabled.id }) else { return }
                self.replaceRules[index].isEnabled = false
                self.saveReplaceRules()
            }
        }
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func loadData() {
        // Load sources (element-wise tolerant decode keeps undeclared Android fields in `extra`)
        if let decodedSources = BookSource.decodeListWithExtras(
            from: defaults.data(forKey: sourcesKey) ?? Data()) {
            self.sources = decodedSources
        }

        replaceRules = ReplaceRuleStore.load(from: defaults)
        bookmarks = BookmarkStore.load(from: defaults)
        searchHistory = SearchHistoryStore.load(from: defaults)

        // Load bookshelf
        if let decodedBooks = Book.decodeListWithExtras(
            from: defaults.data(forKey: booksKey) ?? Data()) {
            self.bookshelf = decodedBooks
        }
        migrateBookGroupsIfNeeded()
    }

    private func commitGroupMigration(_ migration: BookGroupCompatibility.Migration) {
        BookGroupStore.save(migration.groups, to: defaults)
        bookshelf = migration.books
        saveBookshelf()
        if let data = try? JSONEncoder().encode(migration.legacyIDs) { defaults.set(data, forKey: BookGroupStore.legacyIDsKey) }
        defaults.set(true, forKey: BookGroupStore.bitmaskVersionKey)
        defaults.removeObject(forKey: BookGroupStore.migrationKey)
        groupMigrationIssue = nil
    }

    private func migrateBookGroupsIfNeeded() {
        do {
            // Recover the complete snapshot if the app stopped between the individual
            // defaults writes. Never reinterpret half-migrated bitmasks as old IDs.
            if let pending = defaults.data(forKey: BookGroupStore.migrationKey) {
                commitGroupMigration(try JSONDecoder().decode(BookGroupCompatibility.Migration.self, from: pending))
                return
            }
            guard !usesGroupBitmasks else { return }
            let migration = try BookGroupCompatibility.migrateLegacy(groups: BookGroupStore.load(from: defaults), books: bookshelf)
            defaults.set(try JSONEncoder().encode(migration), forKey: BookGroupStore.migrationKey)
            commitGroupMigration(migration)
        } catch { groupMigrationIssue = error.localizedDescription }
    }

    @discardableResult
    public func addBookGroup(name: String, enableRefresh: Bool = true) throws -> BookGroup {
        guard usesGroupBitmasks else { throw BookGroupCompatibilityError.capacity }
        var groups = BookGroupStore.load(from: defaults)
        guard let id = BookGroupCompatibility.nextIdentifier(in: groups) else { throw BookGroupCompatibilityError.capacity }
        let lastOrder = groups.map(\.order).max() ?? -1
        let nextOrder = lastOrder < Int.max ? lastOrder + 1 : lastOrder
        let group = BookGroup(groupId: id, groupName: name.trimmingCharacters(in: .whitespacesAndNewlines), order: nextOrder, enableRefresh: enableRefresh)
        guard !group.groupName.isEmpty else { throw BookGroupCompatibilityError.invalidName }
        groups.append(group)
        BookGroupStore.save(groups, to: defaults)
        objectWillChange.send()
        return group
    }

    public func renameBookGroup(id: Int64, name: String, enableRefresh: Bool? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var groups = BookGroupStore.load(from: defaults)
        guard let index = groups.firstIndex(where: { $0.groupId == id }) else { return }
        groups[index].groupName = name
        if let enableRefresh = enableRefresh { groups[index].enableRefresh = enableRefresh }
        BookGroupStore.save(groups, to: defaults)
        objectWillChange.send()
    }

    public func deleteBookGroups(_ ids: Set<Int64>) {
        let ids = ids.filter { $0 > 0 }
        guard !ids.isEmpty else { return }
        var groups = BookGroupStore.load(from: defaults)
        groups.removeAll { ids.contains($0.groupId) }
        let removed = ids.reduce(Int64(0), |)
        for index in bookshelf.indices {
            if usesGroupBitmasks { bookshelf[index].group &= ~removed }
            else if ids.contains(bookshelf[index].group) { bookshelf[index].group = 0 }
        }
        if let data = defaults.data(forKey: BookGroupStore.legacyIDsKey),
           var map = try? JSONDecoder().decode([String: Int64].self, from: data) {
            for key in map.keys where ids.contains(map[key] ?? 0) { map[key] = 0 }
            if let updated = try? JSONEncoder().encode(map) { defaults.set(updated, forKey: BookGroupStore.legacyIDsKey) }
        }
        BookGroupStore.save(groups, to: defaults)
        saveBookshelf()
        migrateBookGroupsIfNeeded()
        objectWillChange.send()
    }

    public func saveSources() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: sourcesKey)
        }
    }

    public func saveBookshelf() {
        if let data = try? JSONEncoder().encode(bookshelf) {
            defaults.set(data, forKey: booksKey)
        }
    }

    // MARK: - 替换净化 Rules

    public func saveReplaceRules() {
        ReplaceRuleStore.save(replaceRules, to: defaults)
        ContentProcessor.shared.rules = replaceRules
    }

    /// Adds or replaces by id, keeping the list ordered by `order`.
    public func upsertReplaceRule(_ rule: ReplaceRule) {
        if let index = replaceRules.firstIndex(where: { $0.id == rule.id }) {
            replaceRules[index] = rule
        } else {
            replaceRules.append(rule)
        }
        replaceRules.sort { $0.order < $1.order }
        saveReplaceRules()
    }

    public func deleteReplaceRule(id: Int64) {
        replaceRules.removeAll { $0.id == id }
        saveReplaceRules()
    }

    public func setReplaceRule(_ id: Int64, enabled: Bool) {
        guard let index = replaceRules.firstIndex(where: { $0.id == id }) else { return }
        replaceRules[index].isEnabled = enabled
        saveReplaceRules()
    }

    public func moveReplaceRule(from source: IndexSet, to destination: Int) {
        replaceRules.move(fromOffsets: source, toOffset: destination)
        for index in replaceRules.indices { replaceRules[index].order = index }
        saveReplaceRules()
    }

    /// Imports an Android `replaceRule.json` array.
    public func importReplaceRules(json: String) -> Int {
        let before = replaceRules.count
        replaceRules = ReplaceRuleStore.importJSON(json, into: replaceRules)
        saveReplaceRules()
        return replaceRules.count - before
    }

    public func exportReplaceRulesJSON() -> String? {
        ReplaceRuleStore.exportJSON(replaceRules)
    }

    /// The rules that currently apply to a book, for the 「起效的替换」 list.
    public func matchingReplaceRules(bookName: String, bookOrigin: String, forTitle: Bool = false) -> [ReplaceRule] {
        ContentProcessor.matchingRules(bookName: bookName, bookOrigin: bookOrigin,
                                       from: replaceRules, forTitle: forTitle)
    }

    // MARK: - 书签

    public func saveBookmarks() {
        BookmarkStore.save(bookmarks, to: defaults)
    }

    public func addBookmark(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
        bookmarks = BookmarkStore.sorted(bookmarks)
        saveBookmarks()
    }

    public func updateBookmark(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.time == bookmark.time }) else {
            addBookmark(bookmark)
            return
        }
        bookmarks[index] = bookmark
        bookmarks = BookmarkStore.sorted(bookmarks)
        saveBookmarks()
    }

    public func deleteBookmark(time: Int64) {
        bookmarks.removeAll { $0.time == time }
        saveBookmarks()
    }

    /// Scoped by name + author, which is how Android links bookmarks to books and what keeps
    /// them alive across 换源.
    public func bookmarks(for book: Book) -> [Bookmark] {
        BookmarkStore.sorted(bookmarks.filter { $0.bookKey == Bookmark.key(bookName: book.name, bookAuthor: book.author) })
    }

    public func searchBookmarks(book: Book, keyword: String) -> [Bookmark] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoped = bookmarks(for: book)
        guard !needle.isEmpty else { return scoped }
        return scoped.filter {
            $0.chapterName.localizedCaseInsensitiveContains(needle)
                || $0.content.localizedCaseInsensitiveContains(needle)
                || $0.bookText.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Merges restored WebDAV books and sources into local storage
    public func restoreFromWebDAV(books: [Book]?, sources: [BookSource]?) throws -> (booksAdded: Int, sourcesAdded: Int) {
        let res = try restoreBackupPayload(WebDAVService.BackupRestorePayload(books: books, sources: sources))
        return (res.booksAdded, res.sourcesAdded)
    }

    /// Merges a full `BackupRestorePayload` (books, sources, bookmarks, replaceRules, searchHistory, readConfig) into local storage.
    @discardableResult
    public func restoreBackupPayload(_ payload: WebDAVService.BackupRestorePayload) throws -> (booksAdded: Int, sourcesAdded: Int, bookmarksAdded: Int, rulesAdded: Int) {
        var booksCount = 0
        var sourcesCount = 0
        var bookmarksCount = 0
        var rulesCount = 0

        var incomingBooks = payload.books
        if payload.books != nil || payload.bookGroups != nil {
            guard usesGroupBitmasks else { throw BookGroupCompatibilityError.capacity }
            let currentGroups = BookGroupStore.load(from: defaults)
            if payload.bookGroups == nil, let data = defaults.data(forKey: BookGroupStore.legacyIDsKey),
               let mapping = try? JSONDecoder().decode([String: Int64].self, from: data) {
                incomingBooks = incomingBooks?.map { original in
                    var book = original; book.group = mapping[String(original.group)] ?? original.group; return book
                }
            }
            let mask = (incomingBooks ?? []).filter { $0.group > 0 }.reduce(Int64(0)) { $0 | $1.group }
            let definitions: [BookGroup] = payload.bookGroups ?? (currentGroups.filter { $0.groupId > 0 && ($0.groupId & mask) != 0 })
            let merged = try BookGroupCompatibility.mergeAndroid(groups: definitions, books: incomingBooks ?? [], into: currentGroups)
            BookGroupStore.save(merged.groups, to: defaults)
            if payload.books != nil { incomingBooks = merged.books }
        }

        if let newBooks = incomingBooks {
            for b in newBooks {
                if let idx = bookshelf.firstIndex(where: { $0.bookUrl == b.bookUrl }) {
                    var progress = BookProgress(book: bookshelf[idx])
                    // URL identifies this shelf entry even when restored metadata renames it.
                    progress.name = b.name
                    progress.author = b.author
                    bookshelf[idx] = progress.applying(to: b)
                } else {
                    bookshelf.append(b)
                    booksCount += 1
                }
            }
            saveBookshelf()
        }

        if let newSources = payload.sources {
            for s in newSources {
                if let idx = self.sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) {
                    self.sources[idx] = s
                } else {
                    self.sources.append(s)
                    sourcesCount += 1
                }
            }
            saveSources()
        }

        if let newBookmarks = payload.bookmarks, !newBookmarks.isEmpty {
            let before = bookmarks.count
            var map = Dictionary(bookmarks.map { ($0.time, $0) }, uniquingKeysWith: { _, newest in newest })
            for bm in newBookmarks {
                map[bm.time] = bm
            }
            bookmarks = BookmarkStore.sorted(Array(map.values))
            bookmarksCount = max(0, bookmarks.count - before)
            saveBookmarks()
        }

        if let newRules = payload.replaceRules, !newRules.isEmpty {
            let before = replaceRules.count
            for r in newRules {
                if let idx = replaceRules.firstIndex(where: { $0.id == r.id || ($0.name == r.name && $0.pattern == r.pattern) }) {
                    replaceRules[idx] = r
                } else {
                    replaceRules.append(r)
                }
            }
            rulesCount = max(0, replaceRules.count - before)
            saveReplaceRules()
        }

        if let newHistory = payload.searchHistory, !newHistory.isEmpty {
            var merged = searchHistory
            for kw in newHistory {
                if let idx = merged.firstIndex(where: { $0.word == kw.word }) {
                    merged[idx].usage = max(merged[idx].usage, kw.usage)
                    merged[idx].lastUseTime = max(merged[idx].lastUseTime, kw.lastUseTime)
                } else {
                    merged.append(kw)
                }
            }
            searchHistory = merged
            saveSearchHistory()
        }
        if let style = payload.readConfig {
            ReaderStore.save(style, to: defaults)
        }
        if let dictionaries = payload.dictRules {
            let json = String(decoding: try JSONEncoder().encode(dictionaries), as: UTF8.self)
            DictRuleStore.save(DictRuleStore.importJSON(json, into: DictRuleStore.load(from: defaults)), to: defaults)
        }
        if let engines = payload.httpTTS {
            var current = HttpTTSStore.load(from: defaults)
            for engine in engines {
                if let index = current.firstIndex(where: { $0.id == engine.id && $0.contentType != "system" }) { current[index] = engine }
                else { current.append(engine) }
            }
            HttpTTSStore.save(current, to: defaults)
        }

        if let newTxtRules = payload.txtTocRules, !newTxtRules.isEmpty {
            let currentRules = TxtTocRuleStore.load(from: defaults)
            var merged = currentRules
            for r in newTxtRules {
                if let idx = merged.firstIndex(where: { $0.id == r.id || $0.name == r.name }) {
                    merged[idx] = r
                } else {
                    merged.append(r)
                }
            }
            TxtTocRuleStore.save(merged, to: defaults)
        }

        if let newRecords = payload.readRecords, !newRecords.isEmpty {
            let currentRecords = ReadRecordStore.load(from: defaults)
            var merged = currentRecords
            for rec in newRecords {
                if let idx = merged.firstIndex(where: { $0.deviceId == rec.deviceId && $0.bookName == rec.bookName }) {
                    merged[idx].readTime = max(merged[idx].readTime, rec.readTime)
                    merged[idx].lastRead = max(merged[idx].lastRead, rec.lastRead)
                } else {
                    merged.append(rec)
                }
            }
            ReadRecordStore.save(merged, to: defaults)
        }

        if let newRssSources = payload.rssSources, !newRssSources.isEmpty {
            let current = RssStore.loadSources(from: defaults)
            var merged = current
            for s in newRssSources {
                if let idx = merged.firstIndex(where: { $0.sourceUrl == s.sourceUrl }) {
                    merged[idx] = s
                } else {
                    merged.append(s)
                }
            }
            RssStore.saveSources(merged, to: defaults)
        }

        if let newRssStars = payload.rssStars, !newRssStars.isEmpty {
            let current = RssStore.loadStars(from: defaults)
            var merged = current
            for star in newRssStars {
                if !merged.contains(where: { $0.link == star.link }) {
                    merged.append(star)
                }
            }
            RssStore.saveStars(merged, to: defaults)
        }

        return (booksCount, sourcesCount, bookmarksCount, rulesCount)
    }


    @discardableResult
    public func saveOrUpdateBook(_ book: Book) -> Book {
        if let index = bookshelf.firstIndex(where: { $0.bookUrl == book.bookUrl }) {
            var existing = bookshelf[index]
            // Merge policy mirrors Android `BookInfoViewModel.upBookInfo`: the fetched detail
            // overwrites display metadata wholesale (identity is bookUrl, so renaming is safe);
            // reading progress fields are owned by the shelf copy.
            if !book.name.isEmpty { existing.name = book.name }
            if !book.author.isEmpty && book.author != "未知作者" { existing.author = book.author }
            if let cover = book.coverUrl, !cover.isEmpty { existing.coverUrl = book.coverUrl }
            if let intro = book.intro, !intro.isEmpty { existing.intro = intro }
            if let kind = book.kind, !kind.isEmpty { existing.kind = kind }
            if let wordCount = book.wordCount, !wordCount.isEmpty { existing.wordCount = wordCount }
            if let latest = book.latestChapterTitle, !latest.isEmpty { existing.latestChapterTitle = latest }
            if book.totalChapterNum > 0 { existing.totalChapterNum = book.totalChapterNum }
            bookshelf[index] = existing
            saveBookshelf()
            return existing
        } else {
            var newBook = book
            newBook.order = nextManualOrder
            bookshelf.insert(newBook, at: 0)
            saveBookshelf()
            return newBook
        }
    }

    public func removeBook(bookUrl: String) {
        bookshelf.removeAll { $0.bookUrl == bookUrl }
        saveBookshelf()
    }

    // MARK: - 手动排序 (Android `Book.order`)

    /// Next manual position for a newly added book: Android's `BookInfoViewModel` pushes new
    /// books to the top with `order = minOrder - 1`.
    public var nextManualOrder: Int {
        let minimum = bookshelf.map(\.order).min() ?? 1
        return minimum == Int.min ? Int.min : minimum - 1
    }

    /// Applies a drag-reorder from the (possibly group-filtered) shelf view.
    ///
    /// The dragged subset **permutes its own existing order values** in the new sequence.
    /// Reindexing the visible list to 0…n-1 would collide with the other groups' slots and
    /// reshuffle the 全部 view; permuting keeps every non-dragged book exactly where it was,
    /// and degenerates to a plain 0…n-1 reindex when the view shows the whole shelf.
    public func applyManualOrder(_ orderedBooks: [Book]) {
        guard let newOrder = reorderedPositions(current: bookshelf.map { ($0.bookUrl, $0.order) },
                                                ids: orderedBooks.map(\.bookUrl)) else { return }
        for i in 0..<bookshelf.count {
            if let o = newOrder[bookshelf[i].bookUrl] {
                bookshelf[i].order = o
            }
        }
        saveBookshelf()
    }

    /// Drag-to-reorder 书源 = 优先级调整 (Android `BookSource.customOrder` drives 换源候选).
    ///
    /// Same subset-permutation rule as `applyManualOrder`: a filtered/searched view permutes
    /// its own `customOrder` slots so sources outside the view keep their priority, and the
    /// full-list case degenerates to a plain 0…n-1 reindex.
    public func applySourceOrder(_ orderedSources: [BookSource]) {
        guard let newOrder = reorderedPositions(current: sources.map { ($0.bookSourceUrl, $0.customOrder ?? 0) },
                                                ids: orderedSources.map(\.bookSourceUrl)) else { return }
        for i in 0..<sources.count {
            if let o = newOrder[sources[i].bookSourceUrl] {
                sources[i].customOrder = o
            }
        }
        sources.sort { ($0.customOrder ?? 0) < ($1.customOrder ?? 0) }
        saveSources()
    }

    /// Normalize tied / missing imported positions before permuting the visible subset.
    /// A stable tie-break keeps hidden rows in the same relative positions.
    private func reorderedPositions(current: [(id: String, order: Int)], ids: [String]) -> [String: Int]? {
        let visible = Set(ids)
        guard visible.count == ids.count, Set(current.map(\.id)).count == current.count else { return nil }
        let sorted = current.enumerated().sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.map(\.element)
        var positions = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0) })
        let slots = sorted.indices.filter { visible.contains(sorted[$0].id) }
        guard slots.count == ids.count else { return nil }
        for (id, slot) in zip(ids, slots) { positions[id] = slot }
        return positions
    }

    public func removeBooks(bookUrls: Set<String>) {
        guard !bookUrls.isEmpty else { return }
        for url in bookUrls {
            BookContentService.shared.clearCache(for: url)
        }
        bookshelf.removeAll { bookUrls.contains($0.bookUrl) }
        saveBookshelf()
    }

    public func pinBook(bookUrl: String) {
        guard let index = bookshelf.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var item = bookshelf.remove(at: index)
        item.order = nextManualOrder
        item.durChapterTime = now
        item.lastCheckTime = now
        bookshelf.insert(item, at: 0)
        saveBookshelf()
    }

    public func moveBooks(bookUrls: Set<String>, toGroupId groupId: Int64) {
        guard groupId >= 0 else { return }
        guard !bookUrls.isEmpty else { return }
        let known = BookGroupStore.load(from: defaults).filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
        let target = usesGroupBitmasks ? groupId & known : groupId
        for i in 0..<bookshelf.count where bookUrls.contains(bookshelf[i].bookUrl) {
            bookshelf[i].group = target
        }
        saveBookshelf()
    }

    @discardableResult
    public func updateBookMetadata(bookUrl: String, name: String, author: String, coverUrl: String?, intro: String?) -> Book? {
        guard let index = bookshelf.firstIndex(where: { $0.bookUrl == bookUrl }) else { return nil }
        var updated = bookshelf[index]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { updated.name = trimmedName }
        if !trimmedAuthor.isEmpty { updated.author = trimmedAuthor }
        updated.customCoverUrl = coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom = updated.customCoverUrl, !custom.isEmpty {
            updated.coverUrl = custom
        }
        updated.intro = intro?.trimmingCharacters(in: .whitespacesAndNewlines)
        bookshelf[index] = updated
        saveBookshelf()
        return updated
    }

    // MARK: - 换源

    /// Switches a book on the shelf to another source.
    ///
    /// The shelf slot is reused rather than removed-and-appended so the user's ordering
    /// survives, and only the identity fields are rewritten — reading position is remapped by
    /// the caller through `ChapterMatcher`. Old chapter text is discarded because it is keyed
    /// by the previous `bookUrl`; bookmarks need no migration since they key off name+author.
    @discardableResult
    public func changeSource(oldBook: Book, to found: SearchBook, source: BookSource,
                             newChapters: [BookChapter], mappedChapterIndex: Int) -> Book {
        var updated = oldBook
        updated.bookUrl = found.bookUrl
        updated.origin = source.bookSourceUrl
        updated.originName = source.bookSourceName
        updated.tocUrl = found.bookUrl
        if let cover = found.coverUrl, !cover.isEmpty { updated.coverUrl = cover }
        if let intro = found.intro, !intro.isEmpty { updated.intro = intro }
        if let kind = found.kind, !kind.isEmpty { updated.kind = kind }
        if let words = found.wordCount, !words.isEmpty { updated.wordCount = words }
        if !found.name.isEmpty { updated.name = found.name }
        if !found.author.isEmpty, found.author != "未知作者" { updated.author = found.author }

        updated.totalChapterNum = newChapters.count
        updated.latestChapterTitle = newChapters.last?.title ?? updated.latestChapterTitle
        if newChapters.isEmpty {
            updated.durChapterIndex = 0
            updated.durChapterPos = 0
            updated.durChapterTitle = nil
        } else {
            updated.durChapterIndex = min(max(mappedChapterIndex, 0), newChapters.count - 1)
            // Android keeps the in-chapter offset verbatim; a slightly different rendering of
            // the same chapter is closer than jumping back to its first line.
            updated.durChapterTitle = newChapters[updated.durChapterIndex].title
        }

        if let index = bookshelf.firstIndex(where: { $0.bookUrl == oldBook.bookUrl }) {
            bookshelf[index] = updated
        } else {
            bookshelf.insert(updated, at: 0)
        }

        if !oldBook.bookUrl.isEmpty, oldBook.bookUrl != updated.bookUrl {
            BookContentService.shared.clearCache(for: oldBook.bookUrl)
        }
        if !newChapters.isEmpty {
            saveChapters(newChapters, for: updated.bookUrl)
            markTocFetched(bookUrl: updated.bookUrl)   // it came off the network just now
        }
        saveBookshelf()
        return updated
    }

    public func updateProgress(bookUrl: String, chapterIndex: Int, chapterTitle: String, chapterPos: Int = 0) {
        if let index = bookshelf.firstIndex(where: { $0.bookUrl == bookUrl }) {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            bookshelf[index].durChapterIndex = chapterIndex
            bookshelf[index].durChapterPos = chapterPos
            bookshelf[index].durChapterTitle = chapterTitle
            bookshelf[index].durChapterTime = now
            bookshelf[index].lastCheckTime = now
            saveBookshelf()

            // Asynchronously sync progress to WebDAV if configured
            let updatedBook = bookshelf[index]
            let config = WebDAVService.shared.loadConfig()
            if !config.url.isEmpty && !config.username.isEmpty {
                Task {
                    try? await WebDAVService.shared.uploadBookProgress(book: updatedBook, config: config)
                }
            }
        }
    }

    /// Apply a remote timestamp without treating a download as a new local reading event.
    @discardableResult
    public func applyRemoteProgress(_ progress: BookProgress, bookUrl: String) -> Book? {
        guard let index = bookshelf.firstIndex(where: { $0.bookUrl == bookUrl }) else { return nil }
        bookshelf[index] = progress.applying(to: bookshelf[index])
        saveBookshelf()
        return bookshelf[index]
    }

    /// A preUpdateJs reGetBook may change identity. Replace the original shelf slot instead
    /// of adding a duplicate, and keep reading progress changed while the refresh was in flight.
    @discardableResult
    public func applyRefreshedBook(_ refreshed: Book, replacing originalURL: String) throws -> Book? {
        guard let index = bookshelf.firstIndex(where: { $0.bookUrl == originalURL }) else { return nil }
        guard !bookshelf.enumerated().contains(where: { $0.offset != index && $0.element.bookUrl == refreshed.bookUrl }) else {
            throw SourceRuntimeError.bridge("目标网址已存在另一条书架记录，已取消更新")
        }
        let current = bookshelf[index]
        var updated = refreshed
        updated.durChapterIndex = current.durChapterIndex
        updated.durChapterPos = current.durChapterPos
        updated.durChapterTitle = current.durChapterTitle
        updated.durChapterTime = current.durChapterTime
        updated.group = current.group
        updated.order = current.order
        bookshelf[index] = updated
        saveBookshelf()
        if originalURL != updated.bookUrl { BookContentService.shared.clearCache(for: originalURL) }
        return updated
    }

    /// Refreshes all network books on the bookshelf concurrently
    @MainActor
    public func refreshAllBooks(bookURLs: Set<String>? = nil) async {
        // Snapshot published state before starting workers; cache and shelf mutations stay here.
        let jobs = bookshelf.filter { !$0.isLocalBook && (bookURLs?.contains($0.bookUrl) ?? true) }.compactMap { book -> (Book, BookSource)? in
            guard let source = findSource(for: book) else { return nil }
            return (book, source)
        }
        await withTaskGroup(of: (String, Book, [BookChapter])?.self) { group in
            for (book, source) in jobs {
                group.addTask {
                    do {
                        let result = try await BookContentService.shared.fetchBookDetail(book: book, source: source, runPreUpdateJs: true)
                        return (book.bookUrl, result.book, result.chapters)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if Task.isCancelled { group.cancelAll(); break }
                if let (originalURL, updatedBook, chapters) = result {
                    guard let installed = try? applyRefreshedBook(updatedBook, replacing: originalURL) else { continue }
                    if !chapters.isEmpty { saveChapters(chapters, for: installed.bookUrl) }
                }
            }
        }
    }

    // MARK: - Source Management
    public func importSources(json: String) throws -> Int {
        guard let data = json.data(using: .utf8) else { return 0 }
        let imported = (BookSource.decodeListOrObjectWithExtras(from: data) ?? [])
            .filter { !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !imported.isEmpty else {
            throw NSError(domain: "BookStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "未在 JSON 中发现有效书源"])
        }

        var count = 0
        for s in imported {
            if let idx = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) {
                sources[idx] = s
            } else {
                sources.append(s)
                count += 1
            }
        }
        saveSources()
        return count
    }

    public func toggleSource(sourceUrl: String) {
        if let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) {
            var s = sources[idx]
            s.enabled = !(s.enabled ?? true)
            sources[idx] = s
            saveSources()
        }
    }

    public func toggleSourceExplore(sourceUrl: String) {
        if let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) {
            var s = sources[idx]
            s.enabledExplore = !(s.enabledExplore ?? true)
            sources[idx] = s
            saveSources()
        }
    }

    public func deleteSource(sourceUrl: String) {
        sources.removeAll { $0.bookSourceUrl == sourceUrl }
        saveSources()
    }

    public func setSourcesEnabled(urls: Set<String>, enabled: Bool) {
        guard !urls.isEmpty else { return }
        for i in 0..<sources.count where urls.contains(sources[i].bookSourceUrl) {
            sources[i].enabled = enabled
        }
        saveSources()
    }

    public func deleteSources(urls: Set<String>) {
        guard !urls.isEmpty else { return }
        sources.removeAll { urls.contains($0.bookSourceUrl) }
        saveSources()
    }

    public func exportSourcesJSON(urls: Set<String>? = nil) -> String? {
        let target: [BookSource]
        if let urls = urls, !urls.isEmpty {
            target = sources.filter { urls.contains($0.bookSourceUrl) }
        } else {
            target = sources
        }
        guard !target.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(target) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Updates a source's validation outcome: records `respondTime` and adds/removes the 「失效」 group tag.
    public func markSourceValidationResult(sourceUrl: String, passed: Bool, respondTimeMs: Int64) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        var s = sources[idx]
        s.respondTime = respondTimeMs
        var currentGroups = s.groups.filter { $0 != "失效" }
        if !passed {
            currentGroups.insert("失效", at: 0)
        }
        s.bookSourceGroup = currentGroups.isEmpty ? nil : currentGroups.joined(separator: ",")
        sources[idx] = s
        saveSources()
    }

    /// Robustly resolves the BookSource corresponding to a Book using URL, Name, Domain, or Aliases
    public func findSource(for book: Book) -> BookSource? {
        if book.isLocalBook {
            return nil
        }

        // 1. Exact URL match
        if let s = sources.first(where: { $0.bookSourceUrl == book.origin }) {
            return s
        }

        // 2. Exact Name match
        if !book.originName.isEmpty, let s = sources.first(where: { $0.bookSourceName == book.originName }) {
            return s
        }

        // 3. Domain / Host Match (book origin host == source host, covers mirror domains)
        let bookHost = URL(string: book.origin)?.host ?? URL(string: book.bookUrl)?.host ?? ""
        if !bookHost.isEmpty {
            for s in sources {
                let sHost = URL(string: s.bookSourceUrl)?.host ?? ""
                if !sHost.isEmpty && sHost == bookHost {
                    return s
                }
            }
        }

        // 4. Substring / URL contains matching
        if let s = sources.first(where: {
            book.origin.contains($0.bookSourceUrl) ||
            $0.bookSourceUrl.contains(book.origin) ||
            book.bookUrl.hasPrefix($0.bookSourceUrl) ||
            (!book.originName.isEmpty && $0.bookSourceName.contains(book.originName)) ||
            (!book.originName.isEmpty && book.originName.contains($0.bookSourceName))
        }) {
            return s
        }

        return sources.first
    }

    public func updateSource(originalSource: BookSource? = nil, newSource: BookSource) {
        let oldUrl = originalSource?.bookSourceUrl ?? newSource.bookSourceUrl
        let oldName = originalSource?.bookSourceName ?? newSource.bookSourceName

        if let idx = sources.firstIndex(where: { $0.bookSourceUrl == oldUrl || $0.id == (originalSource?.id ?? newSource.id) }) {
            sources[idx] = newSource
            saveSources()
        }

        // Synchronize all books on the bookshelf that referenced the old source name or URL
        var bookshelfModified = false
        for i in 0..<bookshelf.count {
            if bookshelf[i].origin == oldUrl || bookshelf[i].originName == oldName {
                bookshelf[i].origin = newSource.bookSourceUrl
                bookshelf[i].originName = newSource.bookSourceName
                bookshelfModified = true
            }
        }
        if bookshelfModified {
            saveBookshelf()
        }
    }

    public func updateSource(_ source: BookSource) {
        let original = sources.first(where: { $0.id == source.id || $0.bookSourceUrl == source.bookSourceUrl })
        updateSource(originalSource: original, newSource: source)
    }

    public func pinSource(sourceUrl: String) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        let item = sources.remove(at: idx)
        sources.insert(item, at: 0)
        saveSources()
    }


    public func performLogin(source: BookSource, credentials: [String: String]) async throws -> String {
        guard let loginScript = source.loginUrl, !loginScript.isEmpty else {
            throw NSError(domain: "BookStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "该书源未配置登录脚本"])
        }

        let credData = (try? JSONSerialization.data(withJSONObject: credentials)) ?? Data()
        let credJson = String(data: credData, encoding: .utf8) ?? "{}"

        var updatedSource = source
        updatedSource.loginInfo = credJson

        let jsEngine = JSEngine(bookSource: updatedSource, baseUrl: source.bookSourceUrl)
        try jsEngine.checkReady()

        var capturedHeader: String? = nil
        jsEngine.onLoginHeaderUpdated = { newH in
            capturedHeader = newH
        }

        _ = jsEngine.eval(script: JSEngine.extractJSScript(from: loginScript) ?? loginScript)
        if let message = jsEngine.lastScriptError {
            throw NSError(domain: "BookStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let finalHeader = capturedHeader, !finalHeader.isEmpty else {
            throw NSError(domain: "BookStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "登录未返回有效凭据，请检查账号密码"])
        }

        await MainActor.run {
            if let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
                sources[idx].loginInfo = credJson
                sources[idx].loginHeader = finalHeader
                saveSources()
            }
        }

        return finalHeader
    }

    public func logoutSource(sourceUrl: String) {
        if let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) {
            sources[idx].loginHeader = nil
            sources[idx].loginInfo = nil
            saveSources()
        }
    }

    // MARK: - 搜索历史

    public func saveSearchHistory() {
        SearchHistoryStore.save(searchHistory, to: defaults)
    }

    /// Android bumps the counter on a repeat rather than adding a duplicate row.
    public func recordSearchKeyword(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchHistory = SearchHistoryStore.record(trimmed, in: searchHistory)
        saveSearchHistory()
    }

    public func deleteSearchKeyword(_ word: String) {
        searchHistory.removeAll { $0.word == word }
        saveSearchHistory()
    }

    public func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }

    /// Recency when the field is empty, usage when the user is typing.
    public func searchHistory(matching needle: String = "") -> [SearchKeyword] {
        needle.isEmpty ? SearchHistoryStore.byTime(searchHistory)
                       : SearchHistoryStore.matching(searchHistory, needle)
    }

    // MARK: - EPUB & Chapter Storage
    private let chapterCacheLock = NSRecursiveLock()
    private var chaptersCache: [String: [BookChapter]] = [:]
    /// How long a cached TOC may be trusted before something should re-crawl it. The rules live
    /// in `TocCache` so they can be unit-tested without a reader on screen.

    /// When this book's TOC was last successfully crawled. Kept in `UserDefaults` rather than
    /// inside `chapters_<md5>.json` so that file keeps the shape it always had.
    public func tocFetchedAt(bookUrl: String) -> Date? {
        let seconds = defaults.double(forKey: TocCache.defaultsKey(bookUrl: bookUrl))
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public func markTocFetched(bookUrl: String, at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970,
                                  forKey: TocCache.defaultsKey(bookUrl: bookUrl))
    }

    public func tocIsStale(bookUrl: String, now: Date = Date()) -> Bool {
        TocCache.isStale(fetchedAt: tocFetchedAt(bookUrl: bookUrl), now: now)
    }

    public func saveChapters(_ chapters: [BookChapter], for bookUrl: String) {
        chapterCacheLock.lock()
        defer { chapterCacheLock.unlock() }
        chaptersCache[bookUrl] = chapters
        let chapterFile = getDocumentsDirectory().appendingPathComponent("chapters_\(CryptoUtils.md5(bookUrl)).json")
        if let data = try? JSONEncoder().encode(chapters) {
            try? data.write(to: chapterFile)
        }
    }

    public func getChapters(for bookUrl: String) -> [BookChapter] {
        chapterCacheLock.lock()
        defer { chapterCacheLock.unlock() }
        if let memory = chaptersCache[bookUrl] {
            return memory
        }
        let chapterFile = getDocumentsDirectory().appendingPathComponent("chapters_\(CryptoUtils.md5(bookUrl)).json")
        if let data = try? Data(contentsOf: chapterFile),
           var list = try? JSONDecoder().decode([BookChapter].self, from: data) {
            var needsRepair = false
            for i in 0..<list.count {
                if list[i].index != i {
                    list[i].index = i
                    needsRepair = true
                }
                if list[i].url.contains("%23") {
                    list[i].url = list[i].url.replacingOccurrences(of: "%23", with: "#")
                    needsRepair = true
                }
            }
            if needsRepair {
                saveChapters(list, for: bookUrl)
            }
            chaptersCache[bookUrl] = list
            return list
        }
        return []
    }

    public func importEpub(from fileUrl: URL) throws -> Book {
        let parsed = try EpubParser.shared.parse(epubUrl: fileUrl)
        saveChapters(parsed.chapters, for: parsed.book.bookUrl)
        if let idx = bookshelf.firstIndex(where: { $0.bookUrl == parsed.book.bookUrl }) {
            bookshelf[idx] = parsed.book
        } else {
            bookshelf.insert(parsed.book, at: 0)
        }
        saveBookshelf()
        return parsed.book
    }

    public func importTxt(from fileUrl: URL, customRulePattern: String? = nil) throws -> Book {
        guard let data = try? Data(contentsOf: fileUrl) else {
            throw NSError(domain: "BookStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取TXT文件内容"])
        }
        let content = CharsetDetector.decode(data)

        let bookTitle = fileUrl.deletingPathExtension().lastPathComponent
        let bookUrl = "txt://\(CryptoUtils.md5(fileUrl.absoluteString))"
        let bookId = CryptoUtils.md5(bookUrl)

        let docsDir = getDocumentsDirectory()
        let txtBookDir = docsDir.appendingPathComponent("Books/TXT/\(bookId)")
        try? FileManager.default.createDirectory(at: txtBookDir, withIntermediateDirectories: true)

        let nsString = content as NSString
        var matches: [NSTextCheckingResult] = []

        if let custom = customRulePattern, !custom.isEmpty {
            if let regex = try? NSRegularExpression(pattern: custom, options: [.anchorsMatchLines]) {
                matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            }
        }

        if matches.isEmpty {
            // Try all enabled rules in TxtTocRuleStore in order
            let enabledRules = TxtTocRuleStore.load(from: defaults).filter { $0.enable }
            for r in enabledRules {
                if let regex = try? NSRegularExpression(pattern: r.rule, options: [.anchorsMatchLines]) {
                    let candidateMatches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
                    if candidateMatches.count > 1 {
                        matches = candidateMatches
                        break
                    }
                }
            }
        }

        if matches.isEmpty {
            // Fallback default
            let defaultPattern = "^[\\s\\t]*(第[0-9一二三四五六七八九十百千]+[章回节卷].*)$"
            if let regex = try? NSRegularExpression(pattern: defaultPattern, options: [.anchorsMatchLines]) {
                matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            }
        }
        var chapters: [BookChapter] = []

        if matches.isEmpty {
            let chFile = txtBookDir.appendingPathComponent("chapter_0.txt")
            try? content.write(to: chFile, atomically: true, encoding: .utf8)
            chapters.append(BookChapter(
                bookUrl: bookUrl,
                url: chFile.absoluteString,
                title: bookTitle,
                index: 0
            ))
        } else {
            for i in 0..<matches.count {
                let match = matches[i]
                let title = nsString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                let startPos = match.range.location
                let endPos = (i + 1 < matches.count) ? matches[i + 1].range.location : nsString.length
                let chapterText = nsString.substring(with: NSRange(location: startPos, length: endPos - startPos))

                let chFile = txtBookDir.appendingPathComponent("chapter_\(i).txt")
                try? chapterText.write(to: chFile, atomically: true, encoding: .utf8)

                chapters.append(BookChapter(
                    bookUrl: bookUrl,
                    url: chFile.absoluteString,
                    title: title,
                    index: i
                ))
            }
        }

        let book = Book(
            bookUrl: bookUrl,
            name: bookTitle,
            author: "本地书籍",
            kind: "TXT 本地书籍",
            coverUrl: nil,
            intro: "本地导入的TXT小说",
            origin: "local",
            originName: "本地导入",
            tocUrl: "",
            totalChapterNum: chapters.count
        )

        saveChapters(chapters, for: bookUrl)
        if let idx = bookshelf.firstIndex(where: { $0.bookUrl == bookUrl }) {
            bookshelf[idx] = book
        } else {
            bookshelf.insert(book, at: 0)
        }
        saveBookshelf()
        return book
    }

    public func importFile(from fileUrl: URL) throws -> Book {
        let ext = fileUrl.pathExtension.lowercased()
        if ext == "txt" {
            return try importTxt(from: fileUrl)
        } else {
            return try importEpub(from: fileUrl)
        }
    }
}

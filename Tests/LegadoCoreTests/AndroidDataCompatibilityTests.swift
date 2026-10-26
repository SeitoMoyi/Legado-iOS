import XCTest
import ZIPFoundation
@testable import LegadoCore

final class AndroidDataCompatibilityTests: XCTestCase {
    func testCorruptLatestZipDoesNotRestoreAnotherLooseSnapshot() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = WebDAVService(session: session)
        defer { MockWebDAVURLProtocol.requestHandler = nil; session.invalidateAndCancel() }
        MockWebDAVURLProtocol.requestHandler = { request in
            let data: Data
            let status: Int
            if request.httpMethod == "PROPFIND" {
                status = 207
                data = Data(#"<d:multistatus xmlns:d="DAV:"><d:response><d:href>/legado/backup2026-10-01.zip</d:href><d:propstat><d:prop><d:getcontentlength>100</d:getcontentlength></d:prop></d:propstat></d:response></d:multistatus>"#.utf8)
            } else if request.url?.pathExtension == "zip" { status = 200; data = Data("not a zip".utf8) }
            else { XCTFail("A corrupt selected archive must not fall back to loose metadata"); status = 404; data = Data() }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        do {
            _ = try await service.restorePayload(config: WebDAVConfig(url: "https://dav.test", username: "test", password: "test", remotePath: "legado"))
            XCTFail("Expected corrupt archive error")
        } catch { }
    }

    func testLooseWebDAVRestoreRecognizesSupplementalMembers() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = WebDAVService(session: session)
        let originalConfig = service.loadConfig()
        defer { MockWebDAVURLProtocol.requestHandler = nil; session.invalidateAndCancel(); service.saveConfig(originalConfig) }
        MockWebDAVURLProtocol.requestHandler = { request in
            let status: Int
            let data: Data
            if request.httpMethod == "PROPFIND" {
                status = 207
                data = Data(#"<d:multistatus xmlns:d="DAV:"></d:multistatus>"#.utf8)
            } else if request.url?.lastPathComponent == "dictRule.json" {
                status = 200
                data = Data(#"[{"name":"Dictionary","urlRule":"https://dict.test"}]"#.utf8)
            } else { status = 404; data = Data() }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        let config = WebDAVConfig(url: "https://dav.test", username: "test", password: "test", remotePath: "legado")
        let restored = try await service.restorePayload(config: config)
        XCTAssertNil(restored.books)
        XCTAssertEqual(restored.dictRules?.first?.name, "Dictionary")
        XCTAssertEqual(restored.backupName, "dictRule.json")
    }

    func testHTTPVoiceSelectionUsesIdentityAndSystemIsNotAnExportedRow() throws {
        let one = HttpTTS(id: -1, name: "Same", url: "https://one.test")
        let two = HttpTTS(id: 2, name: "Same", url: "https://two.test")
        XCTAssertEqual(HttpTTSStore.engine(id: -1, in: [one, two])?.url, one.url)
        XCTAssertEqual(HttpTTSStore.engine(id: 2, in: [one, two])?.url, two.url)
        XCTAssertNil(HttpTTSStore.engine(id: nil, in: [one, two]))
        let name = "VoiceCompatibility." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        HttpTTSStore.save([HttpTTS(id: 1, name: "Legacy system", contentType: "system"), one, two], to: defaults)
        XCTAssertEqual(HttpTTSStore.load(from: defaults), [one, two])
    }

    private func book(_ url: String, group: Int64) -> Book {
        Book(bookUrl: "https://data.test/" + url, name: url, author: "Author", origin: "https://data.test", group: group)
    }

    func testLegacyTimestampMigrationRetainsMetadataAndMembership() throws {
        var first = BookGroup(groupId: 1_700_000_001, groupName: "First", cover: "cover", order: 8, enableRefresh: false, bookSort: 3)
        first.extra["future"] = .object(["enabled": .bool(true)])
        let second = BookGroup(groupId: 4, groupName: "Existing native bit")
        var reading = book("one", group: first.groupId)
        reading.durChapterIndex = 6; reading.durChapterPos = 15; reading.durChapterTime = 900
        let migrated = try BookGroupCompatibility.migrateLegacy(groups: [first, second], books: [reading])
        let group = try XCTUnwrap(migrated.groups.first { $0.groupName == "First" })
        XCTAssertTrue(BookGroupCompatibility.isSingleBit(group.groupId))
        XCTAssertNotEqual(group.groupId, second.groupId)
        XCTAssertEqual(group.cover, first.cover)
        XCTAssertFalse(group.enableRefresh)
        XCTAssertEqual(group.extra, first.extra)
        XCTAssertEqual(migrated.books.first?.group, group.groupId)
        XCTAssertEqual(migrated.books.first?.durChapterIndex, 6)
        XCTAssertEqual(migrated.books.first?.durChapterPos, 15)
        XCTAssertEqual(migrated.legacyIDs[String(first.groupId)], group.groupId)
    }

    func testExistingAndroidCombinedMaskIsNotTreatedAsOrphanLegacyID() throws {
        let groups = [BookGroup(groupId: 1, groupName: "A"), BookGroup(groupId: 2, groupName: "B")]
        let migrated = try BookGroupCompatibility.migrateLegacy(groups: groups, books: [book("both", group: 3)])
        XCTAssertEqual(migrated.groups, groups)
        XCTAssertEqual(migrated.books.first?.group, 3)
        XCTAssertTrue(migrated.legacyIDs.isEmpty)
    }

    func testImportConflictsRemapOnlyIncomingBookGroups() throws {
        let local = [BookGroup(groupId: 1, groupName: "Local")]
        let imported = [BookGroup(groupId: 1, groupName: "Imported A"), BookGroup(groupId: 2, groupName: "Imported B")]
        let merged = try BookGroupCompatibility.mergeAndroid(groups: imported, books: [book("both", group: 3)], into: local)
        XCTAssertEqual(merged.groups.first?.groupName, "Local")
        let a = try XCTUnwrap(merged.groups.first { $0.groupName == "Imported A" })
        let b = try XCTUnwrap(merged.groups.first { $0.groupName == "Imported B" })
        XCTAssertNotEqual(a.groupId, 1)
        XCTAssertNotEqual(a.groupId, b.groupId)
        XCTAssertEqual(merged.books.first?.group, a.groupId | b.groupId)
    }

    func testUnknownIncomingBitsHaveDefinitionsAndSameNameGroupsRemainDistinct() throws {
        let imported = [BookGroup(groupId: 1, groupName: "Same"), BookGroup(groupId: 2, groupName: "Same")]
        let merged = try BookGroupCompatibility.mergeAndroid(groups: imported, books: [book("all", group: 7)], into: [])
        XCTAssertEqual(Set(merged.groups.map(\.groupId)).count, 3)
        XCTAssertEqual(merged.groups.filter { $0.groupName == "Same" }.count, 2)
        XCTAssertEqual(merged.books.first?.group, 7)
    }

    func testCapacityAndMalformedGroupIDsRejectInsteadOfDroppingData() {
        let full = (0..<63).map { BookGroup(groupId: Int64(1) << $0, groupName: "G\($0)") }
        XCTAssertNil(BookGroupCompatibility.nextIdentifier(in: full))
        XCTAssertThrowsError(try BookGroupCompatibility.mergeAndroid(groups: [BookGroup(groupId: 1, groupName: "New")], books: [], into: full))
        XCTAssertThrowsError(try BookGroupCompatibility.mergeAndroid(groups: [BookGroup(groupId: 3, groupName: "Invalid")], books: [], into: []))
        let legacy = (1000..<1064).map { BookGroup(groupId: Int64($0), groupName: "Old\($0)") }
        XCTAssertThrowsError(try BookGroupCompatibility.migrateLegacy(groups: legacy, books: []))
    }

    func testNativeGroupFiltersUseMembershipAndTypeBits() {
        var both = book("both", group: 3)
        both.extra["type"] = .int(8)
        var local = book("local", group: 0)
        local.extra["type"] = .int(8 | 256)
        var audio = book("audio", group: 0)
        audio.extra["type"] = .int(32)
        var temporary = book("temporary", group: 1)
        temporary.extra["type"] = .int(8 | 1024)
        var failed = book("failed", group: 0)
        failed.extra["type"] = .int(8 | 16)
        let groups = [BookGroup(groupId: 1, groupName: "A"), BookGroup(groupId: 2, groupName: "B")]
        let books = [both, local, audio, temporary, failed]
        XCTAssertEqual(ShelfFilter.books(books, inGroup: 1, groups: groups).map(\.name), ["both"])
        XCTAssertEqual(ShelfFilter.books(books, inGroup: 2, groups: groups).map(\.name), ["both"])
        XCTAssertEqual(ShelfFilter.books(books, inGroup: BookGroup.idLocal, groups: groups).map(\.name), ["local"])
        XCTAssertEqual(ShelfFilter.books(books, inGroup: BookGroup.idAudio, groups: groups).map(\.name), ["audio"])
        XCTAssertEqual(ShelfFilter.books(books, inGroup: BookGroup.idNetNone, groups: groups).map(\.name), ["failed"])
        XCTAssertEqual(ShelfFilter.books(books, inGroup: BookGroup.idError, groups: groups).map(\.name), ["failed"])
        XCTAssertEqual(ShelfFilter.books(books, inGroup: BookGroup.idAll, groups: groups).count, 4)
    }

    func testSparseNativeModelsAndUnknownFieldsSurviveOrdinaryCodable() throws {
        let group = try JSONDecoder().decode(BookGroup.self, from: Data(#"{"groupId":1,"groupName":"养肥中","future":{"color":2}}"#.utf8))
        XCTAssertTrue(group.show)
        XCTAssertEqual(group.extra["future"], .object(["color": .int(2)]))
        XCTAssertEqual(try JSONDecoder().decode(BookGroup.self, from: JSONEncoder().encode(group)), group)
        let engine = try JSONDecoder().decode(HttpTTS.self, from: Data(#"{"id":12,"name":"Voice","url":"https://tts.test","jsLib":"helper()","enabledCookieJar":false,"lastUpdateTime":123}"#.utf8))
        XCTAssertEqual(engine.extra["lastUpdateTime"], .int(123))
        XCTAssertEqual(try JSONDecoder().decode(HttpTTS.self, from: JSONEncoder().encode(engine)), engine)
        let dictionary = try JSONDecoder().decode(DictRule.self, from: Data(#"{"name":"D","future":null}"#.utf8))
        XCTAssertEqual(dictionary.extra["future"], .null)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dictionary)) as? [String: Any]
        XCTAssertNil(encoded?["extra"])
    }

    func testNewBackupMembersRoundTripAndExcludeIOSVirtualEntries() throws {
        var engine = HttpTTS(id: 100, name: "Voice", url: "https://tts.test")
        engine.extra["jsLib"] = .string("library")
        let data = try WebDAVService().createBackupZip(books: [book("both", group: 3)], sources: [],
            bookGroups: [BookGroup(groupId: 1, groupName: "A"), BookGroup(groupId: 2, groupName: "B"), BookGroup(groupId: BookGroup.idNet, groupName: "iOS")],
            dictRules: [DictRule(name: "Dictionary", urlRule: "https://dict.test")],
            httpTTS: [HttpTTS(id: 1, name: "System", contentType: "system"), engine]).data
        let restored = try WebDAVService().restorePayloadFromZip(data: data)
        XCTAssertEqual(restored.books?.first?.group, 3)
        XCTAssertEqual(restored.bookGroups?.map(\.groupId), [1, 2])
        XCTAssertEqual(restored.dictRules?.first?.name, "Dictionary")
        XCTAssertEqual(restored.httpTTS, [engine])
    }

    func testArchiveWithOnlyOneNewMemberIsRecognized() throws {
        for (name, json) in [("bookGroup.json", #"[{"groupId":1,"groupName":"A"}]"#),
                             ("dictRule.json", #"[{"name":"D"}]"#),
                             ("httpTTS.json", #"[{"id":10,"name":"Voice","url":"https://tts.test"}]"#)] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                let archive = try Archive(url: file, accessMode: .create)
                let data = Data(json.utf8)
                try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                }
            }
            let restored = try WebDAVService().restorePayloadFromZip(fileUrl: file)
            XCTAssertNil(restored.books)
            XCTAssertTrue(restored.bookGroups != nil || restored.dictRules != nil || restored.httpTTS != nil)
        }
    }

    func testEmptyPersistedRuleListsStayEmptyAndNativeSeedNamesArePreserved() throws {
        let name = "DataCompatibility." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        DictRuleStore.save([], to: defaults)
        HttpTTSStore.save([], to: defaults)
        XCTAssertTrue(DictRuleStore.load(from: defaults).isEmpty)
        XCTAssertTrue(HttpTTSStore.load(from: defaults).isEmpty)
        defaults.set(true, forKey: BookGroupStore.bitmaskVersionKey)
        BookGroupStore.save([BookGroup(groupId: 1, groupName: "养肥中"), BookGroup(groupId: 2, groupName: "已完结")], to: defaults)
        XCTAssertEqual(BookGroupStore.load(from: defaults).filter { $0.groupId > 0 }.count, 2)
        BookGroupStore.save([BookGroup(groupId: 4, groupName: "Later", order: 8), BookGroup(groupId: 2, groupName: "Earlier", order: 3)], to: defaults)
        XCTAssertEqual(BookGroupStore.load(from: defaults).filter { $0.groupId > 0 }.map(\.groupId), [2, 4])
    }
}

import XCTest
import ZIPFoundation
@testable import LegadoCore

final class BackupSubscriptionTests: XCTestCase {
    func testSubscriptionHTTPDownloadValidatesStatusAndParsesPreview() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); MockWebDAVURLProtocol.requestHandler = nil }
        MockWebDAVURLProtocol.requestHandler = { request in
            let status = request.url?.path == "/missing" ? 404 : 200
            let body = Data(#"[{"bookSourceUrl":"https://source.test","bookSourceName":"Fixture"}]"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }
        let service = RuleSubscriptionService(session: session)
        let preview = try await service.fetch(RuleSub(url: "https://rules.test/ok"))
        XCTAssertEqual(preview.names, ["Fixture"])
        do { _ = try await service.fetch(RuleSub(url: "https://rules.test/missing")); XCTFail("Expected HTTP error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("404")) }
    }

    func testAllStylesSelectionPreferencesAndOpaqueMembersSurviveSecondExport() throws {
        var style = try JSONDecoder().decode(ReadStyleConfig.self, from: Data(#"{"name":"Night","textSize":22,"bgTypeNight":2,"future":{"flag":true}}"#.utf8))
        style.textSize = 23
        var prefs = ReaderPrefs(); prefs.ttsTimer = 45; prefs.textFullJustify = false
        let raw = ["config.xml": Data([0, 255, 40, 90]), "assets/cover.bin": Data([10, 20]), "servers.json": Data("[]".utf8)]
        let payload = WebDAVService.BackupRestorePayload(books: [], sources: [],
            ruleSubscriptions: [RuleSub(id: 7, name: "Rules", url: "https://example.test/rules", autoUpdate: true)],
            readStyles: [ReadStyleConfig(name: "Day"), style], readerSettings: ReaderBackupSettings(selectedStyle: 1, prefs: prefs), preservedMembers: raw)
        let service = WebDAVService()
        let first = try service.restorePayloadFromZip(data: service.createBackupZip(payload: payload).data)
        let second = try service.restorePayloadFromZip(data: service.createBackupZip(payload: first).data)
        XCTAssertEqual(second.readStyles?.count, 2)
        XCTAssertEqual(second.readStyles?[1], style)
        XCTAssertEqual(second.readerSettings?.selectedStyle, 1)
        XCTAssertEqual(second.readerSettings?.prefs, prefs)
        XCTAssertEqual(second.preservedMembers, raw)
        XCTAssertEqual(second.ruleSubscriptions?.first?.autoUpdate, true)
        XCTAssertNil(second.readStyles?[1].extra["extra"])
    }

    func testLegacySingleStyleMigratesAndEditingSelectedStyleDoesNotDeleteOthers() throws {
        let name = "ReaderMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONEncoder().encode(ReadStyleConfig(name: "Legacy")), forKey: ReaderStore.styleKey)
        XCTAssertEqual(ReaderStore.loadStyles(from: defaults).map(\.name), ["Legacy"])
        ReaderStore.saveStyles([ReadStyleConfig(name: "A"), ReadStyleConfig(name: "B")], selectedIndex: 1, to: defaults)
        var current = try XCTUnwrap(ReaderStore.loadStyle(from: defaults)); current.textSize = 29
        ReaderStore.save(current, to: defaults)
        XCTAssertEqual(ReaderStore.loadStyles(from: defaults).map(\.name), ["A", "B"])
        XCTAssertEqual(ReaderStore.loadStyles(from: defaults)[1].textSize, 29)
        defaults.set(999, forKey: ReaderStore.selectedStyleKey)
        XCTAssertEqual(ReaderStore.loadStyle(from: defaults)?.name, "B")
        ReaderStore.saveStyles([], to: defaults)
        XCTAssertNil(ReaderStore.loadStyle(from: defaults))
    }

    func testUnknownOnlyArchiveIsPreservedAndUnsafeArchivePathsRejected() throws {
        let service = WebDAVService()
        let archive = try Archive(accessMode: .create)
        let contents = Data("future".utf8)
        try archive.addEntry(with: "future.json", type: .file, uncompressedSize: Int64(contents.count)) { offset, count in
            contents.subdata(in: Int(offset)..<Int(offset) + count)
        }
        let restored = try service.parseArchivePayload(archive)
        XCTAssertEqual(restored.preservedMembers["future.json"], contents)
        for path in ["../outside.json", "/absolute.json", "a/../b.json", "a\\b.json", "a//b.json"] {
            XCTAssertThrowsError(try BackupCompatibilityStore.validate(path: path))
        }
        let invalid = try Archive(accessMode: .create)
        try invalid.addEntry(with: "../outside.json", type: .file, uncompressedSize: Int64(1)) { _, _ in Data([1]) }
        XCTAssertThrowsError(try service.parseArchivePayload(invalid))
    }

    func testDuplicateWrappedTypedMembersAreRejected() throws {
        let archive = try Archive(accessMode: .create)
        for path in ["a/readConfig.json", "b/readConfig.json"] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(2)) { _, _ in Data("[]".utf8) }
        }
        XCTAssertThrowsError(try WebDAVService().parseArchivePayload(archive))
    }

    func testSubscriptionTypesPreviewAndValidation() throws {
        let book = try RuleSubscriptionService.preview(data: Data(#"[{"bookSourceUrl":"https://book.test","bookSourceName":"Books"}]"#.utf8), type: 0)
        XCTAssertEqual(book.names, ["Books"])
        let rss = try RuleSubscriptionService.preview(data: Data(#"{"sourceUrl":"https://rss.test","sourceName":"Feed"}"#.utf8), type: 1)
        XCTAssertEqual(rss.names, ["Feed"])
        let replace = try RuleSubscriptionService.preview(data: Data(#"[{"name":"Clean","pattern":"ads"}]"#.utf8), type: 2)
        XCTAssertEqual(replace.names, ["Clean"])
        XCTAssertThrowsError(try RuleSubscriptionService.preview(data: Data("[]".utf8), type: 9))
        XCTAssertThrowsError(try RuleSubscriptionService.preview(data: Data("<html>error</html>".utf8), type: 0))
        XCTAssertThrowsError(try RuleSubscriptionService.preview(data: Data(#"[{"sourceName":"wrong type"}]"#.utf8), type: 0))
        for url in ["file:///tmp/test", "javascript:foo", "https://user:password@example.test", "https://"] {
            XCTAssertNil(RuleSubscriptionService.validURL(url))
        }
    }

    func testSubscriptionCRUDUsesNativeIDURLAndOrderWhilePreservingUnknownFields() throws {
        let first = try JSONDecoder().decode(RuleSub.self, from: Data(#"{"id":4,"name":"First","url":"https://a.test","type":9,"customOrder":10,"autoUpdate":true,"newFlag":true}"#.utf8))
        XCTAssertEqual(first.extra["newFlag"], .bool(true))
        XCTAssertEqual(try JSONDecoder().decode(RuleSub.self, from: JSONEncoder().encode(first)), first)
        let second = RuleSub(id: 5, url: "https://b.test")
        let list = try RuleSubStore.upsert(second, into: [first])
        XCTAssertEqual(list[1].customOrder, 11)
        XCTAssertThrowsError(try RuleSubStore.upsert(RuleSub(id: 8, url: first.url), into: list))
        var edited = first; edited.name = "Changed"
        XCTAssertEqual(try RuleSubStore.upsert(edited, into: list).first?.name, "Changed")
        let imported = RuleSub(id: 99, name: "Restored", url: first.url)
        XCTAssertEqual(RuleSubStore.merge([imported], into: list).count, 2)
        XCTAssertEqual(RuleSubStore.merge([imported], into: list).first?.id, 99)
    }

    func testNativeBookReadConfigPrecedenceAndRoundTrip() throws {
        var book = try XCTUnwrap(Book.decodeWithExtras(from: Data(#"{"bookUrl":"b","name":"Book","author":"Author","useReplaceRule":true,"readConfig":{"useReplaceRule":false,"pageAnim":3,"imageStyle":"FULL","reverseToc":true,"future":8}}"#.utf8)))
        XCTAssertEqual(book.useReplaceRule, false)
        XCTAssertEqual(book.readerPageAnim, .scroll)
        XCTAssertEqual(book.readerImageStyle, .full)
        book.useReplaceRule = true
        book.setReaderSetting("pageAnim", value: .int(4))
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as! [String: Any]
        let config = raw["readConfig"] as! [String: Any]
        XCTAssertEqual(config["useReplaceRule"] as? Bool, true)
        XCTAssertEqual(config["future"] as? Int, 8)
        XCTAssertEqual(config["reverseToc"] as? Bool, true)
        XCTAssertNil(raw["useReplaceRule"])
        let reloaded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(reloaded.readerPageAnim, PageAnim.none)
        XCTAssertEqual(reloaded.useReplaceRule, true)
        book.setReaderSetting("pageAnim", value: nil)
        XCTAssertNil(book.readerPageAnim)
    }
}

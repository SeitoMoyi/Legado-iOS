import XCTest
import ZIPFoundation
#if canImport(LegadoCore)
import LegadoCore
#endif
@testable import LegadoCore

/// 书架二级菜单「缓存 / 导出」的导出锁：TXT 拼接与编码、EPUB 结构（mimetype 首位 + OCF/OPF
/// 成员齐全）、书单 JSON 往返。
final class BookExportServiceTests: XCTestCase {

    private let book = Book(bookUrl: "https://test.example/book/1", name: "测试之书",
                            author: "测试作者", origin: "https://test.example")

    private func chapters(_ count: Int) -> [BookChapter] {
        (0..<count).map { i in
            BookChapter(bookUrl: book.bookUrl,
                        url: "https://test.example/c/\(i)",
                        title: "第\(i + 1)章 试炼", index: i)
        }
    }

    private func provider(cached: [Int: String]) -> (Int) -> String? {
        { cached[$0] }
    }

    override func tearDown() {
        // 清理临时导出目录，避免测试间文件名冲突。
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("legado-export")
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testTXTExportConcatenatesCachedChaptersWithTitle() throws {
        let url = try BookExportService.exportTXT(
            book: book, chapters: chapters(3),
            contentProvider: provider(cached: [0: "第一章正文内容", 2: "第三章正文内容"]),
            encoding: .utf8)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("测试之书"))
        XCTAssertTrue(text.contains("作者：测试作者"))
        XCTAssertTrue(text.contains("第1章 试炼"))
        XCTAssertTrue(text.contains("第一章正文内容"))
        XCTAssertTrue(text.contains("第3章 试炼"))
        XCTAssertTrue(text.contains("第三章正文内容"))
        // 未缓存的第 2 章应被跳过
        XCTAssertFalse(text.contains("第2章 试炼"))
    }

    func testTXTExportGB18030RoundTrip() throws {
        let url = try BookExportService.exportTXT(
            book: book, chapters: chapters(1),
            contentProvider: provider(cached: [0: "简繁转换与汉字编码：龘齉"]),
            encoding: .gb18030)

        let data = try Data(contentsOf: url)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let decoded = String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
        XCTAssertEqual(decoded, "测试之书\n作者：测试作者\n\n\n第1章 试炼\n\n简繁转换与汉字编码：龘齉")
    }

    func testTXTExportWithoutCacheThrows() {
        XCTAssertThrowsError(try BookExportService.exportTXT(
            book: book, chapters: chapters(2),
            contentProvider: { _ in nil }))
    }

    func testEPUBStructureMimetypeFirstAndMembersPresent() throws {
        let url = try BookExportService.exportEPUB(
            book: book, chapters: chapters(2),
            contentProvider: provider(cached: [0: "甲乙丙丁", 1: "戊己庚辛"]))

        let archive = try Archive(url: url, accessMode: .read)
        let names = archive.map { $0.path }

        // mimetype 必须是第一个成员（OCF 规范；Entry 的压缩方式字段非公开，改由
        // 导出实现保证 stored 写入）。
        XCTAssertEqual(names.first, "mimetype")
        XCTAssertTrue(names.contains("META-INF/container.xml"))
        XCTAssertTrue(names.contains("OEBPS/content.opf"))
        XCTAssertTrue(names.contains("OEBPS/nav.xhtml"))
        XCTAssertTrue(names.contains("OEBPS/toc.ncx"))
        XCTAssertTrue(names.contains("OEBPS/chapter_0001.xhtml"))
        XCTAssertTrue(names.contains("OEBPS/chapter_0002.xhtml"))

        // container.xml 指向 OPF。
        let containerData = try readEntry("META-INF/container.xml", from: archive)
        let containerXML = String(decoding: containerData, as: UTF8.self)
        XCTAssertTrue(containerXML.contains("OEBPS/content.opf"))

        // 正文 XHTML 保留段落并转义。
        let chapterData = try readEntry("OEBPS/chapter_0001.xhtml", from: archive)
        let chapterXML = String(decoding: chapterData, as: UTF8.self)
        XCTAssertTrue(chapterXML.contains("<p>甲乙丙丁</p>"))
        XCTAssertTrue(chapterXML.contains("第1章 试炼"))

        // OPF spine/manifest 覆盖两章。
        let opf = String(decoding: try readEntry("OEBPS/content.opf", from: archive), as: UTF8.self)
        XCTAssertTrue(opf.contains("<itemref idref=\"c1\"/>"))
        XCTAssertTrue(opf.contains("<itemref idref=\"c2\"/>"))
        XCTAssertTrue(opf.contains("<dc:title>测试之书</dc:title>"))
    }

    func testEPUBXHTMLEscaping() {
        let xhtml = BookExportService.chapterXHTML(title: "第<1>章 & \"试炼\"",
                                                   content: "正文含 <标签> 与 & 符号")
        XCTAssertTrue(xhtml.contains("第&lt;1&gt;章 &amp; &quot;试炼&quot;"))
        XCTAssertTrue(xhtml.contains("<p>正文含 &lt;标签&gt; 与 &amp; 符号</p>"))
    }

    func testEPUBWithoutCacheThrows() {
        XCTAssertThrowsError(try BookExportService.exportEPUB(
            book: book, chapters: chapters(1),
            contentProvider: { _ in nil }))
    }

    func testBookshelfJSONRoundTrip() throws {
        var exported = book
        exported.name = "往返之书"
        let url = try BookExportService.exportBookshelfJSON(books: [exported])
        let data = try Data(contentsOf: url)
        let decoded = try ShelfImportService.parse(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "往返之书")
        let raw = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertNil(raw[0]["bookUrl"])
        XCTAssertNil(raw[0]["durChapterPos"])
    }

    func testSanitizeFileNameStripsPathSeparators() {
        XCTAssertEqual(BookExportService.sanitizeFileName("a/b\\c:d"), "a_b_c_d")
        XCTAssertEqual(BookExportService.sanitizeFileName("   "), "export")
    }

    private func readEntry(_ name: String, from archive: Archive) throws -> Data {
        guard let entry = archive[name] else {
            throw CocoaError(.fileNoSuchFile)
        }
        var data = Data()
        _ = try archive.extract(entry, bufferSize: 65536) { chunk in
            data.append(chunk)
        }
        return data
    }
}

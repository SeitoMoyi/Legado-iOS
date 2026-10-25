import Foundation
import ZIPFoundation

// MARK: - Book Export Service (Plan 第一批 书架二级菜单: CacheActivity 同构)
//
// Exports what the reader already has on disk. The chapter cache deliberately stores
// **未净化** raw bodies, which is exactly what an export should contain — the same rule the
// reader follows when it re-processes on open.

public enum BookExportService {

    public enum ExportError: LocalizedError {
        case noCachedContent

        public var errorDescription: String? {
            switch self {
            case .noCachedContent:
                return "这本书还没有可导出的离线缓存章节"
            }
        }
    }

    /// TXT export encodings. GB18030 covers the device side most 导出 users pair with.
    public enum TextEncoding: String, CaseIterable, Identifiable {
        case utf8 = "UTF-8"
        case utf16 = "UTF-16"
        case gb18030 = "GB18030"

        public var id: String { rawValue }

        public func encode(_ text: String) -> Data {
            switch self {
            case .utf8:
                return text.data(using: .utf8) ?? Data()
            case .utf16:
                return text.data(using: .utf16) ?? Data()
            case .gb18030:
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                let encoding = String.Encoding(rawValue: nsEncoding)
                return text.data(using: encoding) ?? (text.data(using: .utf8) ?? Data())
            }
        }
    }

    // MARK: TXT

    /// Concatenates cached chapters with their titles. Chapters without a disk cache are
    /// skipped; an export with nothing cached raises `noCachedContent`.
    public static func exportTXT(book: Book, chapters: [BookChapter],
                                 contentProvider: (Int) -> String?,
                                 encoding: TextEncoding = .utf8) throws -> URL {
        var parts: [String] = []
        parts.append("\(book.name)\n作者：\(book.author)\n")
        for chapter in chapters {
            guard let content = contentProvider(chapter.index),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            parts.append("\n\n\(chapter.title)\n\n\(content)")
        }
        guard parts.count > 1 else { throw ExportError.noCachedContent }

        let url = exportURL(fileName: sanitizeFileName("\(book.name)-\(book.author).txt"))
        try encoding.encode(parts.joined()).write(to: url)
        return url
    }

    // MARK: EPUB

    /// Composes a minimal but spec-valid EPUB3: `mimetype` stored first, container.xml,
    /// OPF package, EPUB3 nav plus an EPUB2 NCX for legacy readers, one XHTML per cached
    /// chapter. Illustrations stay behind (placeholder markers are plain text) — image
    /// export is tracked as follow-up work.
    public static func exportEPUB(book: Book, chapters: [BookChapter],
                                  contentProvider: (Int) -> String?) throws -> URL {
        var included: [(chapter: BookChapter, content: String)] = []
        for chapter in chapters {
            if let content = contentProvider(chapter.index),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                included.append((chapter, content))
            }
        }
        guard !included.isEmpty else { throw ExportError.noCachedContent }

        let url = exportURL(fileName: sanitizeFileName("\(book.name)-\(book.author).epub"))
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)

        func add(_ zipPath: String, _ data: Data, stored: Bool = false) throws {
            // addEntry(with:relativeTo:) resolves the file at `base + zipPath`, so the temp
            // file must mirror the final ZIP path (including subdirectories).
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let tmpFile = tmpDir.appendingPathComponent(zipPath)
            try FileManager.default.createDirectory(at: tmpFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: tmpFile)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            try archive.addEntry(with: zipPath, relativeTo: tmpDir, compressionMethod: stored ? .none : .deflate)
        }

        // 1. mimetype: first entry, uncompressed (OCF requires both).
        try add("mimetype", Data("application/epub+zip".utf8), stored: true)
        // 2. container.xml
        try add("META-INF/container.xml", Data(Self.containerXML.utf8))
        // 3. chapters + styles
        try add("OEBPS/style.css", Data(Self.epubCSS.utf8))
        for item in included {
            let name = "OEBPS/chapter_\(String(format: "%04d", item.chapter.index + 1)).xhtml"
            try add(name, Data(Self.chapterXHTML(title: item.chapter.title, content: item.content).utf8))
        }
        let titles = included.map { $0.chapter }
        try add("OEBPS/nav.xhtml", Data(Self.navXHTML(book: book, chapters: titles).utf8))
        try add("OEBPS/toc.ncx", Data(Self.ncxXML(book: book, chapters: titles).utf8))
        try add("OEBPS/content.opf", Data(Self.opfXML(book: book, chapters: titles).utf8))
        return url
    }

    // MARK: 书单 (bookshelf JSON)

    /// Same encoding shape as the WebDAV `bookshelf.json` member: pretty-printed, with the
    /// extra-preserving `Book` encoder flattening unknown fields back to top level.
    public static func exportBookshelfJSON(books: [Book]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(books)
        let url = exportURL(fileName: "bookshelf-\(Self.dateStamp()).json")
        try data.write(to: url)
        return url
    }

    // MARK: Helpers

    static func exportURL(fileName: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("legado-export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// Mirrors `WebDAVService.sanitizeFileName`: path separators and control chars out.
    public static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "export" : String(trimmed.prefix(80))
    }

    static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: EPUB document templates

    static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    static let epubCSS = """
    body { margin: 1em; line-height: 1.6; }
    h2 { margin: 0.6em 0 1em; font-size: 1.25em; }
    p { text-indent: 2em; margin: 0.35em 0; }
    """

    static func chapterXHTML(title: String, content: String) -> String {
        let paragraphs = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "<p>\(xmlEscape($0))</p>" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head>
          <title>\(xmlEscape(title))</title>
          <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
        <h2>\(xmlEscape(title))</h2>
        \(paragraphs)
        </body>
        </html>
        """
    }

    static func chapterHref(_ index: Int) -> String {
        "chapter_\(String(format: "%04d", index + 1)).xhtml"
    }

    static func navXHTML(book: Book, chapters: [BookChapter]) -> String {
        let items = chapters
            .map { "<li><a href=\"\(chapterHref($0.index))\">\(xmlEscape($0.title))</a></li>" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>\(xmlEscape(book.name))</title></head>
        <body>
        <nav epub:type="toc" id="toc">
          <h1>目录</h1>
          <ol>
        \(items)
          </ol>
        </nav>
        </body>
        </html>
        """
    }

    static func ncxXML(book: Book, chapters: [BookChapter]) -> String {
        let points = chapters.enumerated()
            .map { idx, chapter in
                """
                <navPoint id="np\(idx + 1)" playOrder="\(idx + 1)">
                  <navLabel><text>\(xmlEscape(chapter.title))</text></navLabel>
                  <content src="\(chapterHref(chapter.index))"/>
                </navPoint>
                """
            }
            .joined(separator: "\n")
        let uuid = CryptoUtils.md5(book.bookUrl)
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="urn:uuid:\(uuid)"/>
          </head>
          <docTitle><text>\(xmlEscape(book.name))</text></docTitle>
          <navMap>
        \(points)
          </navMap>
        </ncx>
        """
    }

    static func opfXML(book: Book, chapters: [BookChapter]) -> String {
        let manifestItems = chapters
            .map { "<item id=\"c\($0.index + 1)\" href=\"\(chapterHref($0.index))\" media-type=\"application/xhtml+xml\"/>" }
            .joined(separator: "\n")
        let spineItems = chapters
            .map { "<itemref idref=\"c\($0.index + 1)\"/>" }
            .joined(separator: "\n")
        let uuid = CryptoUtils.md5(book.bookUrl)
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(uuid)</dc:identifier>
            <dc:title>\(xmlEscape(book.name))</dc:title>
            <dc:creator>\(xmlEscape(book.author))</dc:creator>
            <dc:language>zh</dc:language>
            <meta property="dcterms:modified">\(Self.iso8601Now())</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="css" href="style.css" media-type="text/css"/>
        \(manifestItems)
          </manifest>
          <spine toc="ncx">
        \(spineItems)
          </spine>
        </package>
        """
    }

    static func iso8601Now() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

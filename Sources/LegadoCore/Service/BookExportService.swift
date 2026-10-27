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
        case imagesTooLarge
        case textEncodingUnavailable

        public var errorDescription: String? {
            switch self {
            case .noCachedContent:
                return "这本书还没有可导出的离线缓存章节"
            case .imagesTooLarge:
                return "插图资源超过单次导出限制（256 MiB）"
            case .textEncodingUnavailable:
                return "部分文字无法使用所选编码导出，请选择 UTF-8"
            }
        }
    }

    /// TXT export encodings. GB18030 covers the device side most 导出 users pair with.
    public enum TextEncoding: String, CaseIterable, Identifiable {
        case utf8 = "UTF-8"
        case utf16 = "UTF-16"
        case gb18030 = "GB18030"

        public var id: String { rawValue }

        public func encode(_ text: String) throws -> Data {
            let encoding: String.Encoding
            switch self {
            case .utf8: encoding = .utf8
            case .utf16: encoding = .utf16
            case .gb18030:
                let value = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                encoding = String.Encoding(rawValue: value)
            }
            guard let data = text.data(using: encoding, allowLossyConversion: false) else { throw ExportError.textEncodingUnavailable }
            return data
        }
    }

    public struct ExportReport {
        public let url: URL
        public let includedChapters: Int
        public let missingChapters: [BookChapter]
        public let missingImages: [String]
    }

    public static func exportTXTAsync(book: Book, chapters: [BookChapter], contentProvider: @escaping (Int) -> String?, encoding: TextEncoding = .utf8) async throws -> ExportReport {
        try Task.checkCancellation()
        return try exportTXTReport(book: book, chapters: chapters, contentProvider: contentProvider, encoding: encoding)
    }

    public static func exportEPUBAsync(book: Book, chapters: [BookChapter], contentProvider: @escaping (Int) -> String?) async throws -> ExportReport {
        try Task.checkCancellation()
        return try exportEPUBReport(book: book, chapters: chapters, contentProvider: contentProvider)
    }

    public static func exportTXTReport(book: Book, chapters: [BookChapter], contentProvider: (Int) -> String?, encoding: TextEncoding = .utf8) throws -> ExportReport {
        var snapshot: [Int: String] = [:]
        for chapter in chapters {
            try Task.checkCancellation()
            if let text = contentProvider(chapter.index), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { snapshot[chapter.index] = text }
        }
        let missing = chapters.filter { snapshot[$0.index] == nil && $0.isVolume != true }
        let url = try exportTXT(book: book, chapters: chapters, contentProvider: { snapshot[$0] }, encoding: encoding)
        return ExportReport(url: url, includedChapters: snapshot.count, missingChapters: missing, missingImages: [])
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
            try Task.checkCancellation()
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
    /// chapter. Offline image resources are embedded when available; missing content is
    /// reported explicitly by exportEPUBReport.
    public static func exportEPUB(book: Book, chapters: [BookChapter], contentProvider: (Int) -> String?) throws -> URL {
        try exportEPUBReport(book: book, chapters: chapters, contentProvider: contentProvider).url
    }

    public static func exportEPUBReport(book: Book, chapters: [BookChapter], contentProvider: (Int) -> String?,
                                        imageProvider: ((String) -> Data?)? = nil) throws -> ExportReport {
        var included: [(chapter: BookChapter, content: String)] = []
        for chapter in chapters {
            try Task.checkCancellation()
            if let content = contentProvider(chapter.index),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                included.append((chapter, content))
            }
        }
        guard !included.isEmpty else { throw ExportError.noCachedContent }

        let includedIndices = Set(included.map { $0.chapter.index })
        let missing = chapters.filter { $0.isVolume != true && !includedIndices.contains($0.index) }
        var images: [String: String] = [:]
        var resources: [(path: String, media: String, data: Data)] = []
        var missingImages: [String] = []
        var seenImages = Set<String>()
        var imageBytes = 0
        for item in included {
            try Task.checkCancellation()
            for reference in imageReferences(item.content) where seenImages.insert(reference).inserted {
                guard let data = imageProvider?(reference) ?? cachedImage(book: book, reference: reference),
                      data.count <= 24 * 1024 * 1024, let type = imageType(data) else { missingImages.append(reference); continue }
                guard imageBytes <= 256 * 1024 * 1024 - data.count else { throw ExportError.imagesTooLarge }
                imageBytes += data.count
                let path = "images/i\(resources.count).\(type.extensionName)"
                images[reference] = path
                resources.append((path, type.media, data))
            }
        }

        let url = exportURL(fileName: sanitizeFileName("\(book.name)-\(book.author).epub"))
        let archive = try Archive(url: url, accessMode: .create)
        var finished = false
        defer { if !finished { try? FileManager.default.removeItem(at: url) } }

        func add(_ zipPath: String, _ data: Data, stored: Bool = false) throws {
            try archive.addEntry(with: zipPath, type: .file, uncompressedSize: Int64(data.count), compressionMethod: stored ? .none : .deflate) { offset, size in
                try Task.checkCancellation()
                return data.subdata(in: Int(offset)..<Int(offset) + size)
            }
        }

        // 1. mimetype: first entry, uncompressed (OCF requires both).
        try add("mimetype", Data("application/epub+zip".utf8), stored: true)
        // 2. container.xml
        try add("META-INF/container.xml", Data(Self.containerXML.utf8))
        for resource in resources { try Task.checkCancellation(); try add("OEBPS/" + resource.path, resource.data) }
        // 3. chapters + styles
        try add("OEBPS/style.css", Data(Self.epubCSS.utf8))
        for item in included {
            let name = "OEBPS/chapter_\(String(format: "%04d", item.chapter.index + 1)).xhtml"
            try add(name, Data(Self.chapterXHTML(title: item.chapter.title, content: item.content, images: images).utf8))
        }
        let titles = included.map { $0.chapter }
        try add("OEBPS/nav.xhtml", Data(Self.navXHTML(book: book, chapters: titles).utf8))
        try add("OEBPS/toc.ncx", Data(Self.ncxXML(book: book, chapters: titles).utf8))
        try add("OEBPS/content.opf", Data(Self.opfXML(book: book, chapters: titles, resources: resources.map { ($0.path, $0.media) }).utf8))
        finished = true
        return ExportReport(url: url, includedChapters: included.count, missingChapters: missing, missingImages: missingImages)
    }

    // MARK: 书单 (bookshelf JSON)

    /// Android BookshelfViewModel exports search identities, not device-local URLs or progress.
    public static func exportBookshelfJSON(books: [Book]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(books.map { ShelfBookInfo(name: $0.name, author: $0.author, intro: $0.displayIntro) })
        let url = exportURL(fileName: "bookshelf-\(Self.dateStamp()).json")
        try data.write(to: url)
        return url
    }

    // MARK: Helpers

    static func exportURL(fileName: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("legado-export", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// Mirrors `WebDAVService.sanitizeFileName`: path separators and control chars out.
    public static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.controlCharacters).union(.illegalCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "export" }
        let ext = (trimmed as NSString).pathExtension
        if !ext.isEmpty, ext.count <= 10, ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            let suffix = "." + ext
            return String(trimmed.dropLast(suffix.count).prefix(80 - suffix.count)) + suffix
        }
        return String(trimmed.prefix(80))
    }

    static func imageReferences(_ content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[image:([^\]\r\n]+)\]"#) else { return [] }
        let ns = content as NSString
        return regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func imageType(_ data: Data) -> (extensionName: String, media: String)? {
        if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return ("png", "image/png") }
        if data.starts(with: [255, 216, 255]) { return ("jpg", "image/jpeg") }
        if data.starts(with: Data("GIF8".utf8)) { return ("gif", "image/gif") }
        return nil
    }

    /// Export reads existing offline bytes only. Local files must belong to this EPUB's
    /// extraction tree; a marker from a remote source cannot read arbitrary device files.
    static func cachedImage(book: Book, reference: String) -> Data? {
        guard let url = URL(string: reference) else { return nil }
        if url.isFileURL {
            guard book.isLocalBook else { return nil }
            let id = CryptoUtils.md5(book.bookUrl)
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Books/EPUB/" + id).resolvingSymlinksInPath().standardizedFileURL
            var local = url.resolvingSymlinksInPath().standardizedFileURL
            if !local.path.hasPrefix(root.path + "/"), let range = url.path.range(of: "/Books/EPUB/" + id + "/") {
                local = root.appendingPathComponent(String(url.path[range.upperBound...])).resolvingSymlinksInPath().standardizedFileURL
            }
            guard local.path.hasPrefix(root.path + "/"),
                  let size = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 24 * 1024 * 1024 else { return nil }
            return try? Data(contentsOf: local)
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data
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

    static func chapterXHTML(title: String, content: String, images: [String: String]? = nil) -> String {
        let paragraphs = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { paragraph -> String in
                guard let images = images, let regex = try? NSRegularExpression(pattern: #"\[image:([^\]\r\n]+)\]"#) else { return "<p>\(xmlEscape(paragraph))</p>" }
                let ns = paragraph as NSString
                var output = ""; var previous = 0
                for match in regex.matches(in: paragraph, range: NSRange(location: 0, length: ns.length)) {
                    output += xmlEscape(ns.substring(with: NSRange(location: previous, length: match.range.location - previous)))
                    let reference = ns.substring(with: match.range(at: 1))
                    if let path = images[reference] { output += "<img src=\"\(xmlEscape(path))\" alt=\"插图\"/>" }
                    else { output += "<span>（未导出图片）</span>" }
                    previous = match.range.location + match.range.length
                }
                output += xmlEscape(ns.substring(from: previous))
                return "<p>\(output)</p>"
            }.joined(separator: "\n")
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

    static func opfXML(book: Book, chapters: [BookChapter], resources: [(path: String, media: String)] = []) -> String {
        let manifestItems = chapters
            .map { "<item id=\"c\($0.index + 1)\" href=\"\(chapterHref($0.index))\" media-type=\"application/xhtml+xml\"/>" }
            .joined(separator: "\n")
        let imageItems = resources.enumerated().map { index, resource in
            "<item id=\"i\(index)\" href=\"\(xmlEscape(resource.path))\" media-type=\"\(resource.media)\"/>"
        }.joined(separator: "\n")
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
        \(imageItems)
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

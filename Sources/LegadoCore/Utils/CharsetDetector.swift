import Foundation

/// Resolves response bytes into a String using the same chain Android uses
/// (`OkHttpUtils.ResponseBody.text()` + `utils/EncodingDetect.kt`), minus the bundled
/// ICU4J subset: Foundation's own detector covers the GB family, and a strict-decode
/// scoring pass covers the rest. No third-party dependency.
///
/// Measured facts this implementation relies on (verified on Swift 5.7 / iOS 16 SDK):
/// - `String(data:encoding:.utf8)` returns **nil** for GBK bytes, so "does it strictly
///   decode" is a usable signal. The old `String(decoding:as:UTF8.self)` fallback is what
///   produced mojibake, because it force-substitutes invalid bytes.
/// - `NSString.stringEncoding(for:)` detects UTF-8 and GB18030 exactly, but **mislabels
///   Big5** — hence Big5 sites must be driven by an explicit `charset=` declaration.
/// - The `usedLossyConversion` out-param reads `true` for every sample tested and is
///   therefore not used as a gate.
public enum CharsetDetector {

    /// Decodes `data`. `declared` is the `charset` from the URL options; Android uses it
    /// for *request* encoding, we also honour it as a decode hint since it names the site's
    /// own encoding.
    public static func decode(_ input: Data,
                              headers: [String: String] = [:],
                              declared: String? = nil) -> String {
        let data = stripBOM(input)
        guard !data.isEmpty else { return "" }

        // 1. explicit declarations win
        for name in [declared, charset(fromHeaders: headers), charset(fromMeta: data)] {
            guard let name, let encoding = encoding(named: name) else { continue }
            if let text = String(data: data, encoding: encoding) { return text }
        }

        // 2. valid UTF-8 is decisive
        if let text = String(data: data, encoding: .utf8) { return text }

        // 3. Foundation's statistical detector
        if let detected = statisticalEncoding(for: data),
           let text = String(data: data, encoding: detected) {
            return text
        }

        // 4. score the legacy CJK candidates
        if let best = bestCandidateDecode(data) { return best }

        // 5. last resort: keep the previous behaviour rather than returning nothing
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Declaration extraction

    static func charset(fromHeaders headers: [String: String]) -> String? {
        for (key, value) in headers where key.lowercased() == "content-type" {
            return charsetValue(in: value)
        }
        return nil
    }

    private static func charsetValue(in value: String) -> String? {
        guard let range = value.range(of: "charset", options: .caseInsensitive) else { return nil }
        let tail = String(value[range.upperBound...])
        let pattern = "\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (tail as NSString).substring(with: match.range(at: 1))
    }

    /// Sniffs `<head>` for `<meta charset>` / `http-equiv` the way Android's
    /// `EncodingDetect.getHtmlEncode` does, but on the first bytes only. Non-ASCII bytes are
    /// blanked because a charset declaration is always ASCII and GBK bytes would otherwise
    /// make every decode attempt fail.
    static func charset(fromMeta data: Data) -> String? {
        let prefix = [UInt8](data.prefix(4096))
        let head = String(decoding: prefix.map { $0 < 0x80 ? $0 : 0x20 }, as: UTF8.self)
        return metaCharset(in: head)
    }

    static func metaCharset(in html: String) -> String? {
        let patterns = [
            "(?i)<meta[^>]+charset\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)",
            "(?i)<meta[^>]+content\\s*=\\s*[\"'][^\"']*charset=([A-Za-z0-9_\\-]+)"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = html as NSString
            if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    // MARK: - Detection

    static func stripBOM(_ data: Data) -> Data {
        let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == utf8BOM { return data.dropFirst(3) }
        let utf16LE: [UInt8] = [0xFF, 0xFE]
        let utf16BE: [UInt8] = [0xFE, 0xFF]
        if data.count >= 2, Array(data.prefix(2)) == utf16LE || Array(data.prefix(2)) == utf16BE {
            return data.dropFirst(2)
        }
        return data
    }

    static func statisticalEncoding(for data: Data) -> String.Encoding? {
        var lossy = ObjCBool(false)
        let raw = NSString.stringEncoding(for: data, encodingOptions: nil,
                                          convertedString: nil, usedLossyConversion: &lossy)
        guard raw != 0 else { return nil }
        return String.Encoding(rawValue: raw)
    }

    /// Legacy candidates ordered by how common they are on Chinese novel sites.
    static let candidateEncodings: [String.Encoding] = [
        gb18030, big5Encoding, .shiftJIS, eucKR, .windowsCP1252, .isoLatin1
    ]

    static func bestCandidateDecode(_ data: Data) -> String? {
        var best: (text: String, score: Double)?
        for encoding in candidateEncodings {
            guard let text = String(data: data, encoding: encoding) else { continue }
            let score = plausibility(text)
            if best == nil || score > best!.score {
                best = (text, score)
            }
        }
        return best?.text
    }

    /// Fraction of non-ASCII characters that land in a CJK block. A wrong codepage produces
    /// scattered symbol/extension glyphs instead.
    static func plausibility(_ text: String) -> Double {
        var nonAscii = 0
        var cjk = 0
        for scalar in text.unicodeScalars {
            if scalar.value < 0x80 { continue }
            nonAscii += 1
            if isCJKBlock(scalar.value) { cjk += 1 }
        }
        guard nonAscii > 0 else { return 0 }
        return Double(cjk) / Double(nonAscii)
    }

    private static func isCJKBlock(_ value: UInt32) -> Bool {
        switch value {
        case 0x3000...0x303F,   // CJK punctuation
             0x3400...0x4DBF,   // Ext A
             0x4E00...0x9FFF,   // Unified Ideographs
             0xF900...0xFAFF,   // Compatibility Ideographs
             0xFF00...0xFFEF:   // Full-width forms
            return true
        default:
            return false
        }
    }

    // MARK: - Naming

    static let gb18030 = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    static let big5Encoding = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
    static let big5HKSCS = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
    static let eucKR = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))

    /// Maps every spelling seen in the wild onto a `String.Encoding`. Normalisation drops
    /// case, `-`, `_` and spaces, so `x-gbk`, `GB2312` and `gb_18030` all collapse correctly.
    public static func encoding(named rawName: String) -> String.Encoding? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch name {
        case "utf8": return .utf8
        case "gbk", "xgbk", "gb2312", "gb18030", "csgb2312", "chinese", "gbpc": return gb18030
        case "big5", "csbig5", "big5hkscs", "cnbig5":
            return name == "big5hkscs" ? big5HKSCS : big5Encoding
        case "shiftjis", "sjis", "csshiftjis", "mskanji", "xssjis": return .shiftJIS
        case "euckr", "ksc56011987", "ksc5601", "iso2022kr", "cseuckr": return eucKR
        case "iso88591", "latin1", "l1", "csisolatin1": return .isoLatin1
        case "windows1252", "cp1252", "ansi1252": return .windowsCP1252
        case "usascii", "ascii": return .ascii
        case "utf16", "unicode", "utf16le": return .utf16
        case "utf16be": return .utf16BigEndian
        default: return nil
        }
    }
}

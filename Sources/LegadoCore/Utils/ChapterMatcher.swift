import Foundation

/// Maps a reading position from one source's table of contents onto another's.
///
/// This is a port of Android's `BookHelp.getDurChapter`, and the exact order of its steps
/// matters: a proportional guess narrows a search window, chapter *titles* are compared
/// next, chapter *numbers* rescue the cases where titles were rephrased, and only as a
/// last resort does it fall back to clamping the old index. Getting this wrong silently
/// lands the reader in the wrong chapter after 换源.
public enum ChapterMatcher {

    /// Similarity above which a title match is trusted outright.
    static let titleSimilarityThreshold = 0.96
    /// Half-width of the index window explored around the proportional guess.
    static let windowRadius = 10

    public static func mapChapter(oldIndex: Int, oldTitle: String, oldCount: Int,
                                 newTitles: [String]) -> Int {
        let newSize = newTitles.count
        guard oldIndex > 0 else { return 0 }
        guard newSize > 0 else { return oldIndex }

        let clampedOldIndex = min(oldIndex, newSize - 1)

        // Proportional estimate: the position in the old book, scaled to the new size.
        guard oldCount > 0 else { return clampedOldIndex }
        let estimate = min(newSize - 1, max(0, oldIndex * oldCount / newSize))

        let lower = max(0, min(oldIndex, estimate) - windowRadius)
        let upper = min(newSize - 1, max(oldIndex, estimate) + windowRadius)
        guard lower <= upper else { return clampedOldIndex }

        let window = Array(lower...upper)
        let pureOld = pureChapterName(oldTitle)
        let oldNumber = chapterNumber(in: oldTitle)

        // Title similarity across the window.
        var bestIndex = window.first ?? 0
        var bestSimilarity = -1.0
        for index in window {
            let similarity = jaccardSimilarity(pureOld, pureChapterName(newTitles[index]))
            // Set-based Jaccard ties often (第121章 vs 第112章 share a character set), so
            // break ties towards the proportional guess rather than the first match.
            if similarity > bestSimilarity
                || (abs(similarity - bestSimilarity) < 0.0001
                    && abs(index - estimate) < abs(bestIndex - estimate)) {
                bestSimilarity = similarity
                bestIndex = index
            }
        }
        let nameSimilarity = max(0, bestSimilarity)

        // When titles do not match well enough, try the chapter number instead.
        var chosenIndex = bestIndex
        var chosenNumber = chapterNumber(in: newTitles[bestIndex]) ?? 0
        if nameSimilarity < titleSimilarityThreshold, let wanted = oldNumber {
            var matched = false
            var smallestGap = Int.max
            var fallbackIndex = bestIndex
            var fallbackNumber = chosenNumber
            for index in window {
                guard let number = chapterNumber(in: newTitles[index]) else { continue }
                if number == wanted {
                    chosenIndex = index
                    chosenNumber = number
                    matched = true
                    break
                }
                if abs(number - wanted) < smallestGap {
                    smallestGap = abs(number - wanted)
                    fallbackIndex = index
                    fallbackNumber = number
                }
            }
            if !matched {
                chosenIndex = fallbackIndex
                chosenNumber = fallbackNumber
            }
        }

        // Android compares against 0 when either title carries no number, so a chapter
        // numbered "5" cannot be matched to an unnumbered title by this route.
        let oldNumberValue = oldNumber ?? 0
        if nameSimilarity > titleSimilarityThreshold || abs(chosenNumber - oldNumberValue) < 1 {
            return min(max(0, chosenIndex), newSize - 1)
        }
        return clampedOldIndex
    }

    /// Keeps only letters, digits and CJK characters, so "第1章" and "第 1 章" compare equal.
    public static func pureChapterName(_ title: String) -> String {
        var result = ""
        for scalar in title.unicodeScalars where isSignificant(scalar.value) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private static func isSignificant(_ value: UInt32) -> Bool {
        switch value {
        case 0x0030...0x0039,   // 0-9
             0x0041...0x005A,   // A-Z
             0x0061...0x007A,   // a-z
             0x3400...0x4DBF,   // CJK Ext A
             0x4E00...0x9FFF,   // CJK Unified
             0xF900...0xFAFF:   // CJK Compatibility
            return true
        default:
            return false
        }
    }

    /// Character-set Jaccard similarity; equals Android's `jaccardSimilarity`.
    public static func jaccardSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs.isEmpty, rhs.isEmpty { return 1 }
        let left = Set(lhs.unicodeScalars)
        let right = Set(rhs.unicodeScalars)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    /// The ordinal inside a chapter title, or nil when it has none.
    ///
    /// Android tries "第<number>[章节篇回集话]" first and then a leading number; both accept
    /// Arabic and Chinese numerals, after folding full-width digits and dropping spaces.
    public static func chapterNumber(in title: String) -> Int? {
        let normalized = foldingFullWidth(title).replacingOccurrences(of: " ", with: "")
        let digits = "\(digitCharacters())+"

        for pattern in ["第([\(digits)]+)[章节篇回集话]", "^(\\d+)"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = normalized as NSString
            guard let match = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length))
            else { continue }
            let token = ns.substring(with: match.range(at: 1))
            if let value = parseNumber(token) { return value }
        }
        return nil
    }

    private static func digitCharacters() -> String {
        "0123456789零〇一壹二两贰叁三肆肆伍五陆六柒七捌八玖九十拾百佰千仟万萬亿億"
    }

    /// Full-width digits and letters to their ASCII equivalents.
    static func foldingFullWidth(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value >= 0xFF10, value <= 0xFF19 {
                result.append(Character(UnicodeScalar(value - 0xFF10 + 0x30)!))
            } else if value >= 0xFF21, value <= 0xFF3A || value >= 0xFF41, value <= 0xFF5A {
                result.append(Character(UnicodeScalar(value - 0xFF21 + 0x41)!))
            } else {
                result.append(Character(scalar))
            }
        }
        return result
    }

    static func parseNumber(_ token: String) -> Int? {
        guard !token.isEmpty else { return nil }
        if let arabic = Int(token) { return arabic }
        return chineseNumberToInt(token)
    }

    /// Handles the cumulative forms Android's `stringToInt` covers: 二十一, 一百零五,
    /// 一千二百三十四, 一万二千, and the plain-digit form 一九三七.
    public static func chineseNumberToInt(_ text: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "〇": 0,
            "一": 1, "壹": 1,
            "二": 2, "两": 2, "贰": 2,
            "三": 3, "叁": 3,
            "四": 4, "肆": 4,
            "五": 5, "伍": 5,
            "六": 6, "陆": 6,
            "七": 7, "柒": 7,
            "八": 8, "捌": 8,
            "九": 9, "玖": 9
        ]
        let units: [Character: Int] = [
            "十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1_000, "仟": 1_000,
            "万": 10_000, "萬": 10_000, "亿": 100_000_000, "億": 100_000_000
        ]

        var total = 0        // completed sections
        var section = 0      // value below the current 万/亿 unit
        var current = 0      // digit awaiting its unit
        var sawAnything = false

        for character in text {
            if let digit = digits[character] {
                current = digit
                sawAnything = true
            } else if let unit = units[character] {
                sawAnything = true
                if unit >= 10_000 {
                    section = (section + max(current, 1)) * unit
                    total += section
                    section = 0
                } else {
                    // 十五 means 1*10, not 0*10.
                    let base = current == 0 ? 1 : current
                    section += base * unit
                }
                current = 0
            } else {
                return nil
            }
        }
        guard sawAnything else { return nil }
        return total + section + current
    }
}

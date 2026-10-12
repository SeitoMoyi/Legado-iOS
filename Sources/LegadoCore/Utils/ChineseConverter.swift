import Foundation

/// Simplified ⇄ Traditional conversion using the system's CoreFoundation transform, so no
/// dictionary file or third-party dependency is required.
///
/// Verified on Swift 5.7 / iOS 16 SDK:
/// - `StringTransform.simplifiedTraditional` does not exist as a Swift symbol; the
///   transform must be created from its name string.
/// - `"Simplified-Traditional"` with `reverse: false` is 简→繁, with `reverse: true` is
///   繁→简.
/// - Phrase handling matches Android's OpenCC output for the words in its exclusion list
///   (`列印`, `函式`, `硬碟`, `介面` stay as-is rather than collapsing to 打印/函数/硬盘/界面),
///   which is exactly what legado's `fixT2sDict()` is configured to produce.
public enum ChineseConverter {

    /// mode: 0 关闭 / 1 繁→简 / 2 简→繁 — same encoding as `AppConfig.chineseConverterType`.
    public static func convert(_ text: String, mode: Int) -> String {
        guard mode != ChineseConverterMode.off, !text.isEmpty else { return text }
        let toSimple = (mode == ChineseConverterMode.traditionalToSimple)
        return apply(text, reverse: toSimple) ?? text
    }

    private static func apply(_ text: String, reverse: Bool) -> String? {
        text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: reverse)
    }
}

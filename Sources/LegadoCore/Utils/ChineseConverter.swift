import Foundation

/// Simplified ⇄ Traditional conversion using the system's CoreFoundation transform, so no
/// dictionary file or third-party dependency is required.
///
/// Verified on Swift 5.7 / iOS 16 SDK:
/// - `StringTransform.simplifiedTraditional` does not exist as a Swift symbol; the
///   transform must be created from its name string.
/// - `"Simplified-Traditional"` with `reverse: false` is 简→繁, with `reverse: true` is
///   繁→简.
/// - Phrase handling is *not* identical to Android's OpenCC + `fixT2sDict()` output. The system
///   transform already keeps most of legado's exclusion words untouched (`列印`, `函式`, `硬碟`,
///   `介面`, `磁碟`, `光碟`, `快取`, `解析度`, `晶片`), but 23 of the 64 words in Android's list
///   still get converted (`模組`→`模组`, `變數`→`变数`, `規則`→`规则`, `離線`→`离线`,
///   `載入`→`载入`, `計程車`→`计程车`, …). Reproducing Android exactly would need the full
///   exclusion table applied as a pre-pass; until then this is a known divergence, recorded in
///   `ios/Plan.md` §二 #2.
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

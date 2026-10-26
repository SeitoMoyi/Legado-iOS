import Foundation

/// Freshness and comparison rules for the on-disk table of contents.
///
/// The reader opens from this cache (Android reads its `chapters` table the same way), so the
/// throttle that decides "is this stale enough to re-crawl" and the test that decides "did the
/// crawl actually change anything" are worth keeping in one pure, testable place: a wrong answer
/// here either hammers the source on every open or needlessly replaces the list the reader is
/// looking at.
public enum TocCache {
    /// Android's `upToc` only re-crawls when the last fetch is older than 10 minutes.
    public static let refreshInterval: TimeInterval = 10 * 60

    public static func defaultsKey(bookUrl: String) -> String {
        "legado_toc_time_" + CryptoUtils.md5(bookUrl)
    }

    public static func isStale(fetchedAt: Date?, now: Date = Date(),
                               interval: TimeInterval = refreshInterval) -> Bool {
        guard let fetchedAt else { return true }
        guard now >= fetchedAt else { return true }   // clock jumped backwards: re-crawl
        return now.timeIntervalSince(fetchedAt) >= interval
    }

    /// True when `next` is `previous` with chapters merely appended — the normal shape of a
    /// serialising book. Chapter content caches are keyed by **index**, so this is what decides
    /// whether the cached bodies still describe the right chapters. Anything else (a reorder, a
    /// chapter inserted or renamed early) shifts the meaning of every index after it and the
    /// cache has to be dropped.
    public static func isAppendOnly(_ previous: [BookChapter], _ next: [BookChapter]) -> Bool {
        guard next.count >= previous.count else { return false }
        return zip(previous, next).allSatisfy { left, right in
            left.title == right.title && left.url == right.url
        }
    }

    /// Metadata and middle-of-list changes must reach the open reader too. Index rewrites
    /// and cached bodies do not change directory identity; missing legacy flags mean false.
    public static func isSameList(_ lhs: [BookChapter], _ rhs: [BookChapter]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.title == right.title && left.url == right.url
                && (left.isVolume ?? false) == (right.isVolume ?? false)
                && (left.isVip ?? false) == (right.isVip ?? false)
                && (left.isPay ?? false) == (right.isPay ?? false)
                && (left.tag ?? "") == (right.tag ?? "")
        }
    }
}

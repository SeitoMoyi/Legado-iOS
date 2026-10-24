import Foundation

/// Lenient JSON decoding for the Legado backup interchange format.
///
/// Android serialises these models with GSON, which omits nulls and unknown fields, and
/// every key we add later is absent from archives written before it existed. Swift's
/// synthesised `init(from:)` throws on any missing non-optional key — even when the
/// property has a default — so a strict decode would silently discard restored data.
///
/// Decoding onto a fully-populated default fixes that: serialise `fallback`, overlay only
/// the keys the payload actually provides, then decode the merge. Unknown keys are dropped
/// and explicit nulls are skipped so the default survives.
public enum TolerantJSON {

    public static func decode<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> T? {
        decodeOverlayingFallback(type, from: data, fallback: fallback)
    }

    /// Extras-aware variant: unknown keys land in `extra` so they survive export/backup
    /// (Plan §二 #15). Overload resolution prefers this for conforming types.
    public static func decode<T: JSONExtraPreserving>(_ type: T.Type, from data: Data, fallback: T) -> T? {
        guard var model = decodeOverlayingFallback(type, from: data, fallback: fallback) else { return nil }
        model.absorbExtras(from: data)
        return model
    }

    static func decodeOverlayingFallback<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> T? {
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fallbackData = try? JSONEncoder().encode(fallback),
              var merged = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any]
        else {
            // Not a JSON object — nothing to merge onto; let a strict decode try anyway.
            return try? JSONDecoder().decode(type, from: data)
        }
        for (key, value) in stored where merged[key] != nil && !(value is NSNull) {
            merged[key] = value
        }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(type, from: mergedData)
    }

    /// Decodes a JSON array of objects, tolerating missing keys in every element.
    public static func decodeList<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> [T]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var result: [T] = []
        result.reserveCapacity(array.count)
        for element in array {
            guard let object = element as? [String: Any],
                  let elementData = try? JSONSerialization.data(withJSONObject: object),
                  let decoded = decode(type, from: elementData, fallback: fallback) else { continue }
            result.append(decoded)
        }
        return result
    }

    /// Extras-aware list decode: per-element capture so undeclared fields round-trip.
    public static func decodeList<T: JSONExtraPreserving>(_ type: T.Type, from data: Data, fallback: T) -> [T]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var result: [T] = []
        result.reserveCapacity(array.count)
        for element in array {
            guard let object = element as? [String: Any],
                  let elementData = try? JSONSerialization.data(withJSONObject: object),
                  var decoded = decodeOverlayingFallback(type, from: elementData, fallback: fallback) else { continue }
            decoded.absorbExtras(from: object)
            result.append(decoded)
        }
        return result
    }
}

import Foundation

/// A lossless JSON value — used to park fields the models do not declare.
///
/// `BookSource` / `RssSource` / `Book` are decoded against a `CodingKeys` whitelist, so any
/// Android-only field inside an imported payload (`concurrentRate`, `enabledCookieJar`,
/// `Book.customTag` …) would be silently dropped on the next export or WebDAV backup. Models
/// conforming to `JSONExtraPreserving` keep such keys in `extra: [String: JSONValue]` and write
/// them back **flattened** (as top-level keys, not nested under "extra") on encode, so the
/// round-trip through import → export/backup no longer loses them (Plan §二 #15).
public enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Normalizes a `JSONSerialization`-produced value. `NSNumber` needs an explicit
    /// `CFBoolean` check or every `true`/`false` lands in the numeric cases.
    public init?(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0,
                      number.doubleValue >= -9.22e18, number.doubleValue <= 9.22e18 {
                self = .int(number.int64Value)
            } else {
                self = .double(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.compactMap { JSONValue(any: $0) })
        case let object as [String: Any]:
            var mapped: [String: JSONValue] = [:]
            mapped.reserveCapacity(object.count)
            for (key, element) in object {
                if let element = JSONValue(any: element) {
                    mapped[key] = element
                }
            }
            self = .object(mapped)
        default:
            return nil
        }
    }

    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return NSNumber(value: value)
        case .double(let value): return NSNumber(value: value)
        case .string(let value): return value
        case .array(let values): return values.map { $0.anyValue }
        case .object(let values): return values.mapValues { $0.anyValue }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A `CodingKey` built from an arbitrary string, so dynamic dictionary entries can be written
/// into a keyed encoding container alongside the model's own declared keys.
struct DynamicCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) { nil }
}

/// Captures undeclared fields directly from a nested rule's decoder, including nulls.
func decodeJSONExtras(from decoder: Decoder, excluding keys: Set<String>) throws -> [String: JSONValue] {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    var extras: [String: JSONValue] = [:]
    for key in container.allKeys where !keys.contains(key.stringValue) {
        extras[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
    }
    return extras
}

/// Models that preserve fields they do not declare.
///
/// - `extra` collects raw keys outside `modeledJSONKeys` while decoding; conforming decoders
///   (TolerantJSON, the decode helpers below) fill it in automatically.
/// - Encode side flattens `extra` back to top-level keys; the `extra` key itself is never
///   serialized, and Android (GSON) reads the restored fields natively.
public protocol JSONExtraPreserving: Codable {
    var extra: [String: JSONValue] { get set }
    static var modeledJSONKeys: Set<String> { get }
}

extension JSONExtraPreserving {
    /// Moves keys the model does not declare into `extra`. The raw payload is the source of
    /// truth: entries the model dropped earlier are replaced wholesale on re-decode.
    public mutating func absorbExtras(from rawObject: [String: Any]) {
        var collected: [String: JSONValue] = [:]
        collected.reserveCapacity(rawObject.count)
        for (key, value) in rawObject where !Self.modeledJSONKeys.contains(key) {
            if let value = JSONValue(any: value) {
                collected[key] = value
            }
        }
        extra = collected
    }

    public mutating func absorbExtras(from data: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        absorbExtras(from: raw)
    }

    /// Strict decode plus extras capture — drop-in for `JSONDecoder().decode(Self.self, ...)`.
    public static func decodeWithExtras(from data: Data) -> Self? {
        guard var model = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        model.absorbExtras(from: data)
        return model
    }

    /// Import entry points accept both Android arrays and a single shared entity.
    public static func decodeListOrObjectWithExtras(from data: Data) -> [Self]? {
        if let list = decodeListWithExtras(from: data) { return list }
        return decodeWithExtras(from: data).map { [$0] }
    }

    /// Element-wise array decode plus extras capture — malformed elements are skipped instead of
    /// failing the whole list, matching Android's GSON import behaviour. Returns `nil` only when
    /// the payload is not a JSON array, so callers can distinguish invalid data from an
    /// intentionally empty list.
    public static func decodeListWithExtras(from data: Data) -> [Self]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var result: [Self] = []
        result.reserveCapacity(array.count)
        for element in array {
            guard let object = element as? [String: Any],
                  let elementData = try? JSONSerialization.data(withJSONObject: object),
                  var model = try? JSONDecoder().decode(Self.self, from: elementData) else { continue }
            model.absorbExtras(from: object)
            result.append(model)
        }
        return result
    }
}

/// Writes the model's undeclared keys back into the encoded object as top-level entries.
///
/// JSONEncoder merges the two keyed containers, so calling this after encoding the declared
/// fields produces a flat object — no nested "extra" wrapper.
public func encodeJSONExtras(_ extra: [String: JSONValue], to encoder: Encoder) throws {
    guard !extra.isEmpty else { return }
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    for (key, value) in extra {
        guard let key = DynamicCodingKey(stringValue: key) else { continue }
        try container.encode(value, forKey: key)
    }
}

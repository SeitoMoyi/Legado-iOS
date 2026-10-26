import Foundation

public enum SourceRuntimeError: LocalizedError {
    case library(String)
    case script(stage: String, message: String)
    case bridge(String)

    public var errorDescription: String? {
        switch self {
        case .library(let message): return "jsLib 加载失败：\(message)"
        case .script(let stage, let message): return "\(stage) 执行失败：\(message)"
        case .bridge(let message): return message
        }
    }
}

/// Caches library text, never live JSContext / JSValue objects. Each engine owns its globals.
/// Android accepts inline JavaScript or an ordered JSON map of absolute library URLs.
public final class SourceLibraryStore {
    public static let shared = SourceLibraryStore()
    private let cache = NSCache<NSString, NSData>()
    static let maxLibraryBytes = 1_048_576
    static let maxLibraries = 16

    public init() {
        cache.countLimit = 32
        cache.totalCostLimit = 8 * Self.maxLibraryBytes
    }

    public func clearCache() { cache.removeAllObjects() }

    func scripts(for declaration: String) throws -> [String] {
        let raw = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        guard raw.hasPrefix("{") else { return [raw] }
        guard let data = raw.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw SourceRuntimeError.library("库列表必须是名称到网址的 JSON 对象")
        }
        guard map.count <= Self.maxLibraries else {
            throw SourceRuntimeError.library("库数量超过 \(Self.maxLibraries)")
        }
        // A validated flat string map lets us recover declaration order from its JSON tokens.
        // Dictionary iteration order must not change the order of dependent libraries.
        let pattern = #""(?:[^"\\]|\\.)*"\s*:\s*("(?:[^"\\]|\\.)*")"#
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = raw as NSString
        var scripts: [String] = []
        for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            let token = Data(ns.substring(with: match.range(at: 1)).utf8)
            let urlString = try JSONDecoder().decode(String.self, from: token)
            guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else { continue }
            if let cached = cache.object(forKey: urlString as NSString) {
                scripts.append(String(decoding: cached as Data, as: UTF8.self))
                continue
            }
            // Shared libraries are downloaded without the source's login cookies or headers,
            // like Android SharedJsScope. Header evaluation itself may depend on this library.
            guard let request = NetworkClient.parseLegadoUrl(urlString),
                  let response = NetworkClient.shared.requestSync(parsed: request, handleCookies: false),
                  (200..<300).contains(response.statusCode), !response.data.isEmpty,
                  response.data.count <= Self.maxLibraryBytes else {
                throw SourceRuntimeError.library("无法下载库 \(url.host ?? "")")
            }
            let scriptData = Data(response.bodyString.utf8)
            cache.setObject(scriptData as NSData, forKey: urlString as NSString, cost: scriptData.count)
            scripts.append(response.bodyString)
        }
        return scripts
    }
}

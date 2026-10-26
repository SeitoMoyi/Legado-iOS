import Foundation

public enum RuleLinkService {
    /// Deep links contain a percent-decoded src/url parameter; ordinary HTTP links keep
    /// their query intact. Credentials and local-file schemes are never import endpoints.
    public static func resolve(_ text: String) -> URL? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = RuleSubscriptionService.validURL(clean) { return url }
        guard let components = URLComponents(string: clean),
              ["legado", "yuedu"].contains(components.scheme?.lowercased() ?? ""),
              let target = components.queryItems?.first(where: { ["src", "url"].contains($0.name.lowercased()) })?.value else { return nil }
        return RuleSubscriptionService.validURL(target)
    }

    public static func fetch(_ text: String, session: URLSession = .shared) async throws -> String {
        guard let url = resolve(text) else { throw RuleSubscriptionError.invalidURL }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw WebDAVError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, "规则下载失败")
        }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= BackupCompatibilityStore.maximumMemberSize else { throw RuleSubscriptionError.tooLarge }
        let data = try Data(contentsOf: file)
        guard let json = String(data: data, encoding: .utf8) else { throw RuleSubscriptionError.invalidData }
        let cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        switch ScanPayload.detect(cleaned) {
        case .bookSources, .rssSources, .replaceRules, .dictRules: return cleaned
        default: throw RuleSubscriptionError.invalidData
        }
    }
}

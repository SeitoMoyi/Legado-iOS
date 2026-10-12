import Foundation

/// Everything the content pipeline needs to know about one chapter.
public struct ProcessContext {
    public let bookName: String
    public let bookOrigin: String
    public let chapterTitle: String
    /// Per-book 净化 switch; nil falls back to `ReaderPrefs.replaceEnableDefault`.
    public let useReplaceRule: Bool?
    public let style: ReadStyleConfig
    public let prefs: ReaderPrefs
    /// Identifies the chapter so 「起效的替换」 can read back what just ran.
    public var cacheKey: String

    public init(bookName: String, bookOrigin: String, chapterTitle: String,
                useReplaceRule: Bool? = nil, style: ReadStyleConfig, prefs: ReaderPrefs,
                cacheKey: String = "") {
        self.bookName = bookName
        self.bookOrigin = bookOrigin
        self.chapterTitle = chapterTitle
        self.useReplaceRule = useReplaceRule
        self.style = style
        self.prefs = prefs
        self.cacheKey = cacheKey.isEmpty ? "\(bookOrigin)|\(bookName)|\(chapterTitle)" : cacheKey
    }

    public var replacesEnabled: Bool { useReplaceRule ?? prefs.replaceEnableDefault }
}

public struct ProcessedContent {
    public let title: String
    /// Title + body, newline separated — the shape Android caches.
    public let text: String
    /// Body only. The reader renders the chapter title itself, so it must not appear twice.
    public let bodyText: String
    public let lines: [String]
    /// Rules that actually changed the text, for the 「起效的替换」 panel.
    public let effectiveRules: [ReplaceRule]
    public let sameTitleRemoved: Bool

    public init(title: String, text: String, lines: [String],
                effectiveRules: [ReplaceRule], sameTitleRemoved: Bool) {
        self.title = title
        self.text = text
        self.lines = lines
        self.bodyText = lines.dropFirst().joined(separator: "\n")
        self.effectiveRules = effectiveRules
        self.sameTitleRemoved = sameTitleRemoved
    }
}

/// Port of Android `help/book/ContentProcessor.getContent`.
///
/// Step order is load-bearing — it is what makes a rule written for Android behave the
/// same here:
/// 1. strip a duplicated chapter title at the head of the body
/// 2. apply the image style
/// 3. simplified/traditional conversion
/// 4. trim every line, then apply content rules in `order` with a per-rule timeout
/// 5. apply title rules and re-attach the title
/// 6. replace `\u00A0` with a plain space
/// 7. split into lines and add the first-line indent
///
/// Deliberate departures from Android, all recorded in `ios/plan.md` §10: no `reSegment`
/// (its output depends on `Math.random()`), and a timed-out rule is disabled and dropped
/// instead of replacing the chapter with a stack trace and restarting the app.
public final class ContentProcessor {
    public static let shared = ContentProcessor()

    /// Set by the app layer so it stays the single source of truth. `nil` means read the
    /// store directly, which keeps core usable in tests and for callers outside the app.
    public var rules: [ReplaceRule]?

    /// Called when a rule is auto-disabled after a timeout, so the app can persist it.
    public var onRuleAutoDisabled: ((ReplaceRule) -> Void)?

    private var currentRules: [ReplaceRule] { rules ?? ReplaceRuleStore.load() }

    /// A concurrent queue on purpose: a catastrophic-backtracking pattern can occupy a
    /// worker forever, and a serial queue would then block every later rule.
    private let regexQueue = DispatchQueue(label: "legado.contentprocessor.regex",
                                           qos: .utility, attributes: .concurrent)

    public init() {}

    // MARK: - Last-run bookkeeping

    private var results: [String: ProcessedContent] = [:]

    /// The pipeline output for a chapter, used by 「起效的替换」 to show which rules actually
    /// changed this chapter rather than merely which ones match the book.
    public func result(forKey key: String) -> ProcessedContent? {
        results[key]
    }

    public func clearResults() {
        results.removeAll()
    }

    private func record(_ result: ProcessedContent, for key: String) {
        // Reading forward through a long book would otherwise grow this without bound.
        if results.count > 40 { results.removeAll(keepingCapacity: true) }
        results[key] = result
    }

    // MARK: - Rule selection

    /// Reproduces Android `ReplaceRuleDao.findEnabledBy{Content,Title}Scope`, which matches
    /// with SQL `LIKE '%'||name||'%'` — i.e. "the scope string *contains* the book name or
    /// the origin", not a delimited list.
    public static func matchingRules(bookName: String, bookOrigin: String,
                                     from rules: [ReplaceRule], forTitle: Bool) -> [ReplaceRule] {
        rules.filter { rule in
            guard rule.isEnabled, rule.isValid else { return false }
            if forTitle {
                guard rule.scopeTitle else { return false }
            } else {
                guard rule.scopeContent else { return false }
            }
            if let scope = rule.scope, !scope.isEmpty,
               !contains(scope, bookName), !contains(scope, bookOrigin) {
                return false
            }
            if let exclude = rule.excludeScope, !exclude.isEmpty,
               (contains(exclude, bookName) || contains(exclude, bookOrigin)) {
                return false
            }
            return true
        }
        .sorted { $0.order < $1.order }
    }

    /// `LIKE '%x%'` with an empty needle matches, mirroring SQL.
    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.localizedCaseInsensitiveContains(needle)
    }

    // MARK: - Pipeline

    public func process(rawContent: String, context: ProcessContext) async -> ProcessedContent {
        guard !rawContent.isEmpty, rawContent != "null" else {
            return ProcessedContent(title: context.chapterTitle, text: context.chapterTitle,
                                    lines: [context.chapterTitle], effectiveRules: [],
                                    sameTitleRemoved: false)
        }

        let contentRules = context.replacesEnabled
            ? Self.matchingRules(bookName: context.bookName, bookOrigin: context.bookOrigin,
                                 from: currentRules, forTitle: false)
            : []
        let titleRules = context.replacesEnabled
            ? Self.matchingRules(bookName: context.bookName, bookOrigin: context.bookOrigin,
                                 from: currentRules, forTitle: true)
            : []

        // 1. duplicated title at the head of the body
        var body = removeDuplicatedTitle(from: rawContent, title: context.chapterTitle,
                                         bookName: context.bookName)
        let sameTitleRemoved = body != rawContent
        if !sameTitleRemoved && !titleRules.isEmpty {
            // Android retries with the title *after* title rules have been applied.
            let displayed = await applyTitleRules(titleRules, to: context.chapterTitle)
            if !displayed.isEmpty, displayed != context.chapterTitle,
               let retitled = strip(body, prefix: displayed) {
                body = retitled.text
            }
        }

        // 2. images
        body = applyImageStyle(body, context.prefs.imageStyle)

        // 3. simplified / traditional
        body = ChineseConverter.convert(body, mode: context.prefs.chineseConverterType)

        // 4. trim lines then run content rules
        body = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        var effective: [ReplaceRule] = []
        for rule in contentRules {
            let outcome = await applySingle(rule, to: body)
            switch outcome {
            case .changed(let replaced):
                body = replaced
                effective.append(rule)
            case .timedOut:
                onRuleAutoDisabled?(rule)
            case .unchanged, .failed:
                break
            }
        }

        // 5. title rules + re-attach the title
        let title = await applyTitleRules(titleRules, to: context.chapterTitle)

        // 6. Android only does this on API 26-27 because of a StaticLayout crash; iOS can
        //    always normalise the non-breaking space.
        body = body.replacingOccurrences(of: "\u{00A0}", with: " ")

        // 7. split, drop empties, indent
        let lines = Self.finalizeLines(body: body, title: title, indent: context.style.paragraphIndent)
        let text = lines.joined(separator: "\n")

        let result = ProcessedContent(title: title, text: text, lines: lines,
                                      effectiveRules: effective, sameTitleRemoved: sameTitleRemoved)
        record(result, for: context.cacheKey)
        return result
    }

    static func finalizeLines(body: String, title: String, indent: String) -> [String] {
        var result = [title]
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = trimEdgeWhitespace(rawLine)
            if line.isEmpty { continue }
            result.append(indent.isEmpty ? line : indent + line)
        }
        return result
    }

    /// Android strips characters whose code is <= 0x20 and the full-width space.
    private static func trimEdgeWhitespace(_ slice: Substring) -> String {
        var text = String(slice)
        let trimSet = CharacterSet(charactersIn: " \t\n\r\u{000B}\u{000C}\u{3000}")
        text = text.trimmingCharacters(in: trimSet)
        return text
    }

    // MARK: - Individual steps

    struct StripResult { let text: String }

    func removeDuplicatedTitle(from content: String, title: String, bookName: String) -> String {
        strip(content, prefix: title, bookName: bookName)?.text ?? content
    }

    /// `^(\s|\p{P}|quote(bookName)))*<title>(\s)*` — same construction as Android.
    private func strip(_ content: String, prefix title: String, bookName: String = "") -> StripResult? {
        let namePart = bookName.isEmpty ? "" : NSRegularExpression.escapedPattern(for: bookName)
        let pattern = "^(\\s|\\p{P}|\(namePart))*" + Self.titleRegexFragment(from: title) + "(\\s)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)),
              match.range.location == 0, NSMaxRange(match.range) > 0 else { return nil }
        let trimmed = (content as NSString).substring(to: match.range.location)
            + (content as NSString).substring(from: NSMaxRange(match.range))
        return StripResult(text: trimmed)
    }

    /// Escapes a chapter title for regex use and turns whitespace runs into `\s*`, matching
    /// Android's `escapeRegex().replace(spaceRegex, "\\\\s*")`.
    static func titleRegexFragment(from title: String) -> String {
        var fragment = ""
        var sawWhitespace = false
        for scalar in title.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !sawWhitespace { fragment += "\\s*"; sawWhitespace = true }
                continue
            }
            sawWhitespace = false
            fragment += NSRegularExpression.escapedPattern(for: String(scalar))
        }
        return fragment
    }

    func applyImageStyle(_ content: String, _ style: ReadImageStyle) -> String {
        switch style {
        case .standard, .full:
            return content
        case .textOnly:
            return content
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[image:") }
                .joined(separator: "\n")
        case .singleImage:
            var seen = false
            return content
                .components(separatedBy: "\n")
                .filter { line in
                    guard line.trimmingCharacters(in: .whitespaces).hasPrefix("[image:") else { return true }
                    if seen { return false }
                    seen = true
                    return true
                }
                .joined(separator: "\n")
        }
    }

    enum RuleOutcome {
        case changed(String)
        case unchanged
        case timedOut
        case failed
    }

    /// Runs one rule against `text`, aborting after the rule's own timeout.
    private func applySingle(_ rule: ReplaceRule, to text: String) async -> RuleOutcome {
        guard !rule.pattern.isEmpty else { return .unchanged }
        let timeout = rule.effectiveTimeout

        return await withTaskGroup(of: RuleOutcome.self) { group in
            group.addTask {
                await self.runRegex(rule: rule, text: text)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
                return .timedOut
            }
            let outcome = await group.next() ?? .unchanged
            group.cancelAll()
            return outcome
        }
    }

    /// Applies the title-scoped rules. A replacement that leaves nothing is discarded, which
    /// is Android's behaviour: a chapter cannot be titled "".
    private func applyTitleRules(_ rules: [ReplaceRule], to text: String) async -> String {
        var result = text
        for rule in rules {
            guard case .changed(let replaced) = await applySingle(rule, to: result) else { continue }
            if replaced.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            result = replaced
        }
        return result
    }

    private func runRegex(rule: ReplaceRule, text: String) async -> RuleOutcome {
        await withCheckedContinuation { continuation in
            regexQueue.async {
                continuation.resume(returning: Self.applyRuleSync(rule, to: text))
            }
        }
    }

    static func applyRuleSync(_ rule: ReplaceRule, to text: String) -> RuleOutcome {
        if rule.replacement.hasPrefix("@js:") {
            return replaceWithJS(rule: rule, text: text)
        }
        guard rule.isRegex else {
            guard text.range(of: rule.pattern) != nil else { return .unchanged }
            return .changed(text.replacingOccurrences(of: rule.pattern, with: rule.replacement))
        }
        guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return .failed }
        let ns = text as NSString
        // `$1` / `\1` group references are handled by stringByReplacingMatches.
        let result = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length),
                                                   withTemplate: rule.replacement)
        return result == text ? .unchanged : .changed(result)
    }

    /// `replacement` starting with `@js:` is evaluated per match with `result` bound to the
    /// matched text, as Android does.
    private static func replaceWithJS(rule: ReplaceRule, text: String) -> RuleOutcome {
        guard rule.isRegex, let regex = try? NSRegularExpression(pattern: rule.pattern) else {
            return .failed
        }
        let script = String(rule.replacement.dropFirst(4))
        let engine = JSEngine()
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let matched = ns.substring(with: match.range)
            if let value = engine.eval(script: script, result: matched) {
                result += "\(value)"
            } else {
                result += matched
            }
            cursor = NSMaxRange(match.range)
        }
        result += ns.substring(from: cursor)
        return result == text ? .unchanged : .changed(result)
    }
}

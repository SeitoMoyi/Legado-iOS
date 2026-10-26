import Foundation
import SwiftSoup

public class RuleAnalyzer {
    public let content: Any
    public let baseUrl: String?
    public let jsEngine: JSEngine

    private var parsedDocument: Document?
    private var parsedJson: Any?

    public init(content: Any, baseUrl: String? = nil, bookSource: BookSource? = nil, jsEngine: JSEngine? = nil) {
        self.content = content
        self.baseUrl = baseUrl
        self.jsEngine = jsEngine ?? JSEngine(bookSource: bookSource, baseUrl: baseUrl)

        if let stringContent = content as? String {
            let trimmed = stringContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.starts(with: "{") && trimmed.hasSuffix("}")) ||
               (trimmed.starts(with: "[") && trimmed.hasSuffix("]")),
               let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                self.parsedJson = json
            } else {
                self.parsedDocument = try? SwiftSoup.parse(stringContent, baseUrl ?? "")
            }
        } else if let dict = content as? [String: Any] {
            self.parsedJson = dict
        } else if let array = content as? [Any] {
            self.parsedJson = array
        }
    }

    /// Resolves relative URLs using baseUrl
    public func resolveUrl(_ urlString: String) -> String {
        guard let base = baseUrl, let baseUrlObj = URL(string: base) else {
            return urlString
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.starts(with: "http://") || trimmed.starts(with: "https://") {
            return trimmed
        }
        return URL(string: trimmed, relativeTo: baseUrlObj)?.absoluteString ?? trimmed
    }

    /// Evaluates template expressions with {{...}} placeholders
    public func evaluateTemplate(_ template: String) -> String {
        var result = template
        let pattern = "\\{\\{(.*?)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: (template as NSString).length))

        for match in matches.reversed() {
            let fullRange = match.range
            let innerRange = match.range(at: 1)
            let innerExpr = (template as NSString).substring(with: innerRange).trimmingCharacters(in: .whitespacesAndNewlines)

            var evaluatedValue = ""
            if (innerExpr.starts(with: "'") && innerExpr.hasSuffix("'")) || (innerExpr.starts(with: "\"") && innerExpr.hasSuffix("\"")) {
                evaluatedValue = String(innerExpr.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\t", with: "\t")
            } else if innerExpr.starts(with: "java.") || innerExpr.starts(with: "source.") || innerExpr.starts(with: "book.") {
                let jsRes = jsEngine.eval(script: innerExpr, result: content)
                evaluatedValue = jsRes.map(JSEngine.stringValue) ?? ""
            } else {
                evaluatedValue = getString(innerExpr)
            }

            result = (result as NSString).replacingCharacters(in: fullRange, with: evaluatedValue)
        }
        return result
    }

    /// Evaluates a rule string and returns a single string result
    public func getString(_ rule: String?, isUrl: Bool = false) -> String {
        guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else {
            return ""
        }

        // Handle JS scripts: with or without rule prefix
        let (rulePrefix, jsScript) = JSEngine.splitJSRule(rule)

        if let script = jsScript {
            var targetContent: Any? = content
            if !rulePrefix.isEmpty {
                let prefixVal = getString(rulePrefix, isUrl: false)
                if !prefixVal.isEmpty {
                    targetContent = prefixVal
                }
            }
            let evalResult = jsEngine.eval(script: evaluateTemplate(script), result: targetContent)
            let resStr = evalResult.map(JSEngine.stringValue) ?? ""
            return isUrl ? resolveUrl(resStr) : resStr
        }

        // Templates inside a script are inputs to its execution, not a literal rule result.
        // Expand only the script body above so quoted literals such as '<js>' cannot
        // accidentally change the rule's wrapper during interpolation.
        // Handle template expressions {{...}}
        if rule.contains("{{") && rule.contains("}}") {
            let expanded = evaluateTemplate(rule)
            return isUrl ? resolveUrl(expanded) : expanded
        }

        // Handle fallback operator: rule1 || rule2
        if rule.contains("||") {
            let options = rule.components(separatedBy: "||")
            for option in options {
                let res = getString(option.trimmingCharacters(in: .whitespacesAndNewlines), isUrl: isUrl)
                if !res.isEmpty {
                    return res
                }
            }
            return ""
        }

        // Handle concatenation operator: rule1 && rule2
        if rule.contains("&&") {
            let segments = rule.components(separatedBy: "&&")
            let combined = segments.map { getString($0.trimmingCharacters(in: .whitespacesAndNewlines), isUrl: isUrl) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return combined
        }

        let list = getStringList(rule, isUrl: isUrl)
        return list.first ?? ""
    }

    /// Evaluates a rule string and returns a list of string results
    public func getStringList(_ rule: String?, isUrl: Bool = false) -> [String] {
        guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else {
            return []
        }

        // If pure JS: @js:script or <js>...</js>
        if rule.starts(with: "@js:") {
            let script = String(rule.dropFirst(4))
            let evalResult = jsEngine.eval(script: evaluateTemplate(script), result: content)
            if let arr = evalResult as? [Any] {
                return arr.map { isUrl ? resolveUrl(JSEngine.stringValue($0)) : JSEngine.stringValue($0) }
            } else if let single = evalResult {
                let str = JSEngine.stringValue(single)
                return [isUrl ? resolveUrl(str) : str]
            }
            return []
        } else if let script = JSEngine.extractJSScript(from: rule) {
            let evalResult = jsEngine.eval(script: evaluateTemplate(script), result: content)
            if let arr = evalResult as? [Any] {
                return arr.map { isUrl ? resolveUrl(JSEngine.stringValue($0)) : JSEngine.stringValue($0) }
            } else if let single = evalResult {
                let str = JSEngine.stringValue(single)
                return [isUrl ? resolveUrl(str) : str]
            }
            return []
        }

        let steps = RuleTokenizer.parse(rule)
        var currentValues: [Any] = []

        // Root evaluation
        let jsonTarget: Any? = parsedJson ?? (content as? [String: Any])
        if let json = jsonTarget {
            let candidatePaths = [rule, "$.\(rule)"]
            for p in candidatePaths {
                if let val = JSONPath.evaluate(path: p, json: json) {
                    if let arr = val as? [Any] {
                        currentValues = arr
                    } else {
                        currentValues = [val]
                    }
                    break
                }
            }
            if currentValues.isEmpty {
                currentValues = evaluateJsonSteps(steps: steps, json: json)
            }
        } else if let doc = parsedDocument {
            currentValues = evaluateHtmlSteps(steps: steps, element: doc)
        } else if let element = content as? Element {
            currentValues = evaluateHtmlSteps(steps: steps, element: element)
        }

        // Apply remaining steps: JS, regex, attribute
        return currentValues.map { val in
            var text = "\(val)"
            for step in steps {
                switch step.type {
                case .regex(let pattern, let replacement):
                    if let rx = try? NSRegularExpression(pattern: pattern) {
                        text = rx.stringByReplacingMatches(
                            in: text,
                            range: NSRange(location: 0, length: (text as NSString).length),
                            withTemplate: replacement
                        )
                    }
                case .js(let script):
                    let res = jsEngine.eval(script: script, result: text)
                    if let res = res {
                        text = JSEngine.stringValue(res)
                    }
                default:
                    break
                }
            }
            return isUrl ? resolveUrl(text) : text
        }
    }

    /// Evaluates a rule that returns multiple elements/objects (e.g. book list, chapter list)
    public func getElements(_ rule: String?) -> [Any] {
        guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else {
            return []
        }

        let (rulePrefix, jsScript) = JSEngine.splitJSRule(rule)

        if let script = jsScript {
            var targetContent: Any? = content
            if !rulePrefix.isEmpty {
                let prefixAnalyzer = RuleAnalyzer(content: content, baseUrl: baseUrl, jsEngine: jsEngine)
                let prefixElements = prefixAnalyzer.getElements(rulePrefix)
                if !prefixElements.isEmpty {
                    targetContent = prefixElements
                }
            }
            if let evalResult = jsEngine.eval(script: evaluateTemplate(script), result: targetContent) {
                if let array = evalResult as? [Any] {
                    return array
                } else if let dict = evalResult as? [String: Any] {
                    return [dict]
                } else if let text = evalResult as? String {
                    // ruleBookInfo.init commonly returns a transformed JSON / HTML string.
                    return [text]
                }
            }
            return []
        }

        // If JSON content, prioritize JSONPath / JSON key lookup
        let jsonTarget: Any? = parsedJson ?? (content as? [String: Any]) ?? (content as? [Any])
        if let json = jsonTarget {
            let candidatePaths = [rule, "$.\(rule)"]
            for p in candidatePaths {
                if let evaluated = JSONPath.evaluate(path: p, json: json) {
                    if let array = evaluated as? [Any] {
                        return array
                    } else if let dict = evaluated as? [String: Any] {
                        return [dict]
                    }
                }
            }
        }

        let steps = RuleTokenizer.parse(rule)
        guard let firstStep = steps.first else { return [] }

        switch firstStep.type {
        case .jsonPath(let path):
            if let json = jsonTarget {
                let evaluated = JSONPath.evaluate(path: path, json: json)
                if let array = evaluated as? [Any] {
                    return array
                } else if let dict = evaluated as? [String: Any] {
                    return [dict]
                }
            }
        default:
            break
        }

        // HTML multi-step chained CSS selection
        if parsedDocument != nil || content is Element {
            var currentElements: [Element] = []
            if let doc = parsedDocument {
                currentElements = [doc]
            } else if let el = content as? Element {
                currentElements = [el]
            }

            for step in steps {
                switch step.type {
                case .css(let selector):
                    var next: [Element] = []
                    for el in currentElements {
                        next.append(contentsOf: selectElements(from: el, selector: selector))
                    }
                    currentElements = next
                case .xpath(let expr):
                    var next: [Element] = []
                    for el in currentElements {
                        next.append(contentsOf: evaluateXPathElements(expr, root: el))
                    }
                    currentElements = next
                default:
                    break
                }
            }
            if !currentElements.isEmpty {
                return currentElements
            }
        }

        return []
    }

    /// Selects elements from a parent element given a selector, supporting Legado's `tag.index` syntax (e.g. `li.1`, `a.-1`)
    private func selectElements(from element: Element, selector: String) -> [Element] {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([a-zA-Z0-9_\-\*]+)\.(-?\d+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) {
            if let tagRange = Range(match.range(at: 1), in: trimmed),
               let indexRange = Range(match.range(at: 2), in: trimmed),
               let index = Int(trimmed[indexRange]) {
                let tag = String(trimmed[tagRange])
                if let selected = try? element.select(tag) {
                    let all = selected.array()
                    if index >= 0 && index < all.count {
                        return [all[index]]
                    } else if index < 0 && (all.count + index) >= 0 {
                        return [all[all.count + index]]
                    } else {
                        return []
                    }
                }
            }
        }

        if let selected = try? element.select(trimmed) {
            return selected.array()
        }
        return []
    }

    private func evaluateJsonSteps(steps: [RuleStep], json: Any) -> [Any] {
        guard let first = steps.first else { return [] }
        var resultList: [Any] = []

        if case .jsonPath(let path) = first.type {
            if let evalResult = JSONPath.evaluate(path: path, json: json) {
                if let array = evalResult as? [Any] {
                    resultList = array
                } else {
                    resultList = [evalResult]
                }
            }
        }

        return resultList
    }

    private func evaluateHtmlSteps(steps: [RuleStep], element: Element) -> [Any] {
        var elements: [Element] = [element]
        var implicitAttribute: String? = nil

        for step in steps {
            switch step.type {
            case .css(let selector):
                var next: [Element] = []
                for el in elements {
                    let found = selectElements(from: el, selector: selector)
                    if found.isEmpty {
                        if (try? el.iS(selector)) == true {
                            next.append(el)
                        }
                    } else {
                        next.append(contentsOf: found)
                    }
                }
                elements = next
            case .xpath(let expr):
                let (cleanExpr, extractedAttr) = stripXPathTerminalExtractor(expr)
                if let attr = extractedAttr {
                    implicitAttribute = attr
                }
                var next: [Element] = []
                for el in elements {
                    next.append(contentsOf: evaluateXPathElements(cleanExpr, root: el))
                }
                elements = next
            default:
                break
            }
        }

        // Check if an explicit attribute step or XPath terminal extractor is requested
        let explicitAttr: String? = steps.compactMap {
            if case .attribute(let a) = $0.type { return a }
            return nil
        }.first ?? implicitAttribute

        if let attr = explicitAttr {
            return elements.compactMap { el in
                switch attr {
                case "text":
                    return (try? el.text()) ?? ""
                case "textnodes", "own_text":
                    let nodes = el.textNodes()
                    if !nodes.isEmpty {
                        return nodes.map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    }
                    return (try? el.text()) ?? ""
                case "html", "node":
                    return (try? el.html()) ?? ""
                case "outerhtml", "all":
                    return (try? el.outerHtml()) ?? ""
                case "href":
                    return (try? el.attr("href")) ?? ""
                case "src":
                    return (try? el.attr("src")) ?? ""
                default:
                    if attr.starts(with: "attr(") && attr.hasSuffix(")") {
                        let attrName = String(attr.dropFirst(5).dropLast())
                        return try? el.attr(attrName)
                    }
                    return try? el.attr(attr)
                }
            }
        }

        return elements.compactMap { try? $0.text() }
    }
    // MARK: - Lightweight XPath Evaluator over SwiftSoup

    /// Strips trailing `/text()`, `/node()`, `/all()`, or `/@attr` from an XPath expression.
    private func stripXPathTerminalExtractor(_ expr: String) -> (String, String?) {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes: [(String, String)] = [
            ("//text()", "text"),
            ("/text()", "text"),
            ("/node()", "html"),
            ("/all()", "outerhtml")
        ]
        for (suf, mapped) in suffixes {
            if trimmed.lowercased().hasSuffix(suf) {
                let base = String(trimmed.dropLast(suf.count))
                return (base.isEmpty ? "." : base, mapped)
            }
        }
        // Check trailing `/@attrName` outside brackets
        if let slashAtRange = trimmed.range(of: #"/@([a-zA-Z0-9_\-:]+)$"#, options: .regularExpression) {
            let attrName = String(trimmed[slashAtRange].dropFirst(2))
            let base = String(trimmed[..<slashAtRange.lowerBound])
            return (base.isEmpty ? "." : base, attrName)
        }
        return (trimmed, nil)
    }

    /// Evaluates XPath expressions (supporting union `|`, `//`, `/`, predicates `[@id=...]`,
    /// `[contains(@class,...)]`, `[N]`, `[last()]`, etc.) against a SwiftSoup `Element`.
    private func evaluateXPathElements(_ rawXPath: String, root: Element) -> [Element] {
        let (exprWithoutTerminal, _) = stripXPathTerminalExtractor(rawXPath)
        let unionBranches = splitTopLevelXPath(exprWithoutTerminal, delimiter: "|")
        if unionBranches.count > 1 {
            var combined: [Element] = []
            for branch in unionBranches {
                combined.append(contentsOf: evaluateSingleXPath(branch, root: root))
            }
            return combined
        }
        return evaluateSingleXPath(exprWithoutTerminal, root: root)
    }

    private func evaluateSingleXPath(_ raw: String, root: Element) -> [Element] {
        var expr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.isEmpty || expr == "." { return [root] }

        // Handle grouped index like `(//div[@class='item'])[1]`
        var outerPredicate: String? = nil
        if expr.hasPrefix("("), let closeParen = findMatchingParen(in: expr) {
            let afterParen = String(expr[expr.index(after: closeParen)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if afterParen.hasPrefix("[") && afterParen.hasSuffix("]") {
                outerPredicate = String(afterParen.dropFirst().dropLast())
                expr = String(expr[expr.index(after: expr.startIndex)..<closeParen])
            }
        }

        let segments = parseXPathAxisSteps(expr)
        var current: [Element] = [root]

        for seg in segments {
            var nextBatch: [Element] = []
            for contextEl in current {
                let candidates = collectXPathAxisCandidates(axis: seg.axis, tag: seg.tag, from: contextEl)
                let filtered = applyXPathPredicates(seg.predicates, to: candidates)
                nextBatch.append(contentsOf: filtered)
            }
            current = nextBatch
            if current.isEmpty { break }
        }

        if let outer = outerPredicate {
            current = applyXPathPredicates([outer], to: current)
        }
        return current
    }

    private struct XPathSegment {
        let axis: String // "//", "/", "."
        let tag: String
        let predicates: [String]
    }

    private func parseXPathAxisSteps(_ expr: String) -> [XPathSegment] {
        var s = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("./") {
            s = String(s.dropFirst(1))
        } else if !s.hasPrefix("/") {
            s = "//" + s
        }

        var segments: [XPathSegment] = []
        var idx = s.startIndex

        while idx < s.endIndex {
            var axis = "/"
            if s[idx...].hasPrefix("//") {
                axis = "//"
                idx = s.index(idx, offsetBy: 2)
            } else if s[idx] == "/" {
                axis = "/"
                idx = s.index(after: idx)
            }

            // Read step until next top-level `/`
            let stepStart = idx
            var bracketDepth = 0
            var inSingle = false
            var inDouble = false
            while idx < s.endIndex {
                let ch = s[idx]
                if ch == "'" && !inDouble { inSingle.toggle() }
                else if ch == "\"" && !inSingle { inDouble.toggle() }
                else if !inSingle && !inDouble {
                    if ch == "[" { bracketDepth += 1 }
                    else if ch == "]" { bracketDepth = max(0, bracketDepth - 1) }
                    else if ch == "/" && bracketDepth == 0 { break }
                }
                idx = s.index(after: idx)
            }

            let rawStep = String(s[stepStart..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rawStep.isEmpty { continue }
            let (tag, preds) = splitXPathStepTagAndPredicates(rawStep)
            segments.append(XPathSegment(axis: axis, tag: tag, predicates: preds))
        }
        return segments
    }

    private func splitXPathStepTagAndPredicates(_ step: String) -> (String, [String]) {
        guard let firstBracket = step.firstIndex(of: "[") else {
            return (step, [])
        }
        let tag = String(step[..<firstBracket]).trimmingCharacters(in: .whitespacesAndNewlines)
        var preds: [String] = []
        var idx = firstBracket
        while idx < step.endIndex {
            if step[idx] == "[" {
                let contentStart = step.index(after: idx)
                var depth = 1
                var inSingle = false
                var inDouble = false
                var cur = contentStart
                while cur < step.endIndex && depth > 0 {
                    let c = step[cur]
                    if c == "'" && !inDouble { inSingle.toggle() }
                    else if c == "\"" && !inSingle { inDouble.toggle() }
                    else if !inSingle && !inDouble {
                        if c == "[" { depth += 1 }
                        else if c == "]" { depth -= 1 }
                    }
                    if depth > 0 {
                        cur = step.index(after: cur)
                    }
                }
                let pred = String(step[contentStart..<cur]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !pred.isEmpty { preds.append(pred) }
                idx = cur < step.endIndex ? step.index(after: cur) : step.endIndex
            } else {
                idx = step.index(after: idx)
            }
        }
        return (tag.isEmpty ? "*" : tag, preds)
    }

    private func collectXPathAxisCandidates(axis: String, tag: String, from element: Element) -> [Element] {
        if tag == "." { return [element] }
        if tag == ".." {
            if let parent = element.parent() { return [parent] }
            return []
        }
        let cleanTag = tag.isEmpty ? "*" : tag
        if axis == "//" {
            if let all = try? element.getElementsByTag(cleanTag == "*" ? "*" : cleanTag) {
                // Exclude `element` itself from descendant axis unless element is Document
                return all.array().filter { $0 !== element }
            }
            if cleanTag == "*", let all = try? element.getAllElements() {
                return all.array().filter { $0 !== element }
            }
            return []
        } else {
            // Direct children (`/`)
            var children = element.children().array()
            // When root is Document and path starts with `/html/...`, `Document`'s child is `<html>`
            if cleanTag != "*" {
                children = children.filter { $0.tagName().lowercased() == cleanTag.lowercased() }
            }
            return children
        }
    }

    private func applyXPathPredicates(_ predicates: [String], to elements: [Element]) -> [Element] {
        var current = elements
        for rawPred in predicates {
            let pred = rawPred.trimmingCharacters(in: .whitespacesAndNewlines)
            if pred.isEmpty { continue }

            // 1. Positional index: `1`, `2`, `position()=1`, `last()`, `last()-1`, `position()>1`
            if let index = Int(pred) {
                // XPath is 1-based
                let zeroBased = index - 1
                if zeroBased >= 0 && zeroBased < current.count {
                    current = [current[zeroBased]]
                } else {
                    current = []
                }
                continue
            }
            if pred == "last()" {
                current = current.last.map { [$0] } ?? []
                continue
            }
            if pred.hasPrefix("last()-"), let offset = Int(pred.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                let target = current.count - 1 - offset
                current = (target >= 0 && target < current.count) ? [current[target]] : []
                continue
            }
            if pred.hasPrefix("position()") {
                let rest = pred.dropFirst(10).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("="), let idx = Int(rest.dropFirst().trimmingCharacters(in: .whitespaces)) {
                    current = (idx >= 1 && idx <= current.count) ? [current[idx - 1]] : []
                    continue
                } else if rest.hasPrefix(">"), let idx = Int(rest.dropFirst().trimmingCharacters(in: .whitespaces)) {
                    current = idx < current.count ? Array(current[idx...]) : []
                    continue
                } else if rest.hasPrefix("<"), let idx = Int(rest.dropFirst().trimmingCharacters(in: .whitespaces)) {
                    current = idx > 1 ? Array(current.prefix(idx - 1)) : []
                    continue
                }
            }

            // 2. Boolean filter per element
            current = current.filter { matchesXPathPredicate(pred, element: $0) }
        }
        return current
    }

    private func matchesXPathPredicate(_ pred: String, element: Element) -> Bool {
        // Handle `and` / `or`
        let orParts = splitTopLevelXPath(pred, delimiter: " or ")
        if orParts.count > 1 {
            return orParts.contains { matchesXPathPredicate($0, element: element) }
        }
        let andParts = splitTopLevelXPath(pred, delimiter: " and ")
        if andParts.count > 1 {
            return andParts.allSatisfy { matchesXPathPredicate($0, element: element) }
        }

        let trimmed = pred.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("not(") && trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst(4).dropLast())
            return !matchesXPathPredicate(inner, element: element)
        }

        // `contains(@attr, 'val')` or `contains(text(), 'val')` or `contains(., 'val')`
        if trimmed.hasPrefix("contains(") && trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst(9).dropLast())
            let args = splitTopLevelXPath(inner, delimiter: ",")
            if args.count == 2 {
                let lhs = evaluateXPathStringValue(args[0], element: element)
                let rhs = unquoteXPathLiteral(args[1])
                return lhs.contains(rhs)
            }
        }

        // `starts-with(@attr, 'val')`
        if trimmed.hasPrefix("starts-with(") && trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst(12).dropLast())
            let args = splitTopLevelXPath(inner, delimiter: ",")
            if args.count == 2 {
                let lhs = evaluateXPathStringValue(args[0], element: element)
                let rhs = unquoteXPathLiteral(args[1])
                return lhs.hasPrefix(rhs)
            }
        }

        // `@attr != 'val'` or `@attr = 'val'`
        if let neqRange = trimmed.range(of: "!=") {
            let lhs = evaluateXPathStringValue(String(trimmed[..<neqRange.lowerBound]), element: element)
            let rhs = unquoteXPathLiteral(String(trimmed[neqRange.upperBound...]))
            return lhs != rhs
        }
        if let eqRange = trimmed.range(of: "=") {
            let lhs = evaluateXPathStringValue(String(trimmed[..<eqRange.lowerBound]), element: element)
            let rhs = unquoteXPathLiteral(String(trimmed[eqRange.upperBound...]))
            return lhs == rhs
        }

        // Bare `@attr` existence check: `[@href]`
        if trimmed.hasPrefix("@") {
            let attrName = String(trimmed.dropFirst())
            return element.hasAttr(attrName)
        }

        // Bare child tag existence check: `[a]` or `[span[@class='x']]`
        return !evaluateSingleXPath(trimmed, root: element).isEmpty
    }

    private func evaluateXPathStringValue(_ expr: String, element: Element) -> String {
        let t = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@") {
            let attr = String(t.dropFirst())
            return (try? element.attr(attr)) ?? ""
        }
        if t == "text()" || t == "." {
            return (try? element.text()) ?? ""
        }
        return unquoteXPathLiteral(t)
    }

    private func unquoteXPathLiteral(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("'") && t.hasSuffix("'")) || (t.hasPrefix("\"") && t.hasSuffix("\"")) {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    private func findMatchingParen(in s: String) -> String.Index? {
        var depth = 0
        var inSingle = false
        var inDouble = false
        var idx = s.startIndex
        while idx < s.endIndex {
            let c = s[idx]
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if !inSingle && !inDouble {
                if c == "(" { depth += 1 }
                else if c == ")" {
                    depth -= 1
                    if depth == 0 { return idx }
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    private func splitTopLevelXPath(_ s: String, delimiter: String) -> [String] {
        var results: [String] = []
        var bracketDepth = 0
        var parenDepth = 0
        var inSingle = false
        var inDouble = false
        var segmentStart = s.startIndex
        var idx = s.startIndex

        while idx < s.endIndex {
            let c = s[idx]
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if !inSingle && !inDouble {
                if c == "[" { bracketDepth += 1 }
                else if c == "]" { bracketDepth = max(0, bracketDepth - 1) }
                else if c == "(" { parenDepth += 1 }
                else if c == ")" { parenDepth = max(0, parenDepth - 1) }
                else if bracketDepth == 0 && parenDepth == 0 && s[idx...].hasPrefix(delimiter) {
                    results.append(String(s[segmentStart..<idx]))
                    idx = s.index(idx, offsetBy: delimiter.count)
                    segmentStart = idx
                    continue
                }
            }
            idx = s.index(after: idx)
        }
        results.append(String(s[segmentStart..<s.endIndex]))
        return results
    }
}

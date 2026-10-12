import Foundation

public struct RuleStep: Equatable {
    public enum StepType: Equatable {
        case css(String)
        case jsonPath(String)
        case xpath(String)
        case regex(pattern: String, replacement: String)
        case js(String)
        case attribute(String) // e.g. text, html, href, src
    }

    public let type: StepType
}

public class RuleTokenizer {

    public static func parse(_ rawRule: String) -> [RuleStep] {
        var trimmed = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        // Check for regex replacement at the end: e.g. rule##regex##replacement
        var regexReplacements: [RuleStep] = []
        if let hashRange = trimmed.range(of: "##") {
            let rulePart = String(trimmed[..<hashRange.lowerBound])
            let regexPart = String(trimmed[hashRange.upperBound...])
            let regexSegments = regexPart.components(separatedBy: "##")
            if !regexSegments.isEmpty {
                let pattern = regexSegments[0]
                let replacement = regexSegments.count > 1 ? regexSegments[1] : ""
                regexReplacements.append(RuleStep(type: .regex(pattern: pattern, replacement: replacement)))
                trimmed = rulePart
            }
        }

        // Split by '@js:' or '<js>'
        var jsStep: RuleStep? = nil
        if let jsRange = trimmed.range(of: "@js:") {
            let rulePart = String(trimmed[..<jsRange.lowerBound])
            let script = String(trimmed[jsRange.upperBound...])
            jsStep = RuleStep(type: .js(script))
            trimmed = rulePart
        } else if let openTag = trimmed.range(of: "<js>"),
                  let closeTag = trimmed.range(of: "</js>") {
            let script = String(trimmed[openTag.upperBound..<closeTag.lowerBound])
            jsStep = RuleStep(type: .js(script))
            let beforeTag = String(trimmed[..<openTag.lowerBound])
            trimmed = beforeTag
        }

        let lowerTrimmed = trimmed.lowercased()
        var forceXPath = false
        if lowerTrimmed.hasPrefix("@xpath:") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            forceXPath = true
        }

        var steps: [RuleStep] = []
        let knownAttributes: Set<String> = ["text", "textnodes", "html", "href", "src", "title", "content"]

        if forceXPath || trimmed.hasPrefix("//") || trimmed.hasPrefix("/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("(/") || trimmed.hasPrefix("(//") {
            // XPath expressions can contain `@attr` inside predicates like `//div[@class='a']/@href`.
            // Only split a trailing `@attr` that is outside `[...]` brackets if used in Legado chained style.
            let (xpathExpr, trailingAttr) = splitTrailingLegadoAttrFromXPath(trimmed, knownAttributes: knownAttributes)
            steps.append(RuleStep(type: .xpath(xpathExpr)))
            if let attr = trailingAttr {
                steps.append(RuleStep(type: .attribute(attr)))
            }
        } else {
            // Split by '@'
            let parts = trimmed.components(separatedBy: "@")
            for (index, part) in parts.enumerated() {
                let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if token.isEmpty { continue }

                let lower = token.lowercased()
                let isAttr = knownAttributes.contains(lower) || lower.starts(with: "attr(")

                if index == 0 {
                    // Determine root type
                    if isAttr {
                        steps.append(RuleStep(type: .attribute(lower)))
                    } else if token.starts(with: "$.") || token.starts(with: "$[") {
                        steps.append(RuleStep(type: .jsonPath(token)))
                    } else {
                        steps.append(RuleStep(type: .css(token)))
                    }
                } else {
                    // Secondary steps can be attributes or sub-selectors
                    if isAttr {
                        steps.append(RuleStep(type: .attribute(lower)))
                    } else {
                        steps.append(RuleStep(type: .css(token)))
                    }
                }
            }
        }
        if let js = jsStep {
            steps.append(js)
        }
        steps.append(contentsOf: regexReplacements)

        return steps
    }

    /// Splits a Legado-style trailing `@text` / `@href` off an XPath expression without breaking
    /// `[@id='foo']` predicates or `/@href` XPath attribute axes.
    private static func splitTrailingLegadoAttrFromXPath(_ raw: String, knownAttributes: Set<String>) -> (String, String?) {
        var bracketDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var lastTopLevelAt: String.Index? = nil

        var idx = raw.startIndex
        var prevChar: Character? = nil
        while idx < raw.endIndex {
            let ch = raw[idx]
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if !inSingleQuote && !inDoubleQuote {
                if ch == "[" {
                    bracketDepth += 1
                } else if ch == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if ch == "@" && bracketDepth == 0 && prevChar != "/" {
                    lastTopLevelAt = idx
                }
            }
            prevChar = ch
            idx = raw.index(after: idx)
        }

        if let atIdx = lastTopLevelAt {
            let suffix = String(raw[raw.index(after: atIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if knownAttributes.contains(suffix) || suffix.hasPrefix("attr(") {
                let prefix = String(raw[..<atIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    return (prefix, suffix)
                }
            }
        }
        return (raw, nil)
    }
}

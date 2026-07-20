import Foundation

/// Strips model leakage (chain-of-thought, preambles, meta labels) so only final content remains.
enum GenerationOutputSanitizer {
    nonisolated private static let thinkBlockRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?is)<\s*(?:think(?:ing)?|reasoning|internal)\s*>.*?<\s*/\s*(?:think(?:ing)?|reasoning|internal)\s*>"#
        )
    }()

    nonisolated private static let openThinkRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?is)<\s*(?:think(?:ing)?|reasoning|internal)\s*>.*\z"#
        )
    }()

    nonisolated private static let labeledReasoningRegex: NSRegularExpression = {
        // Drop a labeled reasoning paragraph from its header through the next blank line.
        try! NSRegularExpression(
            pattern: #"(?im)^(?:reasoning|internal reasoning|internal thoughts?|chain of thought|my thoughts?|thinking process|analysis)\s*:?[^\n]*\n(?:[^\n].*\n)*?(?:\n|\z)"#
        )
    }()

    nonisolated private static let preambleRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?is)\A\s*(?:(?:sure|certainly|of course|okay|ok|alright)[,!]?\s+)?(?:here(?:'s| is| are))(?:\s+your|\s+the)?(?:\s+blog\s+post|\s+meeting\s+notes|\s+personal\s+notes|\s+notes|\s+caption|\s+linkedin\s+post|\s+post|\s+output)?\s*:?\s*"#
                + #"|"#
                + #"(?im)\A\s*(?:final\s+(?:answer|output|notes|post)|output)\s*:\s*"#
        )
    }()

    nonisolated private static let wholeFenceRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?is)\A\s*```(?:markdown|md)?\s*\n(.*)\n```\s*\z"#
        )
    }()

    /// Full cleanup for completed generation before persist/validate.
    nonisolated static func sanitize(_ text: String) -> String {
        var result = text
        result = replace(thinkBlockRegex, in: result, with: "")
        result = replace(openThinkRegex, in: result, with: "")
        result = replace(labeledReasoningRegex, in: result, with: "")
        result = unwrapWholeMarkdownFence(result)
        result = replace(preambleRegex, in: result, with: "")
        result = collapseExcessBlankLines(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streaming-safe cleanup: drop closed think blocks and hide unfinished think tags.
    nonisolated static func sanitizeForDisplay(_ text: String) -> String {
        var result = replace(thinkBlockRegex, in: text, with: "")
        result = replace(openThinkRegex, in: result, with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func unwrapWholeMarkdownFence(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = wholeFenceRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let bodyRange = Range(match.range(at: 1), in: text) else {
            return text
        }
        return String(text[bodyRange])
    }

    nonisolated private static func collapseExcessBlankLines(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
    }

    nonisolated private static func replace(
        _ regex: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

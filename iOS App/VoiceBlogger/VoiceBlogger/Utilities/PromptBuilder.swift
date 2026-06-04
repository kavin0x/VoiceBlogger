import Foundation

enum PromptBuilder {
    private static let instagramSummaryCharacterLimit = 1800

    static func blogMessages(transcript: String) -> [[String: String]] {
        let system = """
        You are a professional blog writer. Convert spoken transcripts into polished, \
        engaging blog posts. Write in first person. Use clear headings, short paragraphs, \
        and a conversational yet professional tone. Do not include a meta-commentary about \
        the transcript — just write the blog post directly. \
        Try to not modify the original transcription. Do not add things that the user did not say originally.
        Your job:
        1. Fix minor grammar, punctuation, and flow issues
        2. Format it as a clean, readable blog post with a title and paragraphs
        3. Do NOT add new information, opinions, or change the meaning
        4. Do NOT make it longer than necessary — preserve the original voice
        5. Keep cultural references, names, and places exactly as they are
        """
        let user = """
        Please convert the following voice transcript into a well-structured blog post. \
        Include a compelling title, introduction, main body with subheadings, and a conclusion.

        Transcript:
        \(transcript)
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    static func instagramMessages(blogContent: String) -> [[String: String]] {
        let system = """
        You are a social media content creator specialising in Instagram. \
        Write punchy, engaging Instagram captions that drive engagement. \
        Use relevant hashtags and emojis. Keep each caption under 400 words. \
        Make sure to include the actual info, and at the end tell them to keep reading to see the full blog!
        """
        let user = """
        Based on this blog post, write 3 distinct Instagram captions targeting different angles \
        (motivational, informational, story-driven). Separate each caption with exactly "---" \
        on its own line.

        Blog post:
        \(structuralSummary(of: blogContent))
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    // Extracts title, every heading, and the first sentence of each paragraph.
    // Covers all topics in the entire post at ~10-15% of the original token count —
    // small enough that prefill activations fit in the device's memory budget.
    private static func structuralSummary(of text: String) -> String {
        var result: [String] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let body = paragraphLines.joined(separator: " ")
            paragraphLines = []
            // First sentence up to .!? or first 120 chars, whichever comes first.
            if let range = body.range(of: "[.!?]", options: .regularExpression) {
                result.append(String(body[body.startIndex...range.lowerBound]))
            } else {
                result.append(String(body.prefix(120)))
            }
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                result.append(trimmed)
            } else {
                paragraphLines.append(trimmed)
            }
        }
        flushParagraph()

        return cappedSummary(result.joined(separator: "\n"), limit: instagramSummaryCharacterLimit)
    }

    private static func cappedSummary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }

        let endIndex = text.index(text.startIndex, offsetBy: limit)
        var capped = String(text[..<endIndex])
        if let lastNewline = capped.lastIndex(of: "\n") {
            capped = String(capped[..<lastNewline])
        }
        return capped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractTitle(from blogContent: String) -> String {
        let lines = blogContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let cleaned = trimmed
                    .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
                return String(cleaned.prefix(80))
            }
        }
        return "Untitled Post"
    }
}

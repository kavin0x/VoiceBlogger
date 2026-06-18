import Foundation

enum PromptBuilder {
    private static let instagramSummaryCharacterLimit = 1800
    private static let linkedinSummaryCharacterLimit = 2200
    // Qwen2.5 1.5B has a 32k-token context window. With ~300 tokens for the prompt
    // template and 1800 reserved for output, the transcript budget sits at ~4000 tokens.
    // KV cache at 4k tokens is ~460 MB — safe within the 768 MB MLX cache limit on device.
    // Transcripts above this threshold are chunked and synthesised in multiple passes.
    static let maxTranscriptCharacters = 16_000
    // Chunk size and overlap for the map-reduce path (transcripts > maxTranscriptCharacters).
    private static let chunkSize = 5_500
    private static let chunkOverlap = 400

    // MARK: - Chunking helpers

    nonisolated static func needsChunking(_ transcript: String) -> Bool {
        transcript.count > maxTranscriptCharacters
    }

    nonisolated static func splitIntoChunks(_ transcript: String) -> [String] {
        guard needsChunking(transcript) else { return [transcript] }
        var chunks: [String] = []
        var start = transcript.startIndex
        let stride = chunkSize - chunkOverlap
        while start < transcript.endIndex {
            let remaining = transcript.distance(from: start, to: transcript.endIndex)
            let end = transcript.index(start, offsetBy: min(chunkSize, remaining))
            chunks.append(String(transcript[start..<end]))
            if end == transcript.endIndex { break }
            start = transcript.index(start, offsetBy: min(stride, remaining))
        }
        return chunks
    }

    nonisolated static func chunkSummaryMessages(for chunk: String, index: Int, of total: Int) -> [[String: String]] {
        [
            ["role": "system", "content": "You extract key information from voice transcript segments. Output a compact bullet list of the main facts, ideas, names, and details — no commentary, no headers, no filler."],
            ["role": "user", "content": "Transcript segment \(index + 1) of \(total):\n\n\(chunk)\n\nKey points:"]
        ]
    }

    nonisolated static func synthesisMessages(from summaries: [String]) -> [[String: String]] {
        let numbered = summaries.enumerated()
            .map { "[\($0.offset + 1)]\n\($0.element)" }
            .joined(separator: "\n\n")
        let system = """
        You convert structured notes into clean written blog posts.
        Use the key points provided to write a well-organised post that preserves the speaker's meaning.
        Fix grammar and paragraph flow. Use simple markdown: one title, optional section headings, paragraphs, and lists when useful.
        Do not invent new claims. Do not include commentary about your process.
        Output length must be proportional to the amount of content in the notes — do not pad or expand.
        Stop after the final paragraph.
        """
        let user = """
        Write a blog post from these key points extracted from a voice recording:

        \(numbered)
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    // MARK: - Single-pass prompts

    static func blogMessages(transcript: String) -> [[String: String]] {
        let wordCount = transcript.split(separator: " ").count
        let system = """
        You clean up voice transcripts into readable notes or blog posts.
        Preserve the speaker's words, meaning, names, and facts exactly.
        Remove only: filler words (um, uh, like, you know), false starts, and repeated phrases.
        Fix punctuation and sentence structure.

        OUTPUT LENGTH RULE: Match the output length to the input. A short transcript produces a short note. Do not pad, expand, or add context that wasn't spoken.
        - Under 100 words in → 1-3 short paragraphs max, no title needed
        - 100–400 words in → clean prose, minimal headings if topics clearly shift
        - Over 400 words in → organize with a title and section headings if helpful

        Never add explanations, background context, or advice the speaker did not say.
        Never add a title or headers unless the content is clearly long enough to need them.
        Fix obvious transcription errors (foreign words, names mangled by speech-to-text).
        Use simple markdown only. Stop after the final sentence.
        """
        let safeTranscript = transcript.count > maxTranscriptCharacters
            ? String(transcript.prefix(maxTranscriptCharacters))
            : transcript
        let user = """
        Clean up this voice transcript (~\(wordCount) words). Output should be similar in length.

        Transcript:
        \(safeTranscript)
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    static func instagramMessages(blogContent: String) -> [[String: String]] {
        let system = """
        You write Instagram captions. Write ONE caption only — not multiple variations.

        STRUCTURE (follow exactly):
        1. Hook (line 1): 5-10 words. Bold statement, relatable confession, or surprising fact. No emojis on this line.
        2. [blank line]
        3. Body: 3-5 short lines with line breaks. Tell a micro-story or share one clear insight from the content. Weave in 1-2 relevant emojis naturally — not at the start of every line.
        4. [blank line]
        5. CTA: One specific call-to-action question or prompt. Examples: "Save this for when you need it 🔖", "Comment YES if you've been here 👇", "Tag someone who needs to hear this."
        6. [blank line]
        7. Hashtags: 3-5 niche, relevant tags on the final line.

        RULES:
        - Total length: 150-220 words.
        - Write in first person, like a real person sharing something genuine.
        - No corporate speak. No "I'm excited to share..."
        - Do not mention a blog, link, or external content. The caption stands alone.
        - Be specific — use real details from the content, not generic fluff.
        """
        let user = """
        Write one Instagram caption based on this content:

        \(structuralSummary(of: blogContent, limit: instagramSummaryCharacterLimit))
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    static func linkedinMessages(blogContent: String) -> [[String: String]] {
        let system = """
        You write LinkedIn posts. Write ONE post only — not multiple variations.

        STRUCTURE (follow exactly):
        1. Hook (line 1): Under 210 characters. A bold insight, a "I used to think X" opener, or a surprising number/fact. This must stand alone — it's what people see before tapping "see more."
        2. [blank line]
        3. Body: 3-5 short punchy sentences or very short paragraphs. Each sentence under 12 words. Put each thought on its own line for mobile readability. Share a real insight, lesson, or story from the content.
        4. [blank line]
        5. Closing question: End with one genuine question that invites comments. Make it specific to the topic.
        6. [blank line]
        7. Hashtags: 2-3 relevant hashtags only, on the last line.

        RULES:
        - Total length: 700-1,300 characters (roughly 100-180 words).
        - Write in first person. Be direct and human — no corporate voice.
        - No "Key Takeaways" sections. No bullet lists. No headers.
        - No external links.
        - Be specific — use real details, numbers, or names from the content.
        - Do not start with "I'm excited to share" or any hollow opener.
        """
        let user = """
        Write one LinkedIn post based on this content:

        \(structuralSummary(of: blogContent, limit: linkedinSummaryCharacterLimit))
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    // MARK: - Utilities

    private static func structuralSummary(of text: String, limit: Int) -> String {
        var result: [String] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let body = paragraphLines.joined(separator: " ")
            paragraphLines = []
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

        return cappedSummary(result.joined(separator: "\n"), limit: limit)
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

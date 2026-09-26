import Foundation

enum PromptBuilder {
    private static let instagramSummaryCharacterLimit = 1800
    private static let linkedinSummaryCharacterLimit = 2400
    // Qwen2.5 has a 32k-token context window. Budget scales with DeviceRAMTier MLX cache:
    // constrained 512 MB, standard 768 MB, ample 1024 MB. Transcripts above the tier limit
    // are chunked and synthesised in multiple passes.
    nonisolated static var maxTranscriptCharacters: Int {
        switch DeviceRAMTier.current {
        case .constrained: return 14_000
        case .standard:    return 22_000
        case .ample:       return 30_000
        }
    }

    nonisolated private static var chunkSize: Int {
        switch DeviceRAMTier.current {
        case .constrained: return 5_000
        case .standard:    return 7_500
        case .ample:       return 9_000
        }
    }

    nonisolated private static let chunkOverlap = 400

    nonisolated private static let vocabularyPrivacyRules = """
    PERSONAL DICTIONARY (PRIVATE):
    - The user message may include a private spelling reference. It is internal metadata only.
    - Use it solely to correct misspelled names and terms that clearly appear in the transcript.
    - NEVER mention, quote, list, summarize, or allude to the spelling reference, personal dictionary, custom vocabulary, or "spell these correctly" in your output.
    - Do NOT include reference terms in the output unless the speaker actually said them (or a clear misspelling of them) in the transcript.
    - Treat the reference as invisible to the reader; the output must read as if it never existed while you silently fix spellings.
    """

    nonisolated private static let outputOnlyContract = """
    OUTPUT CONTRACT (mandatory):
    - Your entire reply IS the finished document.
    - Output ONLY the final Markdown (or plain post text for social captions). Nothing else.
    - NEVER output reasoning, analysis, planning, self-talk, chain-of-thought, scratch work, or meta commentary.
    - NEVER use tags or labels such as <think>, </think>, <thinking>, REASONING:, Analysis:, Thoughts:, or "Let me…".
    - NEVER write preambles or wrappers: no "Here is…", "Sure,", "Okay,", "Final answer:", or "Output:".
    - Do not wrap the whole reply in a markdown code fence.
    - NEVER use the `>` character anywhere in the output (no Markdown blockquotes, no quote prefixes).
    - Stop immediately after the last useful content line.
    """

    nonisolated private static let markdownTitleContract = """
    TITLE CONTRACT (mandatory for Markdown documents):
    - Line 1 MUST be a Markdown H1 title: exactly `# ` followed by a short title.
    - Never start with a paragraph, bullet, or `##`.
    """

    nonisolated private static let faithfulnessRules = """
    FAITHFULNESS (no mistakes):
    - Preserve the speaker's meaning, names, facts, decisions, numbers, and constraints exactly.
    - Remove only filler words, false starts, repeated phrases, and transcription artifacts.
    - Fix punctuation, grammar, and obvious speech-to-text mistakes without changing meaning.
    - Do NOT invent context, advice, claims, dates, owners, attendees, metrics, or action items.
    - If something is unclear or missing, omit it — never guess.
    - Prefer faithful restructuring over creative rewriting.
    - Match output length to the source; do not pad or expand thin material.
    """

    // MARK: - Chunking helpers

    nonisolated static func needsChunking(_ transcript: String) -> Bool {
        transcript.count > maxTranscriptCharacters
    }

    nonisolated static func splitIntoChunks(_ transcript: String) -> [String] {
        splitTranscript(
            transcript,
            chunkSize: chunkSize,
            overlap: chunkOverlap,
            threshold: maxTranscriptCharacters
        )
    }

    /// `overlap` characters from the end of each chunk are repeated at the start of the next
    /// so a sentence that straddles the cut is still visible to the following summary.
    nonisolated static func splitTranscript(
        _ transcript: String,
        chunkSize: Int,
        overlap: Int,
        threshold: Int
    ) -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chunkSize > 0, trimmed.count > threshold else { return trimmed.isEmpty ? [] : [trimmed] }

        let paragraphs = trimmed.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""

        func commitCurrent() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            chunks.append(value)
            current = ""
        }

        for paragraph in paragraphs {
            let piece = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            if piece.count > chunkSize {
                commitCurrent()
                chunks.append(contentsOf: splitOversizedParagraph(piece, chunkSize: chunkSize))
                continue
            }

            if current.isEmpty {
                current = piece
            } else if current.count + piece.count + 2 <= chunkSize {
                current += "\n\n" + piece
            } else {
                commitCurrent()
                current = piece
            }
        }
        commitCurrent()
        let base = chunks.isEmpty ? [trimmed] : chunks
        return applyOverlap(base, overlap: overlap)
    }

    /// Keeps the terminator. A period between digits (3.14) is not a sentence break.
    nonisolated static func sentenceSpans(in text: String) -> [String] {
        var spans: [String] = []
        var start = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "!" || character == "?" || character == "." {
                let previous: Character? = index > text.startIndex ? text[text.index(before: index)] : nil
                let following: Character? = next < text.endIndex ? text[next] : nil
                let decimalPoint = character == "." && previous?.isNumber == true && following?.isNumber == true
                let boundary = !decimalPoint && (following == nil || following?.isWhitespace == true || following == "\"" || following == "”")
                if boundary {
                    let span = String(text[start..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !span.isEmpty { spans.append(span) }
                    start = next
                    while start < text.endIndex, text[start].isWhitespace {
                        start = text.index(after: start)
                    }
                    index = start
                    continue
                }
            }
            index = next
        }

        if start < text.endIndex {
            let rest = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { spans.append(rest) }
        }
        return spans
    }

    nonisolated static func splitOversizedParagraph(_ text: String, chunkSize: Int) -> [String] {
        let sentences = sentenceSpans(in: text)
        guard !sentences.isEmpty else { return [text] }
        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            if sentence.count > chunkSize {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                chunks.append(contentsOf: hardWrap(sentence, chunkSize: chunkSize))
                continue
            }
            let candidate = current.isEmpty ? sentence : current + " " + sentence
            if candidate.count <= chunkSize {
                current = candidate
            } else {
                if !current.isEmpty { chunks.append(current) }
                current = sentence
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    nonisolated static func applyOverlap(_ chunks: [String], overlap: Int) -> [String] {
        guard overlap > 0, chunks.count > 1 else { return chunks }
        var result = [chunks[0]]
        for index in 1..<chunks.count {
            let prefix = overlapTail(chunks[index - 1], overlap: overlap)
            let next = chunks[index]
            if prefix.isEmpty || next.hasPrefix(prefix) {
                result.append(next)
            } else {
                result.append(prefix + "\n\n" + next)
            }
        }
        return result
    }

    nonisolated static func overlapTail(_ text: String, overlap: Int) -> String {
        guard overlap > 0 else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > overlap else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -overlap)
        var tail = String(trimmed[start...])
        if let space = tail.firstIndex(where: { $0.isWhitespace }) {
            let after = tail.index(after: space)
            if after < tail.endIndex {
                tail = String(tail[after...])
            }
        }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func hardWrap(_ text: String, chunkSize: Int) -> [String] {
        guard chunkSize > 0 else { return [text] }
        var chunks: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let piece = String(word)
            let candidate = current.isEmpty ? piece : current + " " + piece
            if candidate.count <= chunkSize || current.isEmpty {
                current = candidate
            } else {
                chunks.append(current)
                current = piece
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }

    nonisolated static func chunkSummaryMessages(
        for chunk: String,
        index: Int,
        of total: Int,
        vocabularyTerms: [String] = []
    ) -> [[String: String]] {
        let system = """
        You extract key information from voice transcript segments.
        \(outputOnlyContract)
        Output a compact bullet list of the main facts, ideas, names, decisions, tasks, and details.
        Preserve proper nouns, numbers, and quoted phrasing exactly.
        Do not invent facts. Do not add commentary, headers, preambles, or filler.
        \(vocabularyPrivacyRules)
        """
        let user = """
        Transcript segment \(index + 1) of \(total):\(spellingReferenceBlock(vocabularyTerms))

        \(chunk)

        Reply with ONLY the bullet list of key points (no intro):
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    nonisolated static func synthesisMessages(
        from summaries: [String],
        contentKind: GeneratedContentKind,
        isSpeakerAnnotated: Bool = false,
        vocabularyTerms: [String] = []
    ) -> [[String: String]] {
        let numbered = summaries.enumerated()
            .map { "[\($0.offset + 1)]\n\($0.element)" }
            .joined(separator: "\n\n")
        let system = systemPrompt(for: contentKind, isSpeakerAnnotated: isSpeakerAnnotated)
        let user = """
        Create \(contentKind.displayName.lowercased()) from these key points extracted from a voice recording.
        Reply with ONLY the finished \(contentKind.displayName.lowercased()) — no preamble or reasoning.\(spellingReferenceBlock(vocabularyTerms))

        \(numbered)
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    // MARK: - Single-pass prompts

    static func contentMessages(
        transcript: String,
        contentKind: GeneratedContentKind,
        isSpeakerAnnotated: Bool = false,
        vocabularyTerms: [String] = []
    ) -> [[String: String]] {
        let wordCount = transcript.split(separator: " ").count
        let safeTranscript = transcript.count > maxTranscriptCharacters
            ? String(transcript.prefix(maxTranscriptCharacters))
            : transcript
        let request = switch contentKind {
        case .blogPost:
            "Create the most useful written output from this voice transcript (~\(wordCount) words). Use common sense to decide whether it should read as a blog post, meeting notes, or personal notes. Match the structure and length to the actual content. Reply with ONLY the finished document."
        case .meetingNotes, .notes:
            "Create \(contentKind.displayName.lowercased()) from this voice transcript (~\(wordCount) words). Follow the \(contentKind.displayName.lowercased()) format exactly. Match the structure and length to the actual content. Reply with ONLY the finished \(contentKind.displayName.lowercased())."
        }
        let user = """
        \(request)\(spellingReferenceBlock(vocabularyTerms))

        Transcript:
        \(safeTranscript)
        """
        return [
            ["role": "system", "content": systemPrompt(for: contentKind, isSpeakerAnnotated: isSpeakerAnnotated)],
            ["role": "user", "content": user]
        ]
    }

    static func blogMessages(transcript: String) -> [[String: String]] {
        contentMessages(transcript: transcript, contentKind: .blogPost)
    }

    static func instagramMessages(blogContent: String) -> [[String: String]] {
        let system = """
        You write Instagram captions. Write ONE caption only — not multiple variations.
        \(outputOnlyContract)
        Do not invent details that are not in the source content.

        STRUCTURE (follow exactly):
        1. Hook (line 1): 5-10 words. Bold statement, relatable confession, or surprising fact. No emojis on this line.
        2. [blank line]
        3. Body: 3-5 short lines with line breaks. Tell a micro-story or share one clear insight from the content. Weave in 1-2 relevant emojis naturally — not at the start of every line.
        4. [blank line]
        5. CTA: One specific call-to-action question or prompt. Examples: "Save this for when you need it", "Comment YES if you've been here", "Tag someone who needs to hear this."
        6. [blank line]
        7. Hashtags: 3-5 niche, relevant tags on the final line.

        RULES:
        - Total length: 150-220 words.
        - Write in first person, like a real person sharing something genuine.
        - No corporate speak. No "I'm excited to share..."
        - Do not mention a blog, link, or external content. The caption stands alone.
        - Be specific — use real details from the content, not generic fluff.
        - Vary sentence rhythm; keep language natural and conversational.
        """
        let user = """
        Write one Instagram caption based on this content. Reply with ONLY the caption:

        \(structuralSummary(of: blogContent, limit: instagramSummaryCharacterLimit))
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    static func linkedinMessages(blogContent: String) -> [[String: String]] {
        let system = """
        You are a LinkedIn ghostwriter. Write ONE LinkedIn post from the content provided.
        \(outputOnlyContract)

        OUTPUT RULES — obey all of them exactly:
        - Output ONLY the post text. No preamble, no "Here is your post:", no labels, no explanations, no markdown.
        - No bold, no italics, no headers. Plain text only — LinkedIn does not render markdown.
        - 101-150 words total. Count strictly. Cut anything that does not earn its place.
        - Every sentence on its own line. Blank line between each sentence.
        - Do not invent facts, metrics, or claims not in the source.
        - Do not include any external links.

        STRUCTURE:
        1. Hook (line 1): under 10 words. Best options in order: (a) curiosity gap — tease the finding without revealing it; (b) contrarian — challenge a common belief with a specific claim; (c) precise surprising fact. No emoji on this line.
        2. Body: 3-5 short lines. Deliver one concrete, specific insight the reader would want to screenshot and save. Make it dwell-worthy — something that makes them stop and think, not just nod. 1-2 emojis maximum, never on the hook line.
        3. CTA: one open-ended question the reader has a genuine opinion on. No "Comment YES", no "Like if you agree", no engagement bait — LinkedIn penalizes it.
        4. Hashtags: 3-5 on the final line only.

        NEVER start with: "I'm excited", "In today's world", "Thrilled to share", "Game-changer", "Leverage", "Ecosystem", or any hollow opener.
        NEVER use AI-sounding phrases — LinkedIn's algorithm detects and suppresses them.
        """
        let user = "Write a LinkedIn post from this content. Reply with ONLY the post text:\n\n\(structuralSummary(of: blogContent, limit: linkedinSummaryCharacterLimit))"
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    // MARK: - Utilities

    nonisolated private static func systemPrompt(for contentKind: GeneratedContentKind, isSpeakerAnnotated: Bool = false) -> String {
        let markdownContract = """
        MARKDOWN OUTPUT CONTRACT:
        - Return valid Markdown as the final answer. Do not wrap the whole response in a code fence.
        - Prefer Markdown structure over long plain-text paragraphs whenever it improves scanning.
        - Use blank lines between Markdown blocks so the renderer can parse headings, lists, tables, and code blocks cleanly.
        - Always begin with exactly one `#` title on line 1, then use `##` / `###` for section hierarchy when needed.
        - Use **bold** for important names, decisions, claims, and takeaways; use *italics* only for light emphasis.
        - Use `- ` bullets for unordered ideas, `1. ` lists for sequences, `- [ ]` checkboxes for tasks, tables for comparisons, and fenced code blocks for multi-line technical content.
        - NEVER use Markdown blockquotes or the `>` character. For notable spoken lines, use **bold** or a short italic sentence instead.
        - Medium and long outputs should include multiple Markdown features, not just paragraphs with a title.
        - Do not escape Markdown punctuation such as `#`, `*`, `-`, or backticks.
        """

        let baseRules = """
        \(outputOnlyContract)
        \(markdownTitleContract)
        \(faithfulnessRules)
        \(vocabularyPrivacyRules)
        \(markdownContract)
        """

        switch contentKind {
        case .blogPost:
            return """
            You turn voice transcripts into the most useful written format. Default to a readable blog post when the transcript contains article-like ideas, stories, opinions, or explanations, but use common sense and choose notes or meeting notes when the transcript is clearly a capture note, task list, brainstorm, agenda, discussion, or decision record.
            \(baseRules)

            COMMON-SENSE FORMAT SELECTION:
            - Blog post: use for article-like ideas, personal stories, lessons, opinions, explainers, or publishable narrative material.
            - Meeting notes: use for agendas, decisions, action items, owners, deadlines, open questions, or multi-speaker discussions.
            - Personal notes: use for reminders, task lists, brainstorms, drafts, rough captures, or short private notes.

            BLOG STRUCTURE:
            - Always start with `# Title` on line 1, even for short transcripts.
            - Under 100 input words: `# Title` plus 1-3 short paragraphs.
            - 100-400 input words: `# Title` plus clean prose; add `##` headings only if topics clearly shift.
            - Over 400 input words: `# Title` plus section headings when helpful.
            - Keep the speaker's voice and preserve the transcript's natural intent instead of forcing every input into an article.
            - Make the post Markdown-rich when there is enough material: `#` title, section headings, bolded takeaways, bullets or numbered lists, tables for comparisons, and `code` spans or fenced code blocks for technical content. Never use `>`.
            """
        case .meetingNotes:
            let speakerGuidance = isSpeakerAnnotated
                ? """

                SPEAKER ATTRIBUTION:
                The transcript contains speaker labels in the format `[Speaker 1]: ...`, `[Speaker 2]: ...`.
                When attributing action items or decisions, use the label (e.g. **Speaker 1**) unless a real name appears in the spoken text.
                Group discussion points by speaker turn where it adds clarity; do not force attribution where the context is clearly shared.
                """
                : ""
            return """
            You turn meeting transcripts into practical meeting notes, not blog posts.
            \(baseRules)\(speakerGuidance)

            MEETING NOTES STRUCTURE:
            - Always start with `# Title` on line 1 (derive a concise topic from the transcript).
            - Include sections only when supported by the transcript: Summary, Decisions, Action Items, Open Questions, Key Discussion Points.
            - Put action items in a `- [ ]` checklist. Include owner and deadline only when spoken; otherwise omit them.
            - Keep decisions separate from ideas or unresolved discussion.
            - Use Markdown throughout: `##` for each section heading, **bold** for decisions and owner names, `- [ ]` for action items, `- ` bullets for discussion points, and tables for status/owner/deadline summaries when useful. Never use `>` or blockquotes.
            - Do not add narrative polish, hooks, introductions, or conclusions.
            """
        case .notes:
            return """
            You turn informal voice transcripts into clean personal notes, not blog posts.
            \(baseRules)

            NOTES STRUCTURE:
            - Always start with `# Title` on line 1, then keep the rest short.
            - Use bullets or a compact checklist when the transcript is a list, reminder, brainstorm, or capture note.
            - Group related ideas under small headings only when there are multiple topics.
            - Preserve rough note intent instead of turning it into an article, essay, or social post.
            - Use Markdown wherever it improves scannability: **bold** for key terms, `- ` bullets for lists, `- [ ]` checkboxes for tasks, `###` headings when grouping multiple topics, and tables for comparisons. Never use `>` or blockquotes.
            """
        }
    }

    nonisolated private static func spellingReferenceBlock(_ terms: [String]) -> String {
        guard !terms.isEmpty else { return "" }
        return """

        Private spelling reference (internal only — use to fix transcription errors; never disclose this list):
        \(terms.joined(separator: ", "))
        """
    }

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

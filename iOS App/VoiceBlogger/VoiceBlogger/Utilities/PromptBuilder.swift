import Foundation

enum PromptBuilder {
    private struct PromptTemplate {
        let name: String
        let useWhen: String
        let structure: [String]
        let style: String

        var promptText: String {
            """
            TEMPLATE: \(name)
            Use when: \(useWhen)
            Structure: \(structure.joined(separator: " -> "))
            Style: \(style)
            """
        }
    }

    private struct SocialPromptObject {
        let role: String
        let objective: String
        let outputContract: String
        let templates: [PromptTemplate]
        let rules: [String]

        var systemPrompt: String {
            """
            ROLE
            \(role)

            OBJECTIVE
            \(objective)

            OUTPUT CONTRACT
            \(outputContract)

            POST TYPE TEMPLATES
            \(templates.map(\.promptText).joined(separator: "\n\n"))

            RULES
            \(rules.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
    }

    private static let instagramSummaryCharacterLimit = 1800
    private static let linkedinSummaryCharacterLimit = 2400
    // Qwen2.5 1.5B has a 32k-token context window. With ~300 tokens for the prompt
    // template and 1800 reserved for output, the transcript budget sits at ~4000 tokens.
    // KV cache at 4k tokens is ~460 MB - safe within the 768 MB MLX cache limit on device.
    // Transcripts above this threshold are chunked and synthesised in multiple passes.
    nonisolated static let maxTranscriptCharacters = 16_000
    // Chunk size and overlap for the map-reduce path (transcripts > maxTranscriptCharacters).
    nonisolated private static let chunkSize = 5_500
    nonisolated private static let chunkOverlap = 400

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
            ["role": "system", "content": "You extract key information from voice transcript segments. Output a compact bullet list of the main facts, ideas, names, decisions, tasks, and details. Do not add commentary, headers, or filler."],
            ["role": "user", "content": "Transcript segment \(index + 1) of \(total):\n\n\(chunk)\n\nKey points:"]
        ]
    }

    nonisolated static func synthesisMessages(from summaries: [String], contentKind: GeneratedContentKind, isSpeakerAnnotated: Bool = false) -> [[String: String]] {
        let numbered = summaries.enumerated()
            .map { "[\($0.offset + 1)]\n\($0.element)" }
            .joined(separator: "\n\n")
        let system = systemPrompt(for: contentKind, isSpeakerAnnotated: isSpeakerAnnotated)
        let user = """
        Create \(contentKind.displayName.lowercased()) from these key points extracted from a voice recording:

        \(numbered)
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    // MARK: - Single-pass prompts

    static func contentMessages(transcript: String, contentKind: GeneratedContentKind, isSpeakerAnnotated: Bool = false) -> [[String: String]] {
        let wordCount = transcript.split(separator: " ").count
        let safeTranscript = transcript.count > maxTranscriptCharacters
            ? String(transcript.prefix(maxTranscriptCharacters))
            : transcript
        let request = switch contentKind {
        case .blogPost:
            "Create the most useful written output from this voice transcript (~\(wordCount) words). Use common sense to decide whether it should read as a blog post, meeting notes, or personal notes. Match the structure and length to the actual content."
        case .meetingNotes, .notes:
            "Create \(contentKind.displayName.lowercased()) from this voice transcript (~\(wordCount) words). Match the structure and length to the actual content."
        }
        let user = """
        \(request)

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
        You write Instagram captions. Write ONE caption only - not multiple variations.

        STRUCTURE (follow exactly):
        1. Hook (line 1): 5-10 words. Bold statement, relatable confession, or surprising fact. No emojis on this line.
        2. [blank line]
        3. Body: 3-5 short lines with line breaks. Tell a micro-story or share one clear insight from the content. Weave in 1-2 relevant emojis naturally - not at the start of every line.
        4. [blank line]
        5. CTA: One specific call-to-action question or prompt. Examples: "Save this for when you need it", "Comment YES if you've been here", "Tag someone who needs to hear this."
        6. [blank line]
        7. Hashtags: 3-5 niche, relevant tags on the final line.

        RULES:
        - Total length: 150-220 words.
        - Write in first person, like a real person sharing something genuine.
        - No corporate speak. No "I'm excited to share..."
        - Do not mention a blog, link, or external content. The caption stands alone.
        - Be specific - use real details from the content, not generic fluff.
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
        let system = linkedinPromptObject.systemPrompt
        let user = """
        Select the best POST TYPE TEMPLATE for the content below, then write one complete LinkedIn post.

        Content source:
        \(structuralSummary(of: blogContent, limit: linkedinSummaryCharacterLimit))
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    private static let linkedinPromptObject = SocialPromptObject(
        role: "Act as an expert LinkedIn professional update generator and executive ghostwriter. Write with strategic clarity, specific detail, and a human first-person voice.",
        objective: "Transform the source content into a high-engagement LinkedIn post that feels authentic, polished, and native to the platform. Preserve the source meaning exactly and choose the post structure that best fits the material.",
        outputContract: "Return ONE finished LinkedIn post only. Do not return multiple options, labels, analysis, template names, explanations, or markdown headings.",
        templates: [
            PromptTemplate(
                name: "Original Research / Data Insights",
                useWhen: "the content includes data, research, metrics, a pattern, or a counter-intuitive finding",
                structure: [
                    "hook with the surprising stat or finding",
                    "core data or observation",
                    "why it matters",
                    "actionable takeaway",
                    "specific CTA question",
                    "2-3 relevant hashtags"
                ],
                style: "analytical, insightful, forward-looking, and precise"
            ),
            PromptTemplate(
                name: "Project Update / Milestone",
                useWhen: "the content describes shipping, launching, completing, learning, or reaching a meaningful project milestone",
                structure: [
                    "hook with the impact or result",
                    "brief journey or challenge overcome",
                    "team credit or gratitude when supported by the source",
                    "what comes next",
                    "specific CTA question",
                    "2-3 relevant hashtags"
                ],
                style: "celebratory, humble, collaborative, and grounded"
            ),
            PromptTemplate(
                name: "Event / Long-Form Recap",
                useWhen: "the content recaps a talk, event, interview, podcast, workshop, article, or long-form discussion",
                structure: [
                    "hook with the biggest macro takeaway",
                    "three distinct high-value lessons as short bullets",
                    "how to apply the lessons",
                    "specific CTA question",
                    "2-3 relevant hashtags"
                ],
                style: "educational, generous, concise, and synthesizing"
            )
        ],
        rules: [
            "The first 1-2 lines must earn the 'see more' click. Avoid 'I am thrilled to announce', 'In today's fast-paced world', and other hollow openers.",
            "Use short paragraphs of 1-3 sentences with frequent line breaks for mobile skimming.",
            "Sound professional, conversational, authoritative, and human. Avoid corporate jargon such as synergy, utilize, and paradigm shift.",
            "Use first person when the source supports it. Do not invent personal experiences, names, metrics, dates, claims, links, or gratitude.",
            "Use at most 2-4 relevant emojis in the entire post, and never place one at the start of the hook.",
            "Use bullets only for the Event / Long-Form Recap template; otherwise prefer short paragraphs.",
            "End with a natural open-ended question or a clear next step that invites comments.",
            "Put 2-3 highly relevant hashtags on the final line only.",
            "Target 900-1,800 characters unless the source is very short; do not pad thin material."
        ]
    )

    // MARK: - Utilities

    nonisolated private static func systemPrompt(for contentKind: GeneratedContentKind, isSpeakerAnnotated: Bool = false) -> String {
        let markdownContract = """
        MARKDOWN OUTPUT CONTRACT:
        - Return valid Markdown as the final answer. Do not wrap the whole response in a code fence.
        - Prefer Markdown structure over long plain-text paragraphs whenever it improves scanning.
        - Use blank lines between Markdown blocks so the renderer can parse headings, lists, quotes, tables, and code blocks cleanly.
        - Use `#`, `##`, and `###` headings for clear hierarchy; use no more than one `#` title.
        - Use **bold** for important names, decisions, claims, and takeaways; use *italics* only for light emphasis.
        - Use `- ` bullets for unordered ideas, `1. ` lists for sequences, `- [ ]` checkboxes for tasks, `>` blockquotes for notable spoken lines or callouts, tables for comparisons, and fenced code blocks for multi-line technical content.
        - Medium and long outputs should include multiple Markdown features, not just paragraphs with a title.
        - Do not escape Markdown punctuation such as `#`, `*`, `-`, `>`, or backticks.
        """

        let baseRules = """
        Preserve the speaker's meaning, names, facts, decisions, and constraints exactly.
        Remove only filler words, false starts, repeated phrases, and transcription artifacts.
        Fix punctuation, grammar, and obvious speech-to-text mistakes.
        Do not invent context, advice, claims, dates, owners, or action items.
        \(markdownContract)
        Stop after the final useful line.
        Match output length to input; do not pad or expand thin source material.
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
            - Under 100 input words: write 1-3 short paragraphs, usually with no title.
            - 100-400 input words: write clean prose with minimal headings only if topics clearly shift.
            - Over 400 input words: use one title and section headings if helpful.
            - Keep the speaker's voice and preserve the transcript's natural intent instead of forcing every input into an article.
            - Make the post Markdown-rich when there is enough material: title, section headings, bolded takeaways, bullets or numbered lists, blockquotes for memorable lines, tables for comparisons, and `code` spans or fenced code blocks for technical content.
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
            - Start with a concise title if the meeting topic is clear.
            - Include sections only when supported by the transcript: Summary, Decisions, Action Items, Open Questions, Key Discussion Points.
            - Put action items in a `- [ ]` checklist. Include owner and deadline only when spoken; otherwise omit them.
            - Keep decisions separate from ideas or unresolved discussion.
            - Use Markdown throughout: `##` for each section heading, **bold** for decisions and owner names, `- [ ]` for action items, `- ` bullets for discussion points, tables for status/owner/deadline summaries when useful, and blockquotes for important verbatim remarks.
            - Do not add narrative polish, hooks, introductions, or conclusions.
            """
        case .notes:
            return """
            You turn informal voice transcripts into clean personal notes, not blog posts.
            \(baseRules)

            NOTES STRUCTURE:
            - Keep short notes short.
            - Use bullets or a compact checklist when the transcript is a list, reminder, brainstorm, or capture note.
            - Group related ideas under small headings only when there are multiple topics.
            - Preserve rough note intent instead of turning it into an article, essay, or social post.
            - Do not add a title unless it makes the note easier to scan.
            - Use Markdown wherever it improves scannability: **bold** for key terms, `- ` bullets for lists, `- [ ]` checkboxes for tasks, `###` headings when grouping multiple topics, tables for comparisons, and blockquotes for captured ideas worth preserving.
            """
        }
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

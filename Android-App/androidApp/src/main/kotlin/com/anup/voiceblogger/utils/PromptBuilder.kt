package com.anup.voiceblogger.utils

object PromptBuilder {

    private const val MAX_TRANSCRIPT_CHARS = 8000
    private const val MAX_BLOG_SUMMARY_CHARS = 1800
    private const val MAX_LINKEDIN_SUMMARY_CHARS = 2200
    private const val MAX_BLOG_TOKENS = 1800
    private const val MAX_INSTAGRAM_TOKENS = 450
    private const val MAX_LINKEDIN_TOKENS = 250

    // --- System prompts ---

    val blogSystemPrompt = """
You convert voice transcripts into clean written notes or blog posts.
Preserve the speaker's meaning, facts, names, cultural references, and point of view.
Fix grammar, punctuation, filler words, and paragraph flow without adding new claims.
If the transcript is short, keep the output short. If it is longer, organize it with clear sections.
Use simple markdown only: one title, optional section headings, paragraphs, and lists when useful.
Do not use tables unless the transcript clearly contains tabular data.
Do not include commentary about the transcript or your process.
Stop after the final paragraph; do not repeat sections or restart the post.
    """.trimIndent()

    val instagramSystemPrompt = """
You are a social media content creator specialising in Instagram. Write punchy, engaging Instagram captions that drive engagement. Use relevant hashtags and emojis. Keep each caption under 400 words. Make sure to include the actual info, and at the end tell them to keep reading to see the full blog!
    """.trimIndent()

    val linkedinSystemPrompt = """
You are a professional LinkedIn content writer. Write thoughtful, concise LinkedIn posts that share insights and spark meaningful professional conversations. Use a warm but professional tone. Avoid excessive hashtags — 3 to 5 max at the very end.
    """.trimIndent()

    // --- User prompts ---

    fun buildBlogUserPrompt(transcript: String): String {
        val safeTranscript = transcript.take(MAX_TRANSCRIPT_CHARS)
        return """
Rewrite this voice transcript into a readable post or note. Keep the content proportional to the transcript length.

Transcript:
$safeTranscript
        """.trimIndent()
    }

    fun buildInstagramUserPrompt(blogContent: String): String {
        val summary = structuralSummary(blogContent, MAX_BLOG_SUMMARY_CHARS)
        return """
Based on this blog post, write 3 distinct Instagram captions targeting different angles (motivational, informational, story-driven). Separate each caption with exactly "---" on its own line.

Blog post:
$summary
        """.trimIndent()
    }

    fun buildLinkedInUserPrompt(blogContent: String): String {
        val summary = structuralSummary(blogContent, MAX_LINKEDIN_SUMMARY_CHARS)
        return """
Based on this blog post, write a single LinkedIn post that:
1. Opens with a compelling hook (1-2 sentences)
2. Shares the core insight or story in 2-3 short paragraphs
3. Ends with a "Key Takeaways:" section using bullet points (• )
4. Closes with 3-5 relevant hashtags

Keep the total length between 101-150 words. Posts in this range average 8x more impressions than shorter posts. Cut aggressively — every sentence must earn its place. Do not include a title or heading at the top.

Blog post:
$summary
        """.trimIndent()
    }

    // --- Qwen ChatML format ---

    fun formatQwenPrompt(systemPrompt: String, userMessage: String): String {
        return "<|im_start|>system\n$systemPrompt<|im_end|>\n<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n"
    }

    fun blogMaxTokens(): Int = MAX_BLOG_TOKENS
    fun instagramMaxTokens(): Int = MAX_INSTAGRAM_TOKENS
    fun linkedinMaxTokens(): Int = MAX_LINKEDIN_TOKENS

    // --- Structural summary extraction (exact port of iOS logic) ---

    fun structuralSummary(blogContent: String, limit: Int): String {
        val lines = blogContent.split("\n")
        val resultParts = mutableListOf<String>()
        val currentParagraph = StringBuilder()

        fun flushParagraph() {
            if (currentParagraph.isNotEmpty()) {
                val text = currentParagraph.toString().trim()
                // Take text up to first sentence-ending punctuation or first 120 chars
                val endIdx = text.indexOfFirst { it == '.' || it == '!' || it == '?' }
                val sentence = if (endIdx >= 0) text.substring(0, endIdx + 1) else text.take(120)
                if (sentence.isNotBlank()) {
                    resultParts.add(sentence)
                }
                currentParagraph.clear()
            }
        }

        for (line in lines) {
            when {
                line.isBlank() -> flushParagraph()
                line.startsWith("#") -> {
                    flushParagraph()
                    resultParts.add(line)
                }
                else -> {
                    if (currentParagraph.isNotEmpty()) currentParagraph.append(" ")
                    currentParagraph.append(line)
                }
            }
        }
        flushParagraph()

        val joined = resultParts.joinToString("\n")
        return if (joined.length <= limit) {
            joined
        } else {
            // Cut at last newline before limit
            val truncated = joined.substring(0, limit)
            val lastNewline = truncated.lastIndexOf('\n')
            if (lastNewline > 0) truncated.substring(0, lastNewline) else truncated
        }
    }

    fun extractTitle(blogContent: String): String {
        if (blogContent.isBlank()) return "Untitled Post"
        val firstLine = blogContent.lines().firstOrNull { it.isNotBlank() } ?: return "Untitled Post"
        val withoutHash = firstLine.replace(Regex("^#+\\s*"), "")
        val withoutBold = withoutHash.replace(Regex("\\*\\*(.*?)\\*\\*"), "$1")
        return withoutBold.take(80).ifBlank { "Untitled Post" }
    }
}

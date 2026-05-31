import Foundation

enum PromptBuilder {
    static func blogMessages(transcript: String) -> [[String: String]] {
        let system = """
        You are a professional blog writer. Convert spoken transcripts into polished, \
        engaging blog posts. Write in first person. Use clear headings, short paragraphs, \
        and a conversational yet professional tone. Do not include a meta-commentary about \
        the transcript — just write the blog post directly.
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
        Use relevant hashtags and emojis. Keep each caption under 300 words.
        """
        let user = """
        Based on this blog post, write 3 distinct Instagram captions targeting different angles \
        (motivational, informational, story-driven). Separate each caption with exactly "---" \
        on its own line.

        Blog post:
        \(blogContent)
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
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

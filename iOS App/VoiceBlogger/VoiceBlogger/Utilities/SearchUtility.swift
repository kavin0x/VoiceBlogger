import Foundation

enum SearchUtility {
    static func filter(_ posts: [BlogPost], query: String) -> [BlogPost] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return posts }
        return posts.filter { matches($0, query: trimmed) }
    }

    /// Case-insensitive match. The query is not lowercased first: in Turkish,
    /// `"I".lowercased()` is dotless `ı`, and `"FILE"` does not contain `ı`.
    static func matchesField(_ field: String, query: String) -> Bool {
        field.localizedCaseInsensitiveContains(query)
    }

    private static func matches(_ post: BlogPost, query: String) -> Bool {
        matchesField(post.title, query: query)
            || matchesField(post.transcript, query: query)
            || matchesField(post.blogContent, query: query)
            || matchesField(post.instagramCaptions, query: query)
            || matchesField(post.linkedinPost, query: query)
    }
}

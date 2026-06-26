import Foundation

enum SearchUtility {
    static func filter(_ posts: [BlogPost], query: String) -> [BlogPost] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return posts }
        return posts.filter { matches($0, query: trimmed) }
    }

    private static func matches(_ post: BlogPost, query: String) -> Bool {
        let q = query.lowercased()
        return post.title.localizedCaseInsensitiveContains(q)
            || post.transcript.localizedCaseInsensitiveContains(q)
            || post.blogContent.localizedCaseInsensitiveContains(q)
            || post.instagramCaptions.localizedCaseInsensitiveContains(q)
            || post.linkedinPost.localizedCaseInsensitiveContains(q)
    }
}

import Foundation
import SwiftData

@Model
final class BlogPost {
    var id: UUID
    var title: String
    var transcript: String
    var blogContent: String
    var instagramCaptions: String
    var audioFilename: String?
    var createdAt: Date
    var duration: TimeInterval

    init(
        title: String = "",
        transcript: String = "",
        blogContent: String = "",
        instagramCaptions: String = "",
        audioFilename: String? = nil,
        createdAt: Date = .now,
        duration: TimeInterval = 0
    ) {
        self.id = UUID()
        self.title = title
        self.transcript = transcript
        self.blogContent = blogContent
        self.instagramCaptions = instagramCaptions
        self.audioFilename = audioFilename
        self.createdAt = createdAt
        self.duration = duration
    }
}

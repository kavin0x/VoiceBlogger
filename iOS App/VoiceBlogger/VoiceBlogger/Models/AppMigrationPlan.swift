import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [SchemaV1.BlogPost.self]

    @Model
    final class BlogPost {
        var id: UUID
        var title: String
        var transcript: String
        var blogContent: String
        var instagramCaptions: String
        var linkedinPost: String
        var audioFilename: String?
        var createdAt: Date
        var duration: TimeInterval

        init(
            title: String = "",
            transcript: String = "",
            blogContent: String = "",
            instagramCaptions: String = "",
            linkedinPost: String = "",
            audioFilename: String? = nil,
            createdAt: Date = .now,
            duration: TimeInterval = 0
        ) {
            self.id = UUID()
            self.title = title
            self.transcript = transcript
            self.blogContent = blogContent
            self.instagramCaptions = instagramCaptions
            self.linkedinPost = linkedinPost
            self.audioFilename = audioFilename
            self.createdAt = createdAt
            self.duration = duration
        }
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [BlogPost.self]
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self]
    static var stages: [MigrationStage] = [migrateV1toV2]

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}

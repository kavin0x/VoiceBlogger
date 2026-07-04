import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [SchemaV1.BlogPost.self]

    @Model
    final class BlogPost {
        var id: UUID = UUID()
        var title: String = ""
        var transcript: String = ""
        var blogContent: String = ""
        var instagramCaptions: String = ""
        var linkedinPost: String = ""
        var audioFilename: String?
        var createdAt: Date = Date()
        var duration: TimeInterval = 0

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

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] = [
        BlogPost.self,
        CustomVocabularyEntry.self,
        CustomDictationMode.self
    ]
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    static var stages: [MigrationStage] = [migrateV1toV2, migrateV2toV3]

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
}

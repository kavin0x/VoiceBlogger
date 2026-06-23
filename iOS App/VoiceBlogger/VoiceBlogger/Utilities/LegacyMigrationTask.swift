import Foundation
import SwiftData

// Migrates blog posts from the pre-versioning "default.store" (SchemaV1 shape)
// into the current "VoiceBlogger-v2.store" (SchemaV2). Runs once on first
// launch after upgrading, then becomes a no-op forever.
//
// Two-loader design:
//   Loader A — opens the legacy store read-only using SchemaV1, which exactly
//              matches its on-disk schema (no migration needed to open it).
//   Loader B — the app's main ModelContext (SchemaV2, injected by caller).
//   Worker   — reads from A, writes to B, inferring transcriptionState from
//              each post's transcript content.
@MainActor
func migrateLegacyStoreIfNeeded(into context: ModelContext) async {
    guard !UserDefaults.standard.bool(forKey: "legacyMigrationV2Complete") else { return }

    let legacyURL = URL.applicationSupportDirectory
        .appendingPathComponent("default.store")

    guard FileManager.default.fileExists(atPath: legacyURL.path) else {
        UserDefaults.standard.set(true, forKey: "legacyMigrationV2Complete")
        return
    }

    // Loader A: open default.store with the current BlogPost schema (writable).
    // CoreData's automatic migration adds the transcriptionState column in-place
    // with nil for every existing row — all original data survives.
    // No name = "default.store", which is where the old data lives.
    let legacySchema = Schema([BlogPost.self])
    let legacyConfig = ModelConfiguration(schema: legacySchema, isStoredInMemoryOnly: false)
    guard let legacyContainer = try? ModelContainer(for: legacySchema, configurations: [legacyConfig]) else {
        return
    }

    let legacyContext = ModelContext(legacyContainer)
    guard let oldPosts = try? legacyContext.fetch(FetchDescriptor<BlogPost>()) else { return }

    // Worker: copy each record into the new store, inferring transcriptionState
    // from transcript content since the column was nil before.
    for old in oldPosts {
        let state: TranscriptionState = old.transcript.isEmpty ? .untranscribed : .complete
        context.insert(BlogPost(
            title: old.title,
            transcript: old.transcript,
            blogContent: old.blogContent,
            instagramCaptions: old.instagramCaptions,
            linkedinPost: old.linkedinPost,
            audioFilename: old.audioFilename,
            createdAt: old.createdAt,
            duration: old.duration,
            transcriptionState: state
        ))
    }

    // Only mark migration complete if the save succeeds. If it fails, the flag
    // stays unset so migration reruns on the next launch rather than silently
    // discarding all migrated posts.
    do {
        try context.save()
        UserDefaults.standard.set(true, forKey: "legacyMigrationV2Complete")
    } catch {
        // Save failed — migration will retry on next launch.
    }
}

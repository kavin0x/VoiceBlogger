import SwiftUI
import SwiftData

/*
 hi :)
 */
@main
struct VoiceBloggerApp: App {
    @State private var appState = AppState()
    @State private var audioRecorder = AudioRecorder()
    @State private var downloadManager = ModelDownloadManager()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([BlogPost.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            // Primary path: staged migration for stores that carry version metadata
            // (any store created after this versioning was introduced).
            return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        } catch {
            // Fallback: the store predates versioning and has no version fingerprint,
            // so staged migration can't identify the starting version. CoreData's
            // automatic lightweight migration takes over instead — it infers the
            // mapping from the stored model hash and fills new non-optional columns
            // using their inline property defaults (e.g. linkedinPost = "").
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch let fallbackError {
                fatalError("Could not create ModelContainer: \(fallbackError)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(audioRecorder)
                .environment(downloadManager)
                .task {
                    await downloadManager.warmWhisper()
                    if onboardingComplete && !downloadManager.allModelsReady {
                        appState.navigateTo(.modelDownload)
                    }
                }
        }

        .modelContainer(sharedModelContainer)

        /*
         bye :)
         */
    }

}

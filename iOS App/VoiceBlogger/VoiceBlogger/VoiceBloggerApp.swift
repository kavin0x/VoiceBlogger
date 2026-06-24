import SwiftUI
import SwiftData

@main
struct VoiceBloggerApp: App {
    @State private var appState = AppState()
    @State private var audioRecorder = AudioRecorder()
    @State private var downloadManager = ModelDownloadManager()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([BlogPost.self])
        let storeURL = URL.applicationSupportDirectory.appendingPathComponent("VoiceBlogger-v2.store")
        let config = ModelConfiguration("VoiceBloggerV2", schema: schema, url: storeURL)
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
                    // Skip model gating entirely during UI tests so views are reachable
                    // without downloading ~2.5 GB of models on every test run.
                    guard ProcessInfo.processInfo.environment["UI_TESTING"] == nil else { return }
                    // validatePersistedModelReadiness heals UserDefaults from actual disk state,
                    // so models already on disk are recognized even after an app update that
                    // would otherwise clear the ready flags and force a spurious re-download.
                    downloadManager.validatePersistedModelReadiness()
                    if onboardingComplete && !downloadManager.allModelsReady {
                        appState.navigateTo(.modelDownload)
                        downloadManager.continuePendingDownloadIfNeeded()
                    } else if onboardingComplete {
                        await downloadManager.warmWhisper()
                    }
                }
        }

        .modelContainer(sharedModelContainer)
    }

}

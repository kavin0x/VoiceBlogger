import SwiftUI
import SwiftData

private func applyDataProtection(to storeURL: URL) {
    let fm = FileManager.default
    // SQLite creates three files: the main store, a WAL journal, and a shared-memory file.
    // Protect all three so no file can be read while the device is locked.
    for suffix in ["", "-wal", "-shm"] {
        let fileURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + suffix)
        guard fm.fileExists(atPath: fileURL.path) else { continue }
        try? fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }
}

@main
struct VoiceBloggerApp: App {
    @State private var appState = AppState()
    @State private var audioRecorder = AudioRecorder()
    @State private var downloadManager = ModelDownloadManager()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([BlogPost.self, CustomVocabularyEntry.self, CustomDictationMode.self])
        let storeURL = URL.applicationSupportDirectory.appendingPathComponent("VoiceBlogger-v2.store")
        let config = ModelConfiguration("VoiceBloggerV2", schema: schema, url: storeURL)
        do {
            // Primary path: staged migration for stores that carry version metadata
            // (any store created after this versioning was introduced).
            let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
            applyDataProtection(to: storeURL)
            return container
        } catch {
            // Fallback: the store predates versioning and has no version fingerprint,
            // so staged migration can't identify the starting version. CoreData's
            // automatic lightweight migration takes over instead — it infers the
            // mapping from the stored model hash and fills new non-optional columns
            // using their inline property defaults (e.g. linkedinPost = "").
            do {
                let container = try ModelContainer(for: schema, configurations: [config])
                applyDataProtection(to: storeURL)
                return container
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
                    BackgroundTranscriptionScheduler.register()
                    audioRecorder.recoverStaleRecordingActivityIfNeeded()
                    // Skip model gating entirely during UI tests so views are reachable
                    // without downloading ~2.5 GB of models on every test run.
                    guard ProcessInfo.processInfo.environment["UI_TESTING"] == nil else { return }
                    // validatePersistedModelReadiness heals UserDefaults from actual disk state,
                    // so models already on disk are recognized even after an app update that
                    // would otherwise clear the ready flags and force a spurious re-download.
                    downloadManager.validatePersistedModelReadiness()
                    let intentPending = IntentStorage.hasStartRecordingPending()
                        || IntentStorage.hasStopRecordingPending()
                    if onboardingComplete && !downloadManager.allModelsReady && !intentPending {
                        appState.navigateTo(.modelDownload)
                        downloadManager.continuePendingDownloadIfNeeded()
                    } else if onboardingComplete {
                        Task { await downloadManager.warmWhisper() }
                    }
                }
        }

        .modelContainer(sharedModelContainer)
    }

}

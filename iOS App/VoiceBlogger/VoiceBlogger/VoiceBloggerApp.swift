import SwiftUI
import SwiftData

@main
struct VoiceBloggerApp: App {
    init() {
        // Runs after stored properties, and again is a no-op if the load-time
        // constructor already installed the Metal name guard.
        MLXMetalStartup.installIfNeeded()
        ContentKindDetectionSettings.promoteToDefaultOnIfNeeded()
    }
    @State private var appState = AppState()
    @State private var audioRecorder = AudioRecorder()
    @State private var downloadManager = ModelDownloadManager()
    @State private var library = LibraryStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(audioRecorder)
                .environment(downloadManager)
                .environment(library)
                .id(library.generation)
                .task {
                    BackgroundTranscriptionScheduler.register(
                        modelContainer: library.container,
                        whisperKitProvider: { downloadManager.whisperKit }
                    )
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

        .modelContainer(library.container)
    }

}

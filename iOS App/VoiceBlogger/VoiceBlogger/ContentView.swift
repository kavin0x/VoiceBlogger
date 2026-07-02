import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(AudioRecorder.self) var audioRecorder
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    @State private var darwinObserverToken: UnsafeMutableRawPointer?

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView()
            } else {
                stageView
            }
        }
        .onContinueUserActivity("anup.VoiceBlogger.StartRecordingIntent") { _ in
            IntentFulfillment.shared.handleStartRecording(onboardingComplete: onboardingComplete)
        }
        .onContinueUserActivity("anup.VoiceBlogger.StopRecordingIntent") { _ in
            IntentFulfillment.shared.handleStopRecording(onboardingComplete: onboardingComplete)
        }
        .onAppear {
            configureIntentFulfillment()
            installDarwinObserverIfNeeded()
            processPendingIntents()
        }
        .onDisappear {
            removeDarwinObserverIfNeeded()
        }
        .onChange(of: onboardingComplete) { _, complete in
            guard complete else { return }
            processPendingIntents()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            processPendingIntents()
        }
        .onOpenURL { url in
            guard url.scheme == "voiceblogger" else { return }
            switch url.host {
            case "intent":
                switch url.lastPathComponent {
                case "start":
                    IntentFulfillment.shared.handleStartRecording(onboardingComplete: onboardingComplete)
                case "stop":
                    IntentFulfillment.shared.handleStopRecording(onboardingComplete: onboardingComplete)
                default:
                    break
                }
            case "activity":
                switch url.lastPathComponent {
                case VoiceBloggerActivityAttributes.ActivityKind.recording.rawValue:
                    appState.navigateTo(.recording)
                case VoiceBloggerActivityAttributes.ActivityKind.downloading.rawValue:
                    appState.navigateTo(.modelDownload)
                default:
                    break
                }
            default:
                break
            }
        }
        .task {
            await migrateLegacyStoreIfNeeded(into: modelContext)
        }
        .alert("Error", isPresented: Binding(
            get: { appState.showError },
            set: { appState.showError = $0 }
        )) {
            Button("OK") { appState.dismissError() }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var stageView: some View {
        switch appState.stage {
        case .modelDownload:
            ModelDownloadView()

        case .recording:
            RecordingView()

        case .transcribing(let post):
            TranscriptionView(post: post)

        case .preparingBlog(let postID):
            BlogGenerationPrepView(postID: postID)

        case .generatingBlog(let post):
            BlogView(post: post)

        case .viewingBlog(let post):
            BlogView(post: post)

        case .viewingInstagram(let post):
            InstagramView(post: post)

        case .viewingLinkedIn(let post):
            LinkedInView(post: post)

        case .history:
            BlogListView()
        }
    }

    private func configureIntentFulfillment() {
        IntentFulfillment.shared.configure(
            appState: appState,
            recorder: audioRecorder,
            downloadManager: downloadManager,
            modelContext: modelContext
        )
    }

    private func processPendingIntents() {
        configureIntentFulfillment()
        IntentFulfillment.shared.processPendingIntents(onboardingComplete: onboardingComplete)
    }

    private func installDarwinObserverIfNeeded() {
        guard darwinObserverToken == nil else { return }
        darwinObserverToken = IntentStorage.addDarwinObserver {
            Task { @MainActor in
                let onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
                IntentFulfillment.shared.processPendingIntents(onboardingComplete: onboardingComplete)
            }
        }
    }

    private func removeDarwinObserverIfNeeded() {
        guard let darwinObserverToken else { return }
        IntentStorage.removeDarwinObserver(darwinObserverToken)
        self.darwinObserverToken = nil
    }
}

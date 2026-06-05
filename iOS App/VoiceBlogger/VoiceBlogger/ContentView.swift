import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            if !onboardingComplete && !downloadManager.allModelsReady {
                OnboardingView()
            } else if !downloadManager.allModelsReady {
                ModelDownloadView()
            } else {
                stageView
            }
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

        case .history:
            BlogListView()
        }
    }
}

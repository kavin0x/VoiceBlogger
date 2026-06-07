import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) var appState
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView()
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
            RecordingView()

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
}

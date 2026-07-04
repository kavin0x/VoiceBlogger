import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            Tab("Record", systemImage: "mic.fill", value: MainTab.record) {
                RecordingView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: MainTab.history) {
                BlogListView()
            }
            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                AboutView()
            }
        }
        .fullScreenCover(item: flowBinding) { flow in
            flowView(for: flow)
        }
    }

    private var flowBinding: Binding<AppFlow?> {
        Binding(
            get: {
                switch appState.stage {
                case .recording, .history, .modelDownload:
                    return nil
                default:
                    return AppFlow(stage: appState.stage)
                }
            },
            set: { newValue in
                if newValue == nil {
                    appState.navigateTo(.recording)
                }
            }
        )
    }

    @ViewBuilder
    private func flowView(for flow: AppFlow) -> some View {
        switch flow.stage {
        case .modelDownload:
            ModelDownloadView()
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
        default:
            EmptyView()
        }
    }
}

private struct AppFlow: Identifiable {
    let id = UUID()
    let stage: AppStage
}

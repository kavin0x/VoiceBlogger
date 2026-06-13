import SwiftUI
import SwiftData

struct BlogGenerationPrepView: View {
    let postID: UUID
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var didStart = false
    @State private var error: String?

    init(postID: UUID) {
        self.postID = postID
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Back to Transcript") {
                        if let post = fetchFreshPost() {
                            appState.navigateTo(.transcribing(post: post))
                        } else {
                            appState.navigateTo(.history)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView()
                    Text("Preparing Blog Generator...")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Blog Post")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await prepareAndContinue()
            }
        }
    }

    private func prepareAndContinue() async {
        guard !didStart else { return }
        didStart = true

        guard let post = fetchFreshPost() else {
            error = "Could not reload the saved transcript. Open History and try again."
            return
        }

        let transcript = BlogGenerationHandoff.preparedTranscript(from: post.transcript)
        guard !transcript.isEmpty else {
            error = "Transcript is empty. Re-transcribe before generating a blog post."
            return
        }

        post.transcript = transcript
        post.transcriptionState = .complete
        // Clear any previously generated content so BlogView always runs a fresh generation.
        post.blogContent = ""
        post.title = ""
        try? modelContext.save()

        await downloadManager.prepareForLLMGenerationBarrier(releaseLLM: true)

        // A crash/reopen discards transient model state and uses a freshly fetched
        // SwiftData object. Do the same here, then let BlogView load the LLM cleanly.
        appState.navigateTo(.generatingBlog(post: post))
    }

    private func fetchFreshPost() -> BlogPost? {
        let freshContext = ModelContext(modelContext.container)
        var descriptor = FetchDescriptor<BlogPost>(
            predicate: #Predicate { post in
                post.id == postID
            }
        )
        descriptor.fetchLimit = 1

        guard let post = try? freshContext.fetch(descriptor).first else {
            return nil
        }

        appState.generationModelContext = freshContext
        return post
    }
}

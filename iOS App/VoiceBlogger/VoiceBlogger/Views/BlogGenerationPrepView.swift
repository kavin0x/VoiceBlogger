import SwiftUI
import SwiftData

struct BlogGenerationPrepView: View {
    let postID: UUID
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var didStart = false
    @State private var error: String?
    @State private var prepStep = String(localized: "Preparing generator…")

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
                    Text(prepStep)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Generate")
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

        var transcript = BlogGenerationHandoff.preparedTranscript(from: post.transcript)
        guard !transcript.isEmpty else {
            error = "Transcript is empty. Re-transcribe before generating content."
            return
        }

        if TranscriptionSettings.polishTranscriptEnabled {
            prepStep = String(localized: "Polishing transcript…")
            do {
                await downloadManager.prepareForLLMGenerationBarrier(releaseLLM: false)
                let llm = try await downloadManager.loadedLLMService()
                transcript = try await llm.polishTranscript(transcript)
                post.transcript = transcript
            } catch {
                // Polish is optional — continue with raw transcript.
            }
        }

        post.transcript = transcript
        post.transcriptionState = .complete
        post.blogContent = ""
        post.title = ""
        try? modelContext.save()

        prepStep = String(localized: "Unloading speech model…")
        await downloadManager.prepareForLLMGenerationBarrier(releaseLLM: false)

        prepStep = String(localized: "Loading writing assistant…")
        do {
            _ = try await downloadManager.loadedLLMService()
        } catch {
            self.error = String(
                localized: "The writing assistant could not load: \(error.localizedDescription)"
            )
            return
        }

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

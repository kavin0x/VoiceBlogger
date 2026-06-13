import SwiftUI
import SwiftData

struct TranscriptionView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var isTranscribing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if isTranscribing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing… Please keep the app open!")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { runTranscription() }
                        Button("Reset & Re-download Models", role: .destructive) {
                            downloadManager.resetDownloads()
                            appState.navigateTo(.modelDownload)
                        }
                    }
                }

                // Crash-recovery banner for interrupted transcription
                if !isTranscribing && post.transcriptionState == .inProgress {
                    Section {
                        Label("Transcription was interrupted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("You can use the partial transcript below, re-transcribe from scratch, or generate a blog post from what's here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !post.transcript.isEmpty {
                    Section("Transcript") {
                        ScrollView {
                            Text(post.transcript)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }

                    if !isTranscribing {
                        Section {
                            Button {
                                generateBlog()
                            } label: {
                                Text("Generate Blog Post")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.borderedProminent)
                            .disabled(!BlogGenerationHandoff.canGenerateBlog(
                                from: post.transcript,
                                isBusy: false
                            ))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        appState.navigateTo(.recording)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isTranscribing && post.audioFileURL != nil &&
                        (post.transcriptionState != .untranscribed || !post.transcript.isEmpty) {
                        Button("Re-transcribe") {
                            post.transcript = ""
                            post.transcriptionState = .untranscribed
                            runTranscription()
                        }
                    }
                }
            }
            .task {
                if post.transcriptionState == .untranscribed {
                    runTranscription()
                }
            }
        }
    }

    private func runTranscription() {
        guard let audioURL = post.audioFileURL else {
            error = "Audio file not found. The recording may have been deleted."
            return
        }
        isTranscribing = true
        error = nil
        post.transcriptionState = .inProgress

        Task {
            do {
                let service = try await TranscriptionService.make(reusing: downloadManager.whisperKit)
                let finalText = try await service.transcribe(
                    audioURL: audioURL,
                    mode: .transcribe(language: nil),
                    onPartial: { partial in
                        Task { @MainActor in
                            post.transcript = partial
                        }
                    }
                )
                // Free WhisperKit memory before any later LLM generation to prevent OOM.
                await service.cleanup()
                downloadManager.whisperKit = nil
                Task {
                    await downloadManager.warmWhisper()
                }
                post.transcript = finalText
                post.transcriptionState = .complete
                try? modelContext.save()
            } catch {
                self.error = error.localizedDescription
                // Leave state as .inProgress so the recovery banner shows on next open
            }
            isTranscribing = false
        }
    }

    private func generateBlog() {
        guard BlogGenerationHandoff.canGenerateBlog(
            from: post.transcript,
            isBusy: false
        ) else {
            return
        }

        let transcript = BlogGenerationHandoff.preparedTranscript(from: post.transcript)
        post.transcript = transcript
        post.transcriptionState = .complete
        try? modelContext.save()
        Task {
            await downloadManager.prepareForLLMGeneration(releaseLLM: true)
            appState.navigateTo(.preparingBlog(postID: post.id))
        }
    }
}

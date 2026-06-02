import SwiftUI
import SwiftData
import MLX

struct TranscriptionView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var isTranscribing = false
    @State private var useTranslation = false
    @State private var selectedLanguage = "auto"
    @State private var error: String?

    private let supportedLanguages: [(String, String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("hi", "Hindi"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ar", "Arabic")
    ]

    private var currentMode: TranscriptionMode {
        if useTranslation {
            return .translate
        }
        return .transcribe(language: selectedLanguage == "auto" ? nil : selectedLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Mode", selection: $useTranslation) {
                        Text("Transcribe").tag(false)
                        Text("Translate → English").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if !useTranslation {
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(supportedLanguages, id: \.0) { code, name in
                                Text(name).tag(code)
                            }
                        }
                    }
                }

                if isTranscribing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing with Whisper…")
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
                            Button("Generate Blog Post") {
                                generateBlog()
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.borderedProminent)
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
                    mode: currentMode,
                    onPartial: { partial in
                        Task { @MainActor in
                            post.transcript = partial
                        }
                    }
                )
                // Free WhisperKit memory before LLM generation to prevent OOM.
                service.cleanup()
                downloadManager.whisperKit = nil
                MLX.Memory.clearCache()
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
        downloadManager.prepareForLLMGeneration()
        appState.navigateTo(.generatingBlog(transcript: post.transcript, post: post))
    }
}

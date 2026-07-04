import SwiftUI
import SwiftData

struct TranscriptionView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(AudioRecorder.self) var recorder
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var isTranscribing = false
    @State private var isRefining = false
    @State private var error: String?
    @State private var editableTranscript = ""
    @State private var detectedLanguage: String?

    var body: some View {
        NavigationStack {
            Form {
                if isTranscribing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if isRefining {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Refining transcript…")
                                    .foregroundStyle(.secondary)
                                Text("Preview shown below — final pass runs on the full recording.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { runTranscription(isRefinement: false) }
                        Button("Reset & Re-download Models", role: .destructive) {
                            downloadManager.resetDownloads()
                            appState.navigateTo(.modelDownload)
                        }
                    }
                }

                if !isTranscribing && post.transcriptionState == .inProgress && !isRefining {
                    if recorder.isFinalizingTranscript {
                        Section {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Finalizing preview…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if post.transcript.isEmpty {
                        Section {
                            Label("Transcription was interrupted", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("You can re-transcribe from scratch or generate from any partial transcript below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !post.transcript.isEmpty || !editableTranscript.isEmpty {
                    if let audioURL = post.audioFileURL {
                        Section {
                            AudioPlayerView(audioURL: audioURL)
                        }
                    }

                    Section {
                        if recorder.isLivePreview || isRefining {
                            Label("Preview", systemImage: "text.line.first.and.arrowtriangle.forward")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let detectedLanguage {
                            Label("Detected: \(TranscriptionSettings.languageLabel(for: detectedLanguage))", systemImage: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Transcript") {
                        if isTranscribing {
                            ScrollView {
                                Text(post.transcript)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 300)
                        } else {
                            TextEditor(text: $editableTranscript)
                                .font(.body)
                                .frame(minHeight: 240)
                                .accessibilityLabel("Editable transcript")

                            if editableTranscript != post.transcript {
                                Button("Save Transcript") {
                                    saveEditedTranscript()
                                }
                            }
                        }
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
                                from: editableTranscript,
                                isBusy: isRefining
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
                    if !isTranscribing && !isRefining && post.audioFileURL != nil &&
                        (post.transcriptionState != .untranscribed || !post.transcript.isEmpty) {
                        Button("Re-transcribe") {
                            post.transcript = ""
                            editableTranscript = ""
                            post.detectedSpeakerCount = 0
                            post.transcriptionState = .untranscribed
                            detectedLanguage = nil
                            runTranscription(isRefinement: false)
                        }
                    }
                }
            }
            .onAppear {
                editableTranscript = post.transcript
                downloadManager.warmLLMIfNeeded()
                if post.transcriptionState == .inProgress && !recorder.isFinalizingTranscript {
                    applyLiveTranscriptAndRefine()
                }
            }
            .onDisappear {
                if !isTranscribing {
                    saveEditedTranscript()
                }
            }
            .onChange(of: recorder.isFinalizingTranscript) { _, isFinalizing in
                guard !isFinalizing, post.transcriptionState == .inProgress else { return }
                applyLiveTranscriptAndRefine()
            }
            .task {
                if post.transcriptionState == .untranscribed {
                    runTranscription(isRefinement: false)
                }
            }
        }
    }

    /// Applies live preview text, then always runs the authoritative full-file pass.
    private func applyLiveTranscriptAndRefine() {
        let previewText = recorder.liveTranscript.isEmpty ? post.transcript : recorder.liveTranscript
        guard !previewText.isEmpty else {
            if post.transcriptionState == .inProgress {
                runTranscription(isRefinement: false)
            }
            return
        }
        post.transcript = previewText
        editableTranscript = previewText
        post.detectedSpeakerCount = 1
        recorder.isLivePreview = false
        try? modelContext.save()
        runTranscription(isRefinement: true)
    }

    private func runTranscription(isRefinement: Bool) {
        guard let audioURL = post.audioFileURL else {
            error = "Audio file not found. The recording may have been deleted."
            return
        }
        if isRefinement {
            isRefining = true
        } else {
            isTranscribing = true
        }
        error = nil
        post.transcriptionState = .inProgress

        Task {
            do {
                let service = try await TranscriptionService.make(reusing: downloadManager.whisperKit)
                let mode = TranscriptionSettings.transcriptionMode
                let finalTranscript = try await service.transcribe(
                    audioURL: audioURL,
                    mode: mode,
                    onPartial: { partial in
                        Task { @MainActor in
                            if isRefinement {
                                editableTranscript = partial
                            } else {
                                post.transcript = partial
                                editableTranscript = partial
                            }
                        }
                    }
                )
                // Keep Whisper warm until blog generation (deferred unload).
                post.transcript = finalTranscript.displayText
                editableTranscript = finalTranscript.displayText
                post.detectedSpeakerCount = finalTranscript.detectedSpeakerCount
                post.transcriptionState = .complete
                if case .transcribe(let lang) = mode, let lang {
                    detectedLanguage = lang
                }
                try? modelContext.save()
                BackgroundTranscriptionScheduler.schedule(postID: post.id)
            } catch {
                self.error = error.localizedDescription
                if !isRefinement {
                    post.transcriptionState = .inProgress
                } else if !editableTranscript.isEmpty {
                    post.transcriptionState = .complete
                }
            }
            isTranscribing = false
            isRefining = false
        }
    }

    private func saveEditedTranscript() {
        let transcript = BlogGenerationHandoff.preparedTranscript(from: editableTranscript)
        guard transcript != post.transcript else { return }
        editableTranscript = transcript
        post.transcript = transcript
        post.detectedSpeakerCount = transcript.isEmpty ? 0 : 1
        post.transcriptionState = transcript.isEmpty ? .untranscribed : .complete
        try? modelContext.save()
    }

    private func generateBlog() {
        guard BlogGenerationHandoff.canGenerateBlog(
            from: editableTranscript,
            isBusy: isRefining
        ) else {
            return
        }

        saveEditedTranscript()
        appState.navigateTo(.preparingBlog(postID: post.id))
    }
}

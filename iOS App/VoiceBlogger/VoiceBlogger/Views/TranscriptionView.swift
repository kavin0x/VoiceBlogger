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
    @State private var showAudioShareSheet = false
    @State private var transcriptionAttemptID = UUID()

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

                if let audioURL = availableAudioURL {
                    Section("Recording") {
                        AudioPlayerView(audioURL: audioURL)
                        Button {
                            showAudioShareSheet = true
                        } label: {
                            Label("Share or Export Audio", systemImage: "square.and.arrow.up")
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
                if post.transcriptionState == .complete {
                    downloadManager.warmLLMIfNeeded()
                }
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
            .sheet(isPresented: $showAudioShareSheet) {
                if let audioURL = availableAudioURL {
                    ShareSheet(items: [audioURL])
                }
            }
            .task {
                if post.transcriptionState == .untranscribed {
                    runTranscription(isRefinement: false)
                }
            }
        }
    }

    /// Applies live preview text, then runs the authoritative full-file pass when needed.
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
        let hadLivePreview = recorder.isLivePreview || !recorder.liveTranscript.isEmpty
        recorder.isLivePreview = false
        try? modelContext.save()

        if InferencePerformancePolicy.shouldSkipFullFileRefinement(
            recordingDuration: post.duration,
            previewText: previewText,
            hadLivePreview: hadLivePreview
        ) {
            post.transcriptionState = .complete
            try? modelContext.save()
            downloadManager.warmLLMIfNeeded()
            return
        }
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
        let refinementFallback = isRefinement ? post.transcript : nil
        let attemptID = UUID()
        transcriptionAttemptID = attemptID

        Task {
            do {
                try await downloadManager.ensureWhisperWarm()
                let service = try await TranscriptionService.make(reusing: downloadManager.whisperKit)
                let mode = TranscriptionSettings.transcriptionMode
                let finalTranscript = try await service.transcribe(
                    audioURL: audioURL,
                    mode: mode,
                    onPartial: { partial in
                        Task { @MainActor in
                            guard transcriptionAttemptID == attemptID else { return }
                            if isRefinement {
                                editableTranscript = partial
                            } else {
                                post.transcript = partial
                                editableTranscript = partial
                            }
                        }
                    }
                )
                guard transcriptionAttemptID == attemptID else { return }
                transcriptionAttemptID = UUID()
                // Keep Whisper warm until blog generation (deferred unload).
                post.transcript = finalTranscript.displayText
                editableTranscript = finalTranscript.displayText
                post.detectedSpeakerCount = finalTranscript.detectedSpeakerCount
                post.transcriptionState = .complete
                self.error = nil
                appState.dismissError()
                if case .transcribe(let lang) = mode, let lang {
                    detectedLanguage = lang
                }
                try? modelContext.save()
                BackgroundTranscriptionScheduler.schedule(postID: post.id)
                downloadManager.warmLLMIfNeeded()
            } catch {
                guard transcriptionAttemptID == attemptID else { return }
                transcriptionAttemptID = UUID()
                let candidate = isRefinement ? (refinementFallback ?? "") : editableTranscript
                let hasUsableTranscript = !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let resolution = TranscriptionFailurePolicy.resolve(
                    isRefinement: isRefinement,
                    hasUsableTranscript: hasUsableTranscript
                )
                post.transcriptionState = resolution.transcriptionState
                if resolution.showsError {
                    self.error = error.localizedDescription
                } else {
                    if let refinementFallback {
                        post.transcript = refinementFallback
                        editableTranscript = refinementFallback
                    }
                    self.error = nil
                    appState.dismissError()
                }
                try? modelContext.save()
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

    private var availableAudioURL: URL? {
        guard let url = post.audioFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }
}

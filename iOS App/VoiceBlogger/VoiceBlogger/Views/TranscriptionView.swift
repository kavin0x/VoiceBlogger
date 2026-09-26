import SwiftUI
import SwiftData
import UIKit

struct TranscriptionView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(AudioRecorder.self) var recorder
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var isTranscribing = false
    @State private var isRefining = false
    @State private var refinePreview = ""
    @State private var transcriptWhenRefineStarted = ""
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
                                Text("Preview shown below — final pass runs on the full recording. Edits in the transcript stay put.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if !refinePreview.isEmpty {
                            Text(refinePreview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                reloadTranscriptSavedInBackground()
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

    /// Picks up a transcript written by the background task into a different model context.
    private func reloadTranscriptSavedInBackground() {
        let postID = post.id
        let backgroundContext = ModelContext(modelContext.container)
        var descriptor = FetchDescriptor<BlogPost>(
            predicate: #Predicate { item in
                item.id == postID
            }
        )
        descriptor.fetchLimit = 1
        guard let saved = try? backgroundContext.fetch(descriptor).first else { return }
        guard saved.transcriptionState == .complete, !saved.transcript.isEmpty else { return }
        guard saved.transcript != post.transcript || isTranscribing || isRefining else { return }
        post.transcript = saved.transcript
        post.detectedSpeakerCount = saved.detectedSpeakerCount
        post.transcriptionState = .complete
        if editableTranscript == transcriptWhenRefineStarted || editableTranscript.isEmpty || isTranscribing || isRefining {
            editableTranscript = saved.transcript
        }
        isTranscribing = false
        isRefining = false
        refinePreview = ""
        try? modelContext.save()
        if appState.copyTranscriptToClipboard {
            UIPasteboard.general.string = post.transcript
            appState.copyTranscriptToClipboard = false
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
            transcriptWhenRefineStarted = editableTranscript
            refinePreview = ""
        } else {
            isTranscribing = true
        }
        error = nil
        post.transcriptionState = .inProgress
        let refinementFallback = isRefinement ? post.transcript : nil
        let attemptID = UUID()
        transcriptionAttemptID = attemptID
        BackgroundTranscriptionScheduler.schedule(postID: post.id)

        let task = Task {
            do {
                try await downloadManager.ensureWhisperWarm()
                let service = try await TranscriptionService.make(reusing: downloadManager.whisperKit)
                let mode = TranscriptionSettings.transcriptionMode
                let vocabularyTerms = VocabularyStore.terms(from: modelContext)
                let finalTranscript = try await service.transcribe(
                    audioURL: audioURL,
                    mode: mode,
                    vocabularyTerms: vocabularyTerms,
                    onPartial: { partial in
                        Task { @MainActor in
                            guard transcriptionAttemptID == attemptID else { return }
                            if isRefinement {
                                refinePreview = partial
                            } else {
                                post.transcript = partial
                                editableTranscript = partial
                            }
                        }
                    }
                )
                guard transcriptionAttemptID == attemptID else { return }
                guard !Task.isCancelled else {
                    isTranscribing = false
                    isRefining = false
                    refinePreview = ""
                    return
                }
                transcriptionAttemptID = UUID()
                let userEditedDuringRefine = isRefinement && editableTranscript != transcriptWhenRefineStarted
                if userEditedDuringRefine {
                    let kept = BlogGenerationHandoff.preparedTranscript(from: editableTranscript)
                    post.transcript = kept
                } else {
                    post.transcript = finalTranscript.displayText
                    editableTranscript = finalTranscript.displayText
                }
                post.detectedSpeakerCount = finalTranscript.detectedSpeakerCount
                post.transcriptionState = .complete
                self.error = nil
                appState.dismissError()
                if case .transcribe(let lang) = mode, let lang {
                    detectedLanguage = lang
                }
                try? modelContext.save()
                BackgroundTranscriptionScheduler.clearPending(postID: post.id)
                if appState.copyTranscriptToClipboard {
                    let textToCopy = userEditedDuringRefine ? post.transcript : finalTranscript.displayText
                    if !textToCopy.isEmpty {
                        UIPasteboard.general.string = textToCopy
                    }
                    appState.copyTranscriptToClipboard = false
                }
                downloadManager.warmLLMIfNeeded()
            } catch is CancellationError {
                isTranscribing = false
                isRefining = false
                refinePreview = ""
                return
            } catch {
                guard transcriptionAttemptID == attemptID else { return }
                if Task.isCancelled {
                    isTranscribing = false
                    isRefining = false
                    refinePreview = ""
                    return
                }
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
                    BackgroundTranscriptionScheduler.clearPending(postID: post.id)
                }
                try? modelContext.save()
                if appState.copyTranscriptToClipboard, hasUsableTranscript {
                    UIPasteboard.general.string = candidate
                    appState.copyTranscriptToClipboard = false
                }
            }
            isTranscribing = false
            isRefining = false
            refinePreview = ""
        }
        BackgroundTranscriptionScheduler.noteForegroundTask(task)
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

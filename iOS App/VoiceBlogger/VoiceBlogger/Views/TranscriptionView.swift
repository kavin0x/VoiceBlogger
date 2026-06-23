import SwiftUI
import SwiftData
import UIKit

struct TranscriptionView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var isTranscribing = false
    @State private var error: String?
    @State private var editableTranscript = ""
    @State private var transcriptionStatus = "Starting transcription..."
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var llmPrewarmTask: Task<Void, Never>?
    @State private var showAudioShareSheet = false
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    // Reference holder so the background-task expiry closure can cancel the task even though
    // TranscriptionView is a value type (capturing `self` by value would give a stale copy).
    @State private var taskHolder = TranscriptionTaskHolder()

    var body: some View {
        NavigationStack {
            Form {
                if isTranscribing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(transcriptionStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if post.audioFileURL != nil {
                            Button("Retry Transcription") { runTranscription(resetTranscript: false) }
                            Button("Share Audio") { showAudioShareSheet = true }
                        }
                        Button("Reset & Re-download Models", role: .destructive) {
                            downloadManager.resetDownloads()
                            appState.navigateTo(.modelDownload)
                        }
                    }
                }

                if !isTranscribing && post.transcriptionState == .inProgress {
                    Section {
                        Label("Transcription was interrupted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("VoiceBlogger will retry automatically while this screen is open. You can also keep the partial transcript or share the original audio.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !post.transcript.isEmpty || !editableTranscript.isEmpty {
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
                                Text(BlogGenerationHandoff.contentKind(for: editableTranscript).generationActionTitle)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.borderedProminent)
                            .disabled(!BlogGenerationHandoff.canGenerateBlog(
                                from: editableTranscript,
                                isBusy: false
                            ))
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                if !isTranscribing, post.audioFileURL != nil {
                    Section {
                        Button(post.transcript.isEmpty ? "Retry Transcription" : "Re-transcribe") {
                            runTranscription(resetTranscript: true)
                        }
                        Button("Share Audio") {
                            showAudioShareSheet = true
                        }
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
            }
            .sheet(isPresented: $showAudioShareSheet) {
                if let audioURL = post.audioFileURL {
                    ShareSheet(items: [audioURL])
                }
            }
            .onAppear {
                editableTranscript = post.transcript
            }
            .onDisappear {
                // Cancel any running transcription so it doesn't mutate downloadManager
                // (setting whisperKit = nil) after the user navigates to a different view
                // that may have already started a fresh transcription with the same instance.
                transcriptionTask?.cancel()
                transcriptionTask = nil
                // Cancel LLM pre-warm — if the user navigated away without generating,
                // the next view manages its own LLM lifecycle.
                llmPrewarmTask?.cancel()
                llmPrewarmTask = nil
                // Background task and idle timer are cleaned up by the task's completion
                // handler or expiry handler; no need to touch them here.
                if !isTranscribing {
                    saveEditedTranscript()
                }
            }
            .task {
                if post.transcriptionState == .untranscribed || post.transcriptionState == .inProgress {
                    runTranscription(resetTranscript: false)
                }
            }
        }
    }

    private func runTranscription(resetTranscript: Bool) {
        guard let audioURL = post.audioFileURL else {
            error = TranscriptionError.missingAudio.localizedDescription
            post.transcriptionState = .untranscribed
            try? modelContext.save()
            return
        }

        // Cancel any in-flight LLM pre-warm — it holds llmLoadTask, which would block
        // ensureWhisperWarm() from loading Whisper for the new transcription.
        llmPrewarmTask?.cancel()
        llmPrewarmTask = nil
        downloadManager.releaseLLMService()
        transcriptionTask?.cancel()
        taskHolder.task = nil
        if resetTranscript {
            post.transcript = ""
            editableTranscript = ""
        }
        isTranscribing = true
        transcriptionStatus = ""
        error = nil
        post.transcriptionState = .inProgress
        try? modelContext.save()

        // Keep screen on so the app doesn't suspend mid-transcription.
        UIApplication.shared.isIdleTimerDisabled = true

        // Request background execution time so iOS doesn't kill us if the user
        // switches apps briefly during the (potentially multi-minute) Whisper run.
        // Capture taskHolder (reference type) so the expiry closure sees the live task.
        let holder = taskHolder
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Transcription") { [holder] in
            // Expiry handler: iOS is about to suspend. Cancel gracefully.
            holder.task?.cancel()
            holder.task = nil
        }

        let task = Task {
            defer {
                isTranscribing = false
                endBackgroundTask()
                UIApplication.shared.isIdleTimerDisabled = false
                holder.task = nil
            }
            let progressMonitor = TranscriptionProgressMonitor()
            do {
                await downloadManager.ensureWhisperWarm()
                let service = try await TranscriptionService.make(reusing: downloadManager.whisperKit)
                let finalText = try await transcribeWithWatchdog(
                    service: service,
                    audioURL: audioURL,
                    progressMonitor: progressMonitor
                )
                guard !Task.isCancelled else {
                    await service.cleanup()
                    return
                }

                // Keep whisperKit alive — the increased-memory-limit entitlement allows
                // Whisper and the LLM to coexist in RAM, so there's no reason to unload.
                // Pre-warm the LLM so it's ready if the user taps Generate.
                llmPrewarmTask = Task { try? await downloadManager.loadedLLMService() }
                post.transcript = finalText
                editableTranscript = finalText
                post.transcriptionState = .complete
                try? modelContext.save()
            } catch is CancellationError {
                // Task was cancelled (e.g. view disappeared); leave .inProgress for recovery.
            } catch {
                self.error = error.localizedDescription
                post.transcriptionState = post.transcript.isEmpty ? .untranscribed : .inProgress
                try? modelContext.save()
            }
        }
        taskHolder.task = task
        transcriptionTask = task
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func transcribeWithWatchdog(
        service: TranscriptionService,
        audioURL: URL,
        progressMonitor: TranscriptionProgressMonitor
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await service.transcribe(
                    audioURL: audioURL,
                    mode: .transcribe(language: nil),
                    onProgress: { phase in
                        progressMonitor.markProgress()
                        Task { @MainActor in
                            transcriptionStatus = statusText(for: phase)
                        }
                    },
                    onPartial: { partial in
                        progressMonitor.markProgress()
                        Task { @MainActor in
                            post.transcript = partial
                            editableTranscript = partial
                        }
                    }
                )
            }

            group.addTask {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                    // 10 minutes without any progress callback from WhisperKit = genuinely stalled.
                    // whisper-medium can legitimately take several minutes on long audio segments
                    // without emitting a partial result, so 3 minutes was too aggressive.
                    if await progressMonitor.secondsSinceProgress() >= 600 {
                        throw TranscriptionError.stalled
                    }
                }
                throw CancellationError()
            }

            guard let result = try await group.next() else {
                throw TranscriptionError.stalled
            }
            group.cancelAll()
            return result
        }
    }

    private func statusText(for phase: TranscriptionProgressPhase) -> String {
        switch phase {
        case .loadingAudio:
            return "Loading recording..."
        case .transcribing:
            return "Transcribing... Keep VoiceBlogger in the foreground for best results."
        case .finishing:
            return "Finishing transcript..."
        }
    }

    private func saveEditedTranscript() {
        let transcript = BlogGenerationHandoff.preparedTranscript(from: editableTranscript)
        guard transcript != post.transcript else { return }
        editableTranscript = transcript
        post.transcript = transcript
        post.transcriptionState = transcript.isEmpty ? .untranscribed : .complete
        try? modelContext.save()
    }

    private func generateBlog() {
        guard BlogGenerationHandoff.canGenerateBlog(
            from: editableTranscript,
            isBusy: false
        ) else {
            return
        }

        saveEditedTranscript()
        appState.navigateTo(.preparingBlog(postID: post.id))
    }
}

// Reference type so the UIBackgroundTask expiry closure can cancel the task even though
// TranscriptionView is a value type (a struct). @State wraps this in reference storage.
// All accesses happen on the main thread (view body + background-task expiry callback).
private final class TranscriptionTaskHolder: @unchecked Sendable {
    var task: Task<Void, Never>?
}

private final class TranscriptionProgressMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgress = Date.now

    func markProgress() {
        lock.lock()
        lastProgress = .now
        lock.unlock()
    }

    func secondsSinceProgress() -> TimeInterval {
        lock.lock()
        let seconds = Date.now.timeIntervalSince(lastProgress)
        lock.unlock()
        return seconds
    }
}

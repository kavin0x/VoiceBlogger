import Foundation
import SwiftData

/// Executes start/stop recording intents from any entry point (Control Center, Siri, deep links).
@MainActor
final class IntentFulfillment {
    static let shared = IntentFulfillment()

    private var appState: AppState?
    private var recorder: AudioRecorder?
    private var downloadManager: ModelDownloadManager?
    private var modelContext: ModelContext?
    private var intentChain: Task<Void, Never>?

    private init() {}

    var isConfigured: Bool {
        appState != nil && recorder != nil && downloadManager != nil && modelContext != nil
    }

    func configure(
        appState: AppState,
        recorder: AudioRecorder,
        downloadManager: ModelDownloadManager,
        modelContext: ModelContext
    ) {
        self.appState = appState
        self.recorder = recorder
        self.downloadManager = downloadManager
        self.modelContext = modelContext
    }

    func processPendingIntents(onboardingComplete: Bool) {
        guard onboardingComplete, isConfigured else { return }
        guard let appState, let recorder, let downloadManager, let modelContext else { return }

        if IntentStorage.consumeDictateToClipboardPending() {
            appState.copyTranscriptToClipboard = true
        }

        let steps = RecordingIntentSequence.steps(
            startPending: IntentStorage.consumeStartRecordingPending(),
            stopPending: IntentStorage.consumeStopRecordingPending()
        )
        guard !steps.isEmpty else { return }

        let previous = intentChain
        let task = Task { @MainActor in
            await previous?.value
            for step in steps {
                switch step {
                case .start:
                    await self.startRecording(
                        appState: appState,
                        recorder: recorder,
                        downloadManager: downloadManager,
                        modelContext: modelContext
                    )
                case .stop:
                    self.stopRecording(appState: appState, recorder: recorder, modelContext: modelContext)
                }
            }
        }
        intentChain = task
    }

    func handleStartRecording(onboardingComplete: Bool) {
        guard IntentStorage.isAppGroupAvailable else {
            appState?.showError("VoiceBlogger could not access shared intent storage. Check that the App Group is enabled in your provisioning profile.")
            return
        }
        IntentStorage.markStartRecordingPending()
        processPendingIntents(onboardingComplete: onboardingComplete)
    }

    func handleStopRecording(onboardingComplete: Bool) {
        guard IntentStorage.isAppGroupAvailable else {
            appState?.showError("VoiceBlogger could not access shared intent storage. Check that the App Group is enabled in your provisioning profile.")
            return
        }
        IntentStorage.markStopRecordingPending()
        processPendingIntents(onboardingComplete: onboardingComplete)
    }

    private func startRecording(
        appState: AppState,
        recorder: AudioRecorder,
        downloadManager: ModelDownloadManager,
        modelContext: ModelContext
    ) async {
        appState.navigateTo(.recording)

        if recorder.permissionDenied {
            appState.showError(AudioRecorderError.microphonePermissionDenied.localizedDescription)
            return
        }
        guard !recorder.isRecording else { return }

        do {
            // Start capturing audio immediately; Whisper can finish loading in parallel.
            try await recorder.startRecording(
                whisperKit: downloadManager.whisperKit,
                vocabularyTerms: VocabularyStore.terms(from: modelContext)
            )
            if downloadManager.whisperKit == nil {
                Task {
                    await downloadManager.warmWhisper()
                    if recorder.isRecording {
                        recorder.attachWhisperKit(downloadManager.whisperKit)
                    }
                }
            } else {
                recorder.attachWhisperKit(downloadManager.whisperKit)
            }
        } catch {
            appState.showError("Recording failed: \(error.localizedDescription)")
            if !downloadManager.isWhisperReady {
                appState.navigateTo(.modelDownload)
            }
        }
    }

    private func stopRecording(
        appState: AppState,
        recorder: AudioRecorder,
        modelContext: ModelContext
    ) {
        guard recorder.isRecording, let audioURL = recorder.stopRecording() else { return }

        let duration = recorder.duration
        let post = BlogPost(
            audioFilename: audioURL.lastPathComponent,
            duration: duration,
            transcriptionState: .untranscribed
        )
        if !recorder.liveTranscript.isEmpty {
            post.transcript = recorder.liveTranscript
            post.transcriptionState = .inProgress
        }
        modelContext.insert(post)
        try? modelContext.save()
        appState.navigateTo(.transcribing(post: post))
    }
}

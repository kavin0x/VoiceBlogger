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

        if IntentStorage.consumeStartRecordingPending() {
            Task { await startRecording(appState: appState, recorder: recorder, downloadManager: downloadManager) }
        }

        if IntentStorage.consumeStopRecordingPending() {
            stopRecording(appState: appState, recorder: recorder, modelContext: modelContext)
        }
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
        downloadManager: ModelDownloadManager
    ) async {
        appState.navigateTo(.recording)

        if recorder.permissionDenied {
            appState.showError("Microphone access is required to record. Enable it in Settings.")
            return
        }
        guard !recorder.isRecording else { return }

        do {
            await downloadManager.ensureWhisperWarm()
            try await recorder.startRecording(whisperKit: downloadManager.whisperKit)
        } catch {
            appState.showError("Recording failed: \(error.localizedDescription)")
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

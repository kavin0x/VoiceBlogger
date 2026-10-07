import Foundation
import BackgroundTasks
import SwiftData
import UIKit
import WhisperKit

enum BackgroundTranscriptionScheduler {
    static let taskIdentifier = "com.voiceblogger.transcription"

    private static let pendingPostKey = "pendingBackgroundTranscriptionPostID"
    private static var modelContainer: ModelContainer?
    private static var didRegister = false
    private static var foregroundTask: Task<Void, Never>?
    private static var whisperKitProvider: (@MainActor () -> WhisperKit?)?

    static func updateModelContainer(_ modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    static func register(
        modelContainer: ModelContainer,
        whisperKitProvider: (@MainActor () -> WhisperKit?)? = nil
    ) {
        self.modelContainer = modelContainer
        self.whisperKitProvider = whisperKitProvider
        guard !didRegister else { return }
        didRegister = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(processingTask)
        }
    }

    static func noteForegroundTask(_ task: Task<Void, Never>?) {
        foregroundTask = task
    }

    static func schedule(postID: UUID, after delay: TimeInterval = 1) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        UserDefaults.standard.set(postID.uuidString, forKey: pendingPostKey)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func clearPending(postID: UUID) {
        if UserDefaults.standard.string(forKey: pendingPostKey) == postID.uuidString {
            UserDefaults.standard.removeObject(forKey: pendingPostKey)
        }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func pendingPostID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: pendingPostKey) else { return nil }
        return UUID(uuidString: raw)
    }

    nonisolated private static func handle(_ task: BGProcessingTask) {
        let completion = BackgroundTaskCompletion()
        let work = Task { @MainActor in
            let outcome = await performPendingTranscription()
            switch outcome {
            case .succeeded:
                completion.finish(task, success: true)
            case .giveUp:
                completion.finish(task, success: false)
            case .retry:
                if let postID = pendingPostID() {
                    schedule(postID: postID, after: BackgroundTranscriptionRetryPolicy.retryDelay)
                }
                completion.finish(task, success: false)
            }
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in
                if let postID = pendingPostID() {
                    schedule(postID: postID)
                }
            }
            completion.finish(task, success: false)
        }
    }

    @MainActor
    private static func performPendingTranscription() async -> BackgroundTranscriptionAttempt {
        guard let postID = pendingPostID(), let modelContainer else { return .giveUp }
        let appIsActive = UIApplication.shared.applicationState == .active
        if appIsActive, let foregroundTask, !foregroundTask.isCancelled {
            // The on-screen job is already transcribing. The caller re-queues the request.
            return .retry
        }

        if UIApplication.shared.applicationState != .active {
            foregroundTask?.cancel()
            await foregroundTask?.value
        }

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<BlogPost>(
            predicate: #Predicate { post in
                post.id == postID
            }
        )
        descriptor.fetchLimit = 1
        guard let post = try? context.fetch(descriptor).first else {
            clearPending(postID: postID)
            return .giveUp
        }
        if post.transcriptionState == .complete, !post.transcript.isEmpty {
            clearPending(postID: postID)
            return .succeeded
        }
        guard let audioURL = post.audioFileURL else {
            clearPending(postID: postID)
            return .giveUp
        }
        guard RecordingFileAccess.readiness(at: audioURL) == .ready else {
            return .retry
        }

        let reusedKit = whisperKitProvider?()
        do {
            let service = try await TranscriptionService.make(reusing: reusedKit)
            let result = try await service.transcribe(
                audioURL: audioURL,
                mode: TranscriptionSettings.transcriptionMode,
                vocabularyTerms: VocabularyStore.terms(from: context)
            )
            guard !Task.isCancelled else { return .retry }
            post.transcript = result.displayText
            post.detectedSpeakerCount = result.detectedSpeakerCount
            post.transcriptionState = .complete
            try context.save()
            if reusedKit == nil {
                await service.cleanup()
            }
            clearPending(postID: postID)
            return .succeeded
        } catch {
            let outcome = BackgroundTranscriptionRetryPolicy.attemptResult(fileReady: true, error: error)
            if outcome == .giveUp {
                clearPending(postID: postID)
            }
            return outcome
        }
    }

    private final class BackgroundTaskCompletion: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var finished = false

        nonisolated init() {}

        nonisolated func finish(_ task: BGProcessingTask, success: Bool) {
            lock.lock()
            let shouldFinish = !finished
            finished = true
            lock.unlock()
            if shouldFinish {
                task.setTaskCompleted(success: success)
            }
        }
    }
}

enum BackgroundTranscriptionAttempt: Equatable, Sendable {
    case succeeded
    case retry
    case giveUp
}

enum BackgroundTranscriptionRetryPolicy: Sendable {
    /// Wait before the next background attempt so a missing iCloud file does not spin.
    nonisolated static let retryDelay: TimeInterval = 60

    nonisolated static func attemptResult(fileReady: Bool, error: Error?) -> BackgroundTranscriptionAttempt {
        guard fileReady else { return .retry }
        guard let error else { return .succeeded }
        if error is CancellationError { return .retry }
        if let transcription = error as? TranscriptionError {
            switch transcription {
            case .stillDownloading, .notInitialized, .stalled:
                return .retry
            case .missingAudio, .unreadableAudio, .emptyResult:
                return .giveUp
            }
        }
        return .retry
    }
}

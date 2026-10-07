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

    static func schedule(postID: UUID) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
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
            let success = await performPendingTranscription()
            completion.finish(task, success: success)
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
    private static func performPendingTranscription() async -> Bool {
        guard let postID = pendingPostID(), let modelContainer else { return false }
        let appIsActive = UIApplication.shared.applicationState == .active
        if appIsActive, let foregroundTask, !foregroundTask.isCancelled {
            // The on-screen job is already transcribing. Leave the request queued.
            schedule(postID: postID)
            return false
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
            return false
        }
        if post.transcriptionState == .complete, !post.transcript.isEmpty {
            clearPending(postID: postID)
            return true
        }
        guard let audioURL = post.audioFileURL else { return false }
        guard RecordingFileAccess.readiness(at: audioURL) == .ready else {
            return false
        }

        let reusedKit = whisperKitProvider?()
        do {
            let service = try await TranscriptionService.make(reusing: reusedKit)
            let result = try await service.transcribe(
                audioURL: audioURL,
                mode: TranscriptionSettings.transcriptionMode,
                vocabularyTerms: VocabularyStore.terms(from: context)
            )
            guard !Task.isCancelled else { return false }
            post.transcript = result.displayText
            post.detectedSpeakerCount = result.detectedSpeakerCount
            post.transcriptionState = .complete
            try context.save()
            if reusedKit == nil {
                await service.cleanup()
            }
            clearPending(postID: postID)
            return true
        } catch {
            return false
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

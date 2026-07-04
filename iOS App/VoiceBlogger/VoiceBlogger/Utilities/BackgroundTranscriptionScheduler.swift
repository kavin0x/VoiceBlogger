import Foundation
import BackgroundTasks

enum BackgroundTranscriptionScheduler {
    static let taskIdentifier = "com.voiceblogger.transcription"

    static func register() {
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

    static func schedule(postID: UUID) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
        UserDefaults.standard.set(postID.uuidString, forKey: pendingPostKey)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static let pendingPostKey = "pendingBackgroundTranscriptionPostID"

    private static func handle(_ task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        // Actual transcription runs in-app when user opens TranscriptionView;
        // this task nudges completion when iOS grants background time.
        task.setTaskCompleted(success: true)
    }
}

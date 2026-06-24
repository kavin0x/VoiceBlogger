import ActivityKit
import Foundation

@MainActor
final class LiveActivityCoordinator {
    private var recordingActivity: Activity<VoiceBloggerActivityAttributes>?
    private var downloadActivity: Activity<VoiceBloggerActivityAttributes>?

    func startRecording(startedAt: Date = .now) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Recording",
            detail: "Voice Blogger",
            progress: nil,
            startedAt: startedAt,
            symbolName: "mic.fill"
        )
        startOrUpdate(kind: .recording, state: state, relevanceScore: 100)
    }

    func endRecording() {
        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Recording Saved",
            detail: "Ready to transcribe",
            progress: nil,
            startedAt: nil,
            symbolName: "checkmark.circle.fill"
        )
        end(kind: .recording, state: state)
    }

    func startDownload(progress: Double, detail: String) {
        updateDownload(progress: progress, detail: detail)
    }

    func updateDownload(progress: Double, detail: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Downloading Models",
            detail: detail,
            progress: min(max(progress, 0), 1),
            startedAt: nil,
            symbolName: "arrow.down.circle.fill"
        )
        startOrUpdate(kind: .downloading, state: state, relevanceScore: 80)
    }

    func endDownload(isComplete: Bool) {
        let state = VoiceBloggerActivityAttributes.ContentState(
            title: isComplete ? "Models Ready" : "Download Paused",
            detail: isComplete ? "Voice Blogger works offline" : "Open the app to resume",
            progress: isComplete ? 1 : nil,
            startedAt: nil,
            symbolName: isComplete ? "checkmark.circle.fill" : "pause.circle.fill"
        )
        end(kind: .downloading, state: state)
    }

    private func startOrUpdate(
        kind: VoiceBloggerActivityAttributes.ActivityKind,
        state: VoiceBloggerActivityAttributes.ContentState,
        relevanceScore: Double
    ) {
        if let activity = activity(for: kind) {
            update(activity, state: state, relevanceScore: relevanceScore)
            return
        }

        let attributes = VoiceBloggerActivityAttributes(kind: kind)
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: kind),
            relevanceScore: relevanceScore
        )

        do {
            let activity = try Activity.request(attributes: attributes, content: content)
            setActivity(activity, for: kind)
        } catch {
            // Live Activities are optional UI. Ignore request failures so recording/downloads continue.
        }
    }

    private func update(
        _ activity: Activity<VoiceBloggerActivityAttributes>,
        state: VoiceBloggerActivityAttributes.ContentState,
        relevanceScore: Double
    ) {
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: activity.attributes.kind),
            relevanceScore: relevanceScore
        )

        Task {
            await activity.update(content)
        }
    }

    private func end(
        kind: VoiceBloggerActivityAttributes.ActivityKind,
        state: VoiceBloggerActivityAttributes.ContentState
    ) {
        guard let activity = activity(for: kind) else { return }
        clearActivity(for: kind)

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private func activity(for kind: VoiceBloggerActivityAttributes.ActivityKind) -> Activity<VoiceBloggerActivityAttributes>? {
        if let cached = cachedActivity(for: kind) {
            return cached
        }

        let restored = Activity<VoiceBloggerActivityAttributes>.activities.first { $0.attributes.kind == kind }
        setActivity(restored, for: kind)
        return restored
    }

    private func cachedActivity(for kind: VoiceBloggerActivityAttributes.ActivityKind) -> Activity<VoiceBloggerActivityAttributes>? {
        switch kind {
        case .recording:
            recordingActivity
        case .downloading:
            downloadActivity
        }
    }

    private func setActivity(_ activity: Activity<VoiceBloggerActivityAttributes>?, for kind: VoiceBloggerActivityAttributes.ActivityKind) {
        switch kind {
        case .recording:
            recordingActivity = activity
        case .downloading:
            downloadActivity = activity
        }
    }

    private func clearActivity(for kind: VoiceBloggerActivityAttributes.ActivityKind) {
        setActivity(nil, for: kind)
    }

    private func staleDate(for kind: VoiceBloggerActivityAttributes.ActivityKind) -> Date? {
        switch kind {
        case .recording:
            return Date(timeIntervalSinceNow: 12 * 60 * 60)
        case .downloading:
            return Date(timeIntervalSinceNow: 15 * 60)
        }
    }
}

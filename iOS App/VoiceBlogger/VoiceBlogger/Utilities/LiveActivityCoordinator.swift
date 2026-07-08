#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

@MainActor
final class LiveActivityCoordinator {
#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
    private var recordingActivity: Activity<VoiceBloggerActivityAttributes>?
    private var downloadActivity: Activity<VoiceBloggerActivityAttributes>?
    /// Bumped when recording ends so in-flight `update` tasks cannot revive the activity.
    private var recordingUpdateGeneration = 0
    private var isRecordingActivityActive = false
#endif

    func startRecording(startedAt: Date = .now) {
#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        isRecordingActivityActive = true
        recordingUpdateGeneration += 1

        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Recording",
            detail: "Voice Blogger",
            progress: nil,
            startedAt: startedAt,
            symbolName: "mic.fill",
            wordCount: 0
        )
        startOrUpdate(kind: .recording, state: state, relevanceScore: 100)
#endif
    }

    func updateRecordingWordCount(_ count: Int, startedAt: Date?) {
#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        guard isRecordingActivityActive, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let detail = count > 0 ? "\(count) words transcribed" : "Voice Blogger"
        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Recording",
            detail: detail,
            progress: nil,
            startedAt: startedAt,
            symbolName: "mic.fill",
            wordCount: count
        )
        startOrUpdate(kind: .recording, state: state, relevanceScore: 100)
#endif
    }

    func endRecording() {
#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        isRecordingActivityActive = false
        recordingUpdateGeneration += 1

        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Recording Saved",
            detail: "Ready to transcribe",
            progress: nil,
            startedAt: nil,
            symbolName: "checkmark.circle.fill",
            wordCount: nil
        )
        end(kind: .recording, state: state)
#endif
    }

    func startDownload(progress: Double, detail: String) {
        updateDownload(progress: progress, detail: detail)
    }

    func updateDownload(progress: Double, detail: String) {
#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = VoiceBloggerActivityAttributes.ContentState(
            title: "Downloading Models",
            detail: detail,
            progress: min(max(progress, 0), 1),
            startedAt: nil,
            symbolName: "arrow.down.circle.fill",
            wordCount: nil
        )
        startOrUpdate(kind: .downloading, state: state, relevanceScore: 80)
#endif
    }

    func endDownload(isComplete: Bool) {
#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        let state = VoiceBloggerActivityAttributes.ContentState(
            title: isComplete ? "Models Ready" : "Download Paused",
            detail: isComplete ? "Voice Blogger works offline" : "Open the app to resume",
            progress: isComplete ? 1 : nil,
            startedAt: nil,
            symbolName: isComplete ? "checkmark.circle.fill" : "pause.circle",
            wordCount: nil
        )
        end(kind: .downloading, state: state)
#endif
    }

#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
    private func startOrUpdate(
        kind: VoiceBloggerActivityAttributes.ActivityKind,
        state: VoiceBloggerActivityAttributes.ContentState,
        relevanceScore: Double
    ) {
        if kind == .recording, !isRecordingActivityActive { return }

        if let activity = activity(for: kind) {
            update(activity, state: state, relevanceScore: relevanceScore, generation: recordingUpdateGeneration)
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
        relevanceScore: Double,
        generation: Int
    ) {
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: activity.attributes.kind),
            relevanceScore: relevanceScore
        )

        Task {
            if activity.attributes.kind == .recording {
                guard generation == recordingUpdateGeneration else { return }
            }
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
#endif
}

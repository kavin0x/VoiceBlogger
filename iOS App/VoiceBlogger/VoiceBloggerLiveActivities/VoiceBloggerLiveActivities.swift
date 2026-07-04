import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VoiceBloggerLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        VoiceBloggerLiveActivityWidget()
        StartRecordingControl()
        StopRecordingControl()
    }
}

struct VoiceBloggerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceBloggerActivityAttributes.self) { context in
            VoiceBloggerLiveActivityContent(context: context)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                compactLeadingStatus(context: context)
            } compactTrailing: {
                compactTrailingStatus(context: context)
            } minimal: {
                minimalStatus(context: context)
            }
            .widgetURL(URL(string: "voiceblogger://activity/\(context.attributes.kind.rawValue)"))
            .keylineTint(tint(for: context.attributes.kind))
        }
    }

    // MARK: - Expanded

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        HStack(spacing: 8) {
            RecordingPulse(color: tint(for: context.attributes.kind), isRecording: context.attributes.kind == .recording)
            VStack(alignment: .leading, spacing: 1) {
                Text(context.state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Voice Blogger")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        switch context.attributes.kind {
        case .recording:
            VStack(alignment: .trailing, spacing: 1) {
                recordingTimer(context: context)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                Text("elapsed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .downloading:
            if let progress = context.state.progress {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                    Text("downloaded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        switch context.attributes.kind {
        case .recording:
            VStack(alignment: .leading, spacing: 4) {
                if let count = context.state.wordCount, count > 0 {
                    Text("\(count) words")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        case .downloading:
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = context.state.progress {
                    ProgressView(value: progress)
                        .tint(tint(for: context.attributes.kind))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Compact

    @ViewBuilder
    private func compactLeadingStatus(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        switch context.attributes.kind {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(tint(for: context.attributes.kind))
                .font(.caption)
        case .downloading:
            Image(systemName: context.state.symbolName)
                .foregroundStyle(tint(for: context.attributes.kind))
        }
    }

    @ViewBuilder
    private func compactTrailingStatus(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        switch context.attributes.kind {
        case .recording:
            recordingTimer(context: context)
                .font(.caption2.monospacedDigit())
        case .downloading:
            if let progress = context.state.progress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.monospacedDigit())
            }
        }
    }

    // MARK: - Minimal

    @ViewBuilder
    private func minimalStatus(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        switch context.attributes.kind {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(tint(for: context.attributes.kind))
                .font(.system(size: 9))
        case .downloading:
            Image(systemName: context.state.symbolName)
                .foregroundStyle(tint(for: context.attributes.kind))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func recordingTimer(context: ActivityViewContext<VoiceBloggerActivityAttributes>) -> some View {
        if let startedAt = context.state.startedAt {
            Text(startedAt, style: .timer)
        } else {
            Text("0:00")
        }
    }

    private func tint(for kind: VoiceBloggerActivityAttributes.ActivityKind) -> Color {
        switch kind {
        case .recording: return .red
        case .downloading: return .blue
        }
    }
}

// MARK: - Lock screen / notification banner view

private struct VoiceBloggerLiveActivityContent: View {
    let context: ActivityViewContext<VoiceBloggerActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            RecordingPulse(color: tint, isRecording: context.attributes.kind == .recording)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.state.title)
                        .font(.headline)
                    Spacer()
                    statusText
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if context.attributes.kind == .downloading, let progress = context.state.progress {
                    ProgressView(value: progress)
                        .tint(tint)
                        .padding(.top, 2)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusText: some View {
        switch context.attributes.kind {
        case .recording:
            if let startedAt = context.state.startedAt {
                Text(startedAt, style: .timer)
            }
        case .downloading:
            if let progress = context.state.progress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }

    private var tint: Color {
        switch context.attributes.kind {
        case .recording: return .red
        case .downloading: return .blue
        }
    }
}

// MARK: - Animated recording indicator

private struct RecordingPulse: View {
    let color: Color
    let isRecording: Bool

    @State private var pulsing = false

    var body: some View {
        ZStack {
            if isRecording {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulsing ? 1.4 : 1.0)
                    .opacity(pulsing ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: pulsing
                    )
            }
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
            Image(systemName: isRecording ? "mic.fill" : "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
        .onAppear { pulsing = isRecording }
    }
}

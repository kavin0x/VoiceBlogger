import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VoiceBloggerLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        VoiceBloggerLiveActivityWidget()
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
            ActivityWaveformView(
                levels: context.state.audioLevels.isEmpty ? expandedRecordingLevels : context.state.audioLevels,
                color: tint(for: context.attributes.kind)
            )
            .frame(height: 36)
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
            ActivityWaveformView(
                levels: context.state.audioLevels.isEmpty ? compactRecordingLevels : context.state.audioLevels,
                color: tint(for: context.attributes.kind),
                spacing: 1
            )
            .frame(width: 24, height: 18)
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
            ActivityWaveformView(
                levels: context.state.audioLevels.isEmpty ? minimalRecordingLevels : context.state.audioLevels,
                color: tint(for: context.attributes.kind),
                spacing: 1
            )
            .frame(width: 18, height: 18)
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

    private var expandedRecordingLevels: [Float] {
        [-44, -26, -37, -18, -31, -12, -29, -22, -8, -34, -16, -27, -20, -35, -14, -24, -40, -19, -30, -11, -28, -23, -36, -15]
    }

    private var compactRecordingLevels: [Float] {
        [-34, -16, -27, -10, -24, -18, -31]
    }

    private var minimalRecordingLevels: [Float] {
        [-34, -18, -10, -25]
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

                switch context.attributes.kind {
                case .recording:
                    ActivityWaveformView(
                        levels: context.state.audioLevels.isEmpty ? recordingLevels : context.state.audioLevels,
                        color: tint
                    )
                    .frame(height: 40)
                    .padding(.top, 2)
                case .downloading:
                    if let progress = context.state.progress {
                        ProgressView(value: progress)
                            .tint(tint)
                    }
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

    private var recordingLevels: [Float] {
        [-42, -24, -35, -17, -29, -12, -26, -21, -9, -32, -15, -25, -19, -33, -13, -23, -38, -18, -28, -10, -27, -22, -34, -14, -31, -20, -39, -16]
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

// MARK: - Waveform canvas

private struct ActivityWaveformView: View {
    let levels: [Float]
    var color: Color
    var spacing: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }

            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = max(2, (size.width - totalSpacing) / CGFloat(count))
            let minHeight: CGFloat = min(4, size.height)

            for i in 0..<count {
                let clamped = Double(max(-60, min(0, levels[i])))
                let normalized = CGFloat((clamped + 60.0) / 60.0)
                let barHeight = minHeight + normalized * (size.height - minHeight)
                let x = CGFloat(i) * (barWidth + spacing)
                let y = (size.height - barHeight) / 2
                let path = Path(
                    roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                    cornerRadius: min(2, barWidth / 2)
                )
                context.fill(path, with: .color(color))
            }
        }
        .accessibilityLabel("Recording waveform")
    }
}

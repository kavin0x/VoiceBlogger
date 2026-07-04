import SwiftUI

struct ModelDownloadView: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(AppState.self) var appState
    @State private var selectedQuality = ModelQualityLevel.recommended
    @State private var hasChosenQuality = ModelQualityLevel.current != ModelQualityLevel.recommended
        || UserDefaults.standard.bool(forKey: "whisperModelReady_v4")

    private var quality: ModelQualityLevel { selectedQuality }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Setting Up VoiceBlogger")
                    .font(.title2.bold())
                Text("AI models download once and work fully offline. Choose a quality level — you can change this before downloading starts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !hasChosenQuality && !downloadManager.isDownloading && !downloadManager.allModelsReady {
                ModelQualityPickerView(selection: $selectedQuality)
                    .padding(.horizontal)
            }

            VStack(spacing: 20) {
                DownloadRowView(
                    icon: "waveform",
                    title: "Speech Recognition",
                    subtitle: "90+ languages · \(quality.whisperDownloadSizeLabel) · resumable",
                    progress: downloadManager.whisperProgress,
                    isReady: downloadManager.isWhisperReady
                )
                DownloadRowView(
                    icon: "text.bubble.fill",
                    title: "Writing Assistant",
                    subtitle: "\(quality.llmDownloadSizeLabel) · resumable",
                    progress: downloadManager.llmProgress,
                    isReady: downloadManager.isLLMReady
                )
            }
            .padding(.horizontal)

            if let error = downloadManager.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)

                Button("Retry") {
                    Task { await downloadManager.downloadAll() }
                }
                .buttonStyle(.borderedProminent)
            } else if downloadManager.allModelsReady {
                VStack(spacing: 12) {
                    Label("All models are ready", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)

                    Button("Continue") {
                        appState.navigateTo(.recording)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if downloadManager.isDownloading {
                ProgressView("")
            } else {
                Button("Download AI Models") {
                    ModelQualityLevel.select(selectedQuality, forNewInstall: !hasChosenQuality)
                    hasChosenQuality = true
                    Task { await downloadManager.downloadAll() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: 560)
        .onAppear {
            selectedQuality = ModelQualityLevel.current
            if downloadManager.allModelsReady {
                appState.navigateTo(.recording)
                return
            }
            hasChosenQuality = UserDefaults.standard.bool(forKey: "whisperModelReady_v4")
            downloadManager.continuePendingDownloadIfNeeded()
        }
        .onChange(of: downloadManager.allModelsReady) { _, ready in
            guard ready else { return }
            ModelQualityLevel.lockExistingInstall(to: ModelQualityLevel.current)
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                appState.navigateTo(.recording)
            }
        }
    }
}

private struct DownloadRowView: View {
    let icon: String
    let title: String
    let subtitle: String
    let progress: Double
    let isReady: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if isReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    } else if progress >= 0.95 {
                        Text("Loading model…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: isReady ? 1.0 : progress)
                    .tint(isReady ? .green : .blue)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

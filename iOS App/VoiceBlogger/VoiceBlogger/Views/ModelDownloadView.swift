import SwiftUI

struct ModelDownloadView: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(AppState.self) var appState

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
                Text("Downloading AI models (~1.5 GB total).\nAn internet connection is required. After this one-time setup, the app works fully offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 20) {
                DownloadRowView(
                    icon: "waveform",
                    title: "Advanced Speech Recognition",
                    subtitle: "~800 MB (Supports up to 90+ languages)",
                    progress: downloadManager.whisperProgress,
                    isReady: downloadManager.isWhisperReady
                )
                DownloadRowView(
                    icon: "text.bubble.fill",
                    title: "Blog Generator",
                    subtitle: "~700 MB",
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
                ProgressView("Downloading…")
            } else if !downloadManager.allModelsReady {
                Button("Download Models") {
                    Task { await downloadManager.downloadAll() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            if !downloadManager.allModelsReady && !downloadManager.isDownloading {
                Task { await downloadManager.downloadAll() }
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
                    } else {
                        Text("\(Int(progress * 100))%")
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

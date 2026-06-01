import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecordingView: View {
    @Environment(AppState.self) var appState
    @Environment(AudioRecorder.self) var recorder
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var showPermissionAlert = false
    @State private var showFilePicker = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // Waveform
                WaveformView(
                    levels: recorder.audioLevels,
                    color: recorder.isRecording ? .red : .blue.opacity(0.3)
                )
                .frame(height: 64)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.05), value: recorder.audioLevels)

                // Duration
                if recorder.isRecording {
                    Text(formatDuration(recorder.duration))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Record button
                Button {
                    if recorder.isRecording {
                        stopAndTranscribe()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(recorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(duration: 0.3), value: recorder.isRecording)

                Text(recorder.isRecording ? "Tap to stop" : "Tap to record")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !recorder.isRecording {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Upload Recording", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .navigationTitle("VoiceBlogger")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appState.navigateTo(.history)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Reset & Re-download Models", systemImage: "arrow.trianglehead.2.clockwise", role: .destructive) {
                            showResetConfirm = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .confirmationDialog(
                "Reset Models?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset & Re-download", role: .destructive) {
                    downloadManager.resetDownloads()
                    appState.navigateTo(.modelDownload)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all downloaded AI models and re-download them (~1.5 GB). Use this if a model fails to load.")
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importAudioFile(from: url)
                }
            }
            .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("VoiceBlogger needs microphone access to record audio. Please enable it in Settings.")
            }
        }
    }

    private func startRecording() {
        Task {
            if recorder.permissionDenied {
                showPermissionAlert = true
                return
            }
            do {
                try await recorder.startRecording()
            } catch {
                appState.showError("Recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopAndTranscribe() {
        guard let audioURL = recorder.stopRecording() else { return }
        let post = BlogPost(
            audioFilename: audioURL.lastPathComponent,
            duration: recorder.duration,
            transcriptionState: .untranscribed
        )
        modelContext.insert(post)
        try? modelContext.save()
        appState.navigateTo(.transcribing(post: post))
    }

    private func importAudioFile(from url: URL) {
        Task {
            do {
                let recordingsDir = URL.recordingsDirectory
                try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                let filename = UUID().uuidString + "." + url.pathExtension
                let destURL = recordingsDir.appendingPathComponent(filename)
                guard url.startAccessingSecurityScopedResource() else {
                    appState.showError("Could not access the selected file.")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: url, to: destURL)
                let post = BlogPost(audioFilename: filename, transcriptionState: .untranscribed)
                modelContext.insert(post)
                try? modelContext.save()
                appState.navigateTo(.transcribing(post: post))
            } catch {
                appState.showError("Failed to import audio: \(error.localizedDescription)")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

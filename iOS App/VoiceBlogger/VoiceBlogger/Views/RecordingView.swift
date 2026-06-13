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
    @State private var showAbout = false

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
                .accessibilityHidden(true)

                // Duration
                if recorder.isRecording {
                    Text(formatDuration(recorder.duration))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Permission denied banner
                if recorder.permissionDenied {
                    VStack(spacing: 10) {
                        Label("Microphone access is required to record.", systemImage: "mic.slash.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal, 32)
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
                .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
                .scaleEffect(recorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(duration: 0.3), value: recorder.isRecording)
                .disabled(recorder.permissionDenied)
                .opacity(recorder.permissionDenied ? 0.4 : 1.0)

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
            .navigationTitle("Voice Blogger")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appState.navigateTo(.history)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("About", systemImage: "info.circle") {
                            showAbout = true
                        }
                        Divider()
                        Button("Reset & Re-download Models", systemImage: "arrow.trianglehead.2.clockwise", role: .destructive) {
                            showResetConfirm = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
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
            .sheet(isPresented: $showAbout) {
                AboutView()
                    .presentationDetents([.medium])
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
                // Permission denied during the request (first tap after denial)
                if recorder.permissionDenied {
                    showPermissionAlert = true
                }
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
        guard url.startAccessingSecurityScopedResource() else {
            appState.showError("Could not access the selected file.")
            return
        }
        let recordingsDir = URL.recordingsDirectory
        Task.detached {
            do {
                try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                let filename = UUID().uuidString + "." + url.pathExtension
                let destURL = recordingsDir.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: url, to: destURL)
                url.stopAccessingSecurityScopedResource()
                await MainActor.run {
                    let post = BlogPost(audioFilename: filename, transcriptionState: .untranscribed)
                    modelContext.insert(post)
                    try? modelContext.save()
                    appState.navigateTo(.transcribing(post: post))
                }
            } catch {
                url.stopAccessingSecurityScopedResource()
                await MainActor.run {
                    appState.showError("Failed to import audio: \(error.localizedDescription)")
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

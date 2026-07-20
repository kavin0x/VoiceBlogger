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
    @State private var recordPulse = false

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
                            .shadow(
                                color: (recorder.isRecording ? Color.red : Color.blue)
                                    .opacity(recordPulse ? 0.55 : 0.15),
                                radius: recordPulse ? 22 : 6
                            )
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
                .onChange(of: recorder.isRecording) { _, isRecording in
                    withAnimation(
                        isRecording
                            ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.3)
                    ) {
                        recordPulse = isRecording
                    }
                }

                Text(recorder.isRecording ? "Tap to stop" : "Tap to record")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Live transcript display during recording
                if recorder.isRecording && !recorder.liveTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                        ScrollView {
                            Text(recorder.liveTranscript)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(maxHeight: 200)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    }
                    .transition(.opacity)
                }

                if !recorder.isRecording {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Upload Recording", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer()
            }
            .frame(maxWidth: 560)
            .navigationTitle("Voice Blogger")
            .navigationBarTitleDisplayMode(.large)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importAudioFile(from: url)
                }
            }
            .onAppear {
                Task {
                    await downloadManager.warmWhisper()
                    if recorder.isRecording, let kit = downloadManager.whisperKit {
                        recorder.attachWhisperKit(kit)
                    }
                }
            }
            .onChange(of: downloadManager.hasLoadedWhisperKit) { _, _ in
                if recorder.isRecording {
                    recorder.attachWhisperKit(downloadManager.whisperKit)
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
                try await downloadManager.ensureWhisperWarm()
                try await recorder.startRecording(whisperKit: downloadManager.whisperKit)
                HapticFeedback.recordToggle()
                // Attach late if warm completes after recording started
                if downloadManager.whisperKit != nil {
                    recorder.attachWhisperKit(downloadManager.whisperKit)
                }
                // Permission denied during the request (first tap after denial)
                if recorder.permissionDenied {
                    showPermissionAlert = true
                }
            } catch {
                appState.showError("Recording failed: \(error.localizedDescription)")
                if !downloadManager.isWhisperReady {
                    appState.navigateTo(.modelDownload)
                }
            }
        }
    }

    private func stopAndTranscribe() {
        guard let audioURL = recorder.stopRecording() else { return }
        HapticFeedback.recordToggle()
        let post = BlogPost(
            audioFilename: audioURL.lastPathComponent,
            duration: recorder.duration,
            transcriptionState: .untranscribed
        )
        // Pre-populate with live transcript if background transcription ran during recording
        if !recorder.liveTranscript.isEmpty {
            post.transcript = recorder.liveTranscript
            post.transcriptionState = .inProgress  // tail chunk still finalizing
        }
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

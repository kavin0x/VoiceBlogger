import SwiftUI

struct RecordingView: View {
    @Environment(AppState.self) var appState
    @Environment(AudioRecorder.self) var recorder

    @State private var showPermissionAlert = false

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
        appState.navigateTo(.transcribing(audioURL: audioURL))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

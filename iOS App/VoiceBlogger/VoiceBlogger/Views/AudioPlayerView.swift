import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let audioURL: URL
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackError: String?
    @State private var timeTimer: Timer?

    var body: some View {
        VStack(spacing: 8) {
            if let playbackError {
                Text(playbackError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .disabled(audioPlayer == nil)

                Slider(
                    value: Binding(
                        get: { duration > 0 ? currentTime / duration : 0 },
                        set: { newValue in
                            let target = newValue * duration
                            currentTime = target
                            audioPlayer?.currentTime = target
                        }
                    )
                )
                .disabled(audioPlayer == nil)

                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    private func setupPlayer() {
        do {
            try AudioSessionManager.activatePlayback()
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            audioPlayer = player
            duration = player.duration
            playbackError = nil
            startTimeUpdates()
        } catch {
            audioPlayer = nil
            playbackError = "Could not load audio for playback."
        }
    }

    private func teardownPlayer() {
        timeTimer?.invalidate()
        timeTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func startTimeUpdates() {
        timeTimer?.invalidate()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let player = audioPlayer else { return }
            currentTime = player.currentTime
            isPlaying = player.isPlaying
            if !player.isPlaying, player.currentTime >= player.duration - 0.05, player.duration > 0 {
                player.currentTime = 0
                currentTime = 0
            }
        }
    }

    private func togglePlayback() {
        guard let audioPlayer else { return }
        do {
            try AudioSessionManager.activatePlayback()
            if audioPlayer.isPlaying {
                audioPlayer.pause()
            } else {
                if audioPlayer.currentTime >= audioPlayer.duration - 0.05 {
                    audioPlayer.currentTime = 0
                }
                guard audioPlayer.play() else {
                    playbackError = "Playback could not start."
                    return
                }
            }
            isPlaying = audioPlayer.isPlaying
            playbackError = nil
        } catch {
            playbackError = "Audio output is unavailable."
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

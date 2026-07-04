import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let audioURL: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Slider(
                    value: Binding(
                        get: { duration > 0 ? currentTime / duration : 0 },
                        set: { newValue in
                            let target = newValue * duration
                            currentTime = target
                            player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                        }
                    )
                )

                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    private func setupPlayer() {
        let item = AVPlayerItem(url: audioURL)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer

        Task {
            if let loaded = try? await item.asset.load(.duration) {
                await MainActor.run {
                    duration = loaded.seconds.isFinite ? loaded.seconds : 0
                }
            }
        }

        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentTime = time.seconds
            isPlaying = avPlayer.rate > 0
        }
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = player.rate > 0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

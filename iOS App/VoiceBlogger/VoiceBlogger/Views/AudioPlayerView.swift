import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let audioURL: URL
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackError: String?
    @State private var statusMessage: String?
    @State private var timeTimer: Timer?
    @State private var downloadTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            if let playbackError {
                Text(playbackError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        switch RecordingFileAccess.readiness(at: audioURL) {
        case .downloading:
            audioPlayer = nil
            playbackError = nil
            statusMessage = "Downloading recording from iCloud…"
            observeDownload()
            return
        case .missing:
            audioPlayer = nil
            statusMessage = nil
            playbackError = RecordingReadiness.missing.unavailableMessage
            return
        case .ready:
            statusMessage = nil
        }

        loadTask?.cancel()
        loadTask = Task { await loadReadyPlayer() }
    }

    private func loadReadyPlayer() async {
        do {
            let player = try await AudioSessionManager.makePreparedPlayer(for: audioURL)
            guard !Task.isCancelled else { return }
            audioPlayer = player
            duration = player.duration
            playbackError = nil
            startTimeUpdates()
        } catch {
            guard !Task.isCancelled else { return }
            audioPlayer = nil
            playbackError = "Could not load audio for playback."
        }
    }

    private func observeDownload() {
        downloadTask?.cancel()
        downloadTask = Task {
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if RecordingFileAccess.readiness(at: audioURL) == .ready {
                    await MainActor.run { setupPlayer() }
                    return
                }
            }
            await MainActor.run {
                statusMessage = nil
                playbackError = RecordingReadiness.downloading.unavailableMessage
            }
        }
    }

    private func teardownPlayer() {
        downloadTask?.cancel()
        downloadTask = nil
        loadTask?.cancel()
        loadTask = nil
        playbackTask?.cancel()
        playbackTask = nil
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
        guard let captured = audioPlayer else { return }
        playbackTask?.cancel()
        playbackTask = Task {
            do {
                try await AudioSessionManager.activatePlayback()
                guard !Task.isCancelled else { return }
                // Activation suspends this task. Disappear can stop and drop the player first.
                guard let player = PlaybackContinuity.playerToToggle(captured: captured, current: audioPlayer) else {
                    return
                }
                if player.isPlaying {
                    player.pause()
                } else {
                    if player.currentTime >= player.duration - 0.05 {
                        player.currentTime = 0
                    }
                    guard player.play() else {
                        playbackError = "Playback could not start."
                        return
                    }
                }
                isPlaying = player.isPlaying
                playbackError = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard PlaybackContinuity.playerToToggle(captured: captured, current: audioPlayer) != nil else {
                    return
                }
                playbackError = "Audio output is unavailable."
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

enum PlaybackContinuity {
    /// The player to pause or play after an async gap, or nil when the view no longer owns it.
    static func playerToToggle<Player: AnyObject>(captured: Player, current: Player?) -> Player? {
        guard let current, current === captured else { return nil }
        return current
    }
}

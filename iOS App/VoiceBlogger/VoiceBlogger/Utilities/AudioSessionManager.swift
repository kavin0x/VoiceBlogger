import AVFoundation

nonisolated enum AudioSessionError: Error, Sendable {
    case activationFailed
    case playbackPreparationFailed
}

/// Configures `AVAudioSession` off the main thread.
///
/// Category changes and synchronous activation block while the session is already
/// active. This target isolates types to the main actor by default, so the blocking
/// calls run inside a detached task, and iOS 27 uses the async activate/deactivate API.
nonisolated enum AudioSessionManager {
    /// Set on the thread that last configured the session. Tests use this to prove
    /// activation did not run on the main thread.
    nonisolated(unsafe) static var lastWorkRanOnMainThread = false

    nonisolated static func activatePlayback() async throws {
        let sampleRate = await MainActor.run { RecordingAudioSettings.archiveSampleRate }
        try await Task.detached(priority: .userInitiated) {
            recordCallingThread()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            // Leave the output at the archive rate. A session left at a narrowband rate
            // plays the preview back through a telephone-bandwidth path.
            try session.setPreferredSampleRate(sampleRate)
            try await activate(session)
        }.value
    }

    nonisolated static func activateRecording() async throws {
        let sampleRate = await MainActor.run { RecordingAudioSettings.archiveSampleRate }
        try await Task.detached(priority: .userInitiated) {
            recordCallingThread()
            let session = AVAudioSession.sharedInstance()
            // `.spokenAudio` is a speech-intelligibility mode. It band-limits and compresses
            // the microphone, which is what made previews sound thin and distorted.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.023)
            try await activate(session)
        }.value
    }

    nonisolated static func deactivate() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if #available(iOS 27.0, *) {
                _ = try? await session.deactivate(options: .notifyOthersOnDeactivation)
            } else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }.value
    }

    /// Activates playback, then prepares an `AVAudioPlayer` off the main thread.
    /// `prepareToPlay` starts the audio hardware synchronously.
    nonisolated static func makePreparedPlayer(for url: URL) async throws -> AVAudioPlayer {
        try await activatePlayback()
        let box = try await Task.detached(priority: .userInitiated) {
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.prepareToPlay() else {
                throw AudioSessionError.playbackPreparationFailed
            }
            return UncheckedSendable(player)
        }.value
        return box.value
    }

    private nonisolated static func recordCallingThread() {
        lastWorkRanOnMainThread = Thread.isMainThread
    }

    private nonisolated static func activate(_ session: AVAudioSession) async throws {
        if #available(iOS 27.0, *) {
            let activated = try await session.activate(options: [])
            guard activated else { throw AudioSessionError.activationFailed }
        } else {
            try session.setActive(true)
        }
    }
}

private nonisolated final class UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

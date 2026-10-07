import AVFoundation

enum AudioSessionManager {
    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        // Leave the output at the archive rate. A session left at a narrowband rate
        // plays the preview back through a telephone-bandwidth path.
        try session.setPreferredSampleRate(RecordingAudioSettings.archiveSampleRate)
        try session.setActive(true)
    }

    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        // `.spokenAudio` is a speech-intelligibility mode. It band-limits and compresses
        // the microphone, which is what made previews sound thin and distorted.
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setPreferredSampleRate(RecordingAudioSettings.archiveSampleRate)
        try session.setPreferredIOBufferDuration(0.023)
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioRecorder: NSObject {
    var isRecording = false
    var duration: TimeInterval = 0
    var audioLevels: [Float] = Array(repeating: -60, count: 30)
    var currentAudioURL: URL?
    var permissionGranted = false
    var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    override init() {
        super.init()
        let status = AVAudioApplication.shared.recordPermission
        permissionGranted = status == .granted
        permissionDenied = status == .denied
    }

    func requestPermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        permissionGranted = granted
        permissionDenied = !granted
    }

    func startRecording() async throws {
        if !permissionGranted {
            await requestPermission()
        }
        guard permissionGranted else { return }

        try await Task.detached {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        }.value

        let recordingsDir = URL.recordingsDirectory
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let tempURL = recordingsDir.appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: tempURL, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true
        recorder?.record()

        currentAudioURL = tempURL
        isRecording = true
        recordingStartTime = .now
        duration = 0

        startTimers()
    }

    func stopRecording() -> URL? {
        stopTimers()
        recorder?.stop()
        isRecording = false
        audioLevels = Array(repeating: -60, count: 30)

        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
        return currentAudioURL
    }

    func discardRecording() {
        stopTimers()
        recorder?.stop()
        recorder?.deleteRecording()
        isRecording = false
        currentAudioURL = nil
        duration = 0
        audioLevels = Array(repeating: -60, count: 30)
        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
    }

    private func startTimers() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLevels() }
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let start = self?.recordingStartTime else { return }
                self?.duration = Date.now.timeIntervalSince(start)
            }
        }
    }

    private func stopTimers() {
        levelTimer?.invalidate()
        levelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateLevels() {
        recorder?.updateMeters()
        let level = recorder?.averagePower(forChannel: 0) ?? -60
        var updated = audioLevels
        updated.removeFirst()
        updated.append(level)
        audioLevels = updated
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.currentAudioURL = nil
            }
        }
    }
}

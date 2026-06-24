import Foundation
import AVFoundation
import Observation
import UIKit

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
    // Tracks an interrupted recording that hasn't been claimed by the caller
    private var hasUnclaimedInterruptedRecording = false
    @ObservationIgnored nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let liveActivity = LiveActivityCoordinator()

    override init() {
        super.init()
        let status = AVAudioApplication.shared.recordPermission
        permissionGranted = status == .granted
        permissionDenied = status == .denied
        setupNotifications()
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
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

        // Discard any leftover file from an interrupted recording
        if hasUnclaimedInterruptedRecording, let old = currentAudioURL {
            try? FileManager.default.removeItem(at: old)
            currentAudioURL = nil
            hasUnclaimedInterruptedRecording = false
        }

        let recordingsDir = URL.recordingsDirectory
        try FileManager.default.createDirectory(
            at: recordingsDir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let tempURL = recordingsDir.appendingPathComponent(UUID().uuidString + ".caf")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        try await activateRecordingSession()

        do {
            let newRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()

            guard newRecorder.record() else {
                throw AudioRecorderError.recordingCouldNotStart
            }

            recorder = newRecorder
        } catch {
            Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
            throw error
        }
        currentAudioURL = tempURL
        isRecording = true
        recordingStartTime = .now
        duration = 0

        startTimers()
        liveActivity.startRecording(startedAt: recordingStartTime ?? .now)
    }

    func stopRecording() -> URL? {
        stopTimers()
        recorder?.stop()
        isRecording = false
        hasUnclaimedInterruptedRecording = false
        audioLevels = Array(repeating: -60, count: 30)
        liveActivity.endRecording()
        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
        let url = currentAudioURL
        currentAudioURL = nil
        if let url {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
        return url
    }

    func discardRecording() {
        stopTimers()
        recorder?.stop()
        recorder?.deleteRecording()
        isRecording = false
        currentAudioURL = nil
        duration = 0
        hasUnclaimedInterruptedRecording = false
        audioLevels = Array(repeating: -60, count: 30)
        liveActivity.endRecording()
        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
    }

    private func activateRecordingSession() async throws {
        // Activate audio session on a global background queue so the synchronous
        // setCategory/setActive calls never block the main thread.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .record,
                        mode: .measurement,
                        options: [.allowBluetoothHFP]
                    )
                    try session.setPreferredSampleRate(16000)
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func setupNotifications() {
        // Handle phone calls, Siri, and other audio session interruptions
        let interruptionObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }

        // Stop level updates in the background. The recorder continues writing audio.
        // The live activity waveform freezes while backgrounded; its elapsed timer keeps running.
        let backgroundObs = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopLevelTimer()
            }
        }

        // Restart level updates when returning to foreground.
        let foregroundObs = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                self.startLevelTimer()
            }
        }

        notificationObservers = [interruptionObs, backgroundObs, foregroundObs]
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            guard isRecording else { return }
            // Screen lock can report a .began interruption; ignore it so background recording
            // continues. Only stop for real interruptions (phone calls, Siri).
            if let reasonValue = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt,
               let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue),
               reason == .appWasSuspended {
                return
            }
            stopTimers()
            recorder?.stop()
            isRecording = false
            // Mark the partial file as unclaimed so it can be cleaned up on next startRecording()
            hasUnclaimedInterruptedRecording = currentAudioURL != nil
            audioLevels = Array(repeating: -60, count: 30)
            liveActivity.endRecording()
        case .ended:
            // Don't auto-resume; let the user explicitly start a new recording
            break
        @unknown default:
            break
        }
    }

    private func startTimers() {
        startLevelTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let start = self?.recordingStartTime else { return }
                self?.duration = Date.now.timeIntervalSince(start)
            }
        }
    }

    private func stopTimers() {
        stopLevelTimer()
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLevels() }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func updateLevels() {
        recorder?.updateMeters()
        let level = recorder?.averagePower(forChannel: 0) ?? -60
        if audioLevels.isEmpty {
            audioLevels = Array(repeating: level, count: 30)
        } else {
            audioLevels.removeFirst()
            audioLevels.append(level)
        }
    }
}

private enum AudioRecorderError: LocalizedError {
    case recordingCouldNotStart

    var errorDescription: String? {
        switch self {
        case .recordingCouldNotStart:
            "The microphone could not start recording."
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.currentAudioURL = nil
                self.hasUnclaimedInterruptedRecording = false
            }
        }
    }
}

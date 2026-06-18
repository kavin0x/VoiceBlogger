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
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let tempURL = recordingsDir.appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let newRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
        newRecorder.delegate = self
        newRecorder.isMeteringEnabled = true

        // Activate audio session on a global background queue so the synchronous
        // setCategory/setActive calls never block the main thread.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        newRecorder.record()

        recorder = newRecorder
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
        hasUnclaimedInterruptedRecording = false
        audioLevels = Array(repeating: -60, count: 30)
        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
        let url = currentAudioURL
        currentAudioURL = nil
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
        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
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

        // Stop the level meter when going to background — waveform isn't visible
        let backgroundObs = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopLevelTimer() }
        }

        // Restart the level meter when returning to foreground
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
            stopTimers()
            recorder?.stop()
            isRecording = false
            // Mark the partial file as unclaimed so it can be cleaned up on next startRecording()
            hasUnclaimedInterruptedRecording = currentAudioURL != nil
            audioLevels = Array(repeating: -60, count: 30)
        case .ended:
            // Don't auto-resume; let the user explicitly start a new recording
            break
        @unknown default:
            break
        }
    }

    private func startTimers() {
        startLevelTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
        // 15 Hz is indistinguishable from 20 Hz visually but saves ~25% of main-thread
        // timer callbacks and battery during long recordings.
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
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
        audioLevels.removeFirst()
        audioLevels.append(level)
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

import Foundation
import AVFoundation
import Observation
import UIKit
import WhisperKit

@MainActor
@Observable
final class AudioRecorder: NSObject {
    var isRecording = false
    var duration: TimeInterval = 0
    var audioLevels: [Float] = Array(repeating: -60, count: 30)
    var currentAudioURL: URL?
    var permissionGranted = false
    var permissionDenied = false
    /// Grows word-by-word as background chunk transcription completes during recording.
    var liveTranscript: String = ""
    /// True while the tail chunk (audio after the last 30s boundary) is being transcribed post-stop.
    var isFinalizingTranscript: Bool = false

    private var audioEngine: AVAudioEngine?
    private var levelTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var hasUnclaimedInterruptedRecording = false

    // All nonisolated(unsafe) properties below are accessed exclusively from
    // sampleQueue (a serial DispatchQueue), except:
    // - outputAudioFile: written from tap (sampleQueue-dispatched), closed from
    //   stopRecording/interruption after the engine is stopped (no concurrent writers).
    // - latestAudioLevel: written from tap (background thread), read from level timer
    //   (main thread). Stale-by-one-tick reads are harmless for UI metering.
    @ObservationIgnored nonisolated(unsafe) private var outputAudioFile: AVAudioFile?
    @ObservationIgnored nonisolated(unsafe) private var audioConverter: AVAudioConverter?
    @ObservationIgnored nonisolated(unsafe) private var activeWhisperKit: WhisperKit?
    @ObservationIgnored nonisolated(unsafe) private var sampleAccumulator: [Float] = []
    @ObservationIgnored nonisolated(unsafe) private var chunkTaskIndex: Int = 0
    @ObservationIgnored nonisolated(unsafe) private var chainedTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var latestAudioLevel: Float = -60

    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.voiceblogger.samplequeue", qos: .userInitiated)
    @ObservationIgnored nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let liveActivity = LiveActivityCoordinator()

    // 15 seconds of 16kHz mono audio — half a Whisper window, gives faster live feedback
    nonisolated private static let chunkSampleCount = 15 * 16_000

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

    func startRecording(whisperKit: WhisperKit? = nil) async throws {
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

        // Reset live transcription state and drain any in-flight sampleQueue work
        liveTranscript = ""
        isFinalizingTranscript = false
        sampleQueue.sync {
            chainedTask?.cancel()
            chainedTask = nil
            sampleAccumulator = []
            chunkTaskIndex = 0
            activeWhisperKit = nil
        }

        let recordingsDir = URL.recordingsDirectory
        try FileManager.default.createDirectory(
            at: recordingsDir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let outputURL = recordingsDir.appendingPathComponent(UUID().uuidString + ".caf")

        // 16kHz mono float32 — WhisperKit's native format; no second conversion needed
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.recordingCouldNotStart
        }

        try await activateRecordingSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
            throw AudioRecorderError.recordingCouldNotStart
        }

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
        } catch {
            Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
            throw error
        }

        // Assign nonisolated state before engine.start() so the tap sees it immediately
        audioConverter = converter
        outputAudioFile = outputFile
        activeWhisperKit = whisperKit

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer, targetFormat: targetFormat)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            outputAudioFile = nil
            activeWhisperKit = nil
            Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }
            throw error
        }

        audioEngine = engine
        currentAudioURL = outputURL
        isRecording = true
        recordingStartTime = .now
        duration = 0

        startTimers()
        liveActivity.startRecording(startedAt: recordingStartTime ?? .now)
    }

    func stopRecording() -> URL? {
        stopTimers()
        let engine = audioEngine
        audioEngine = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        // Close the file only after the tap is removed — no more concurrent writes
        outputAudioFile = nil

        isRecording = false
        hasUnclaimedInterruptedRecording = false
        audioLevels = Array(repeating: -60, count: 30)
        latestAudioLevel = -60
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

        // Optimistically mark as finalizing if WhisperKit is active.
        // sampleQueue will clear the flag if no tail samples remain.
        if activeWhisperKit != nil {
            isFinalizingTranscript = true
        }

        sampleQueue.async { [weak self] in
            guard let self else { return }
            let remaining = self.sampleAccumulator
            self.sampleAccumulator = []
            let wk = self.activeWhisperKit
            self.activeWhisperKit = nil

            if !remaining.isEmpty, let whisperKit = wk {
                let idx = self.chunkTaskIndex
                self.chunkTaskIndex += 1
                self.enqueueTranscription(samples: remaining, index: idx, isFinal: true, whisperKit: whisperKit)
            } else {
                Task { @MainActor [weak self] in
                    self?.isFinalizingTranscript = false
                }
            }
        }

        return url
    }

    func discardRecording() {
        stopTimers()
        let engine = audioEngine
        audioEngine = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        outputAudioFile = nil

        let urlToDelete = currentAudioURL
        isRecording = false
        currentAudioURL = nil
        duration = 0
        hasUnclaimedInterruptedRecording = false
        audioLevels = Array(repeating: -60, count: 30)
        latestAudioLevel = -60
        isFinalizingTranscript = false
        liveTranscript = ""
        liveActivity.endRecording()
        Task.detached { try? AVAudioSession.sharedInstance().setActive(false) }

        if let url = urlToDelete {
            try? FileManager.default.removeItem(at: url)
        }

        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.chainedTask?.cancel()
            self.chainedTask = nil
            self.sampleAccumulator = []
            self.activeWhisperKit = nil
        }
    }

    // MARK: - Tap Processing

    nonisolated private func processTapBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter = audioConverter else { return }

        let inputFormat = buffer.format
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount)
        else { return }

        var inputConsumed = false
        var conversionError: NSError?
        converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return buffer
        }
        guard conversionError == nil, convertedBuffer.frameLength > 0 else { return }

        try? outputAudioFile?.write(from: convertedBuffer)

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let frameCount = Int(convertedBuffer.frameLength)
        let newSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // RMS -> dBFS for the waveform meter
        let sumSquares = newSamples.reduce(0.0 as Float) { $0 + $1 * $1 }
        let rms = sqrt(sumSquares / Float(frameCount))
        latestAudioLevel = rms > 0 ? max(20 * log10(rms), -60) : -65

        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.sampleAccumulator.append(contentsOf: newSamples)

            // Fire a transcription task for each complete 15s window
            while self.sampleAccumulator.count >= Self.chunkSampleCount {
                guard let wk = self.activeWhisperKit else {
                    // WhisperKit not available — drain the window and skip
                    self.sampleAccumulator = Array(self.sampleAccumulator.dropFirst(Self.chunkSampleCount))
                    continue
                }
                let chunk = Array(self.sampleAccumulator.prefix(Self.chunkSampleCount))
                self.sampleAccumulator = Array(self.sampleAccumulator.dropFirst(Self.chunkSampleCount))
                let idx = self.chunkTaskIndex
                self.chunkTaskIndex += 1
                self.enqueueTranscription(samples: chunk, index: idx, isFinal: false, whisperKit: wk)
            }
        }
    }

    // MARK: - Live Transcription

    // Must be called from sampleQueue so chainedTask reads/writes are serialized.
    nonisolated private func enqueueTranscription(
        samples: [Float],
        index: Int,
        isFinal: Bool,
        whisperKit: WhisperKit
    ) {
        let previous = chainedTask
        chainedTask = Task {
            // Serial chain: each chunk waits for the previous before starting
            await previous?.value
            guard !Task.isCancelled else {
                if isFinal {
                    await MainActor.run { [weak self] in self?.isFinalizingTranscript = false }
                }
                return
            }
            let text = await Self.transcribeChunk(samples, whisperKit: whisperKit)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !text.isEmpty {
                    if !self.liveTranscript.isEmpty { self.liveTranscript += " " }
                    self.liveTranscript += text
                }
                if isFinal {
                    self.isFinalizingTranscript = false
                }
            }
        }
    }

    nonisolated private static func transcribeChunk(_ samples: [Float], whisperKit: WhisperKit) async -> String {
        let suppressTokens = TranscriptionService.nonSpeechAnnotationTokens(for: whisperKit.tokenizer)
        let options = DecodingOptions(
            task: .transcribe,
            language: nil,
            temperature: 0,
            usePrefillPrompt: false,
            suppressBlank: true,
            suppressTokens: suppressTokens,
            noSpeechThreshold: 0.1,
            chunkingStrategy: ChunkingStrategy.none
        )
        do {
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let rawText = results.map(\.text).joined(separator: " ")
            return TranscriptionService.filterTokens(rawText)
        } catch {
            return ""
        }
    }

    // MARK: - Audio Session

    private func activateRecordingSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .record,
                        mode: .measurement,
                        options: [.allowBluetoothHFP]
                    )
                    try session.setPreferredSampleRate(16_000)
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let interruptionObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }

        // Stop level updates when backgrounded; the engine keeps recording.
        let backgroundObs = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopLevelTimer() }
        }

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
            let engine = audioEngine
            audioEngine = nil
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            outputAudioFile = nil

            isRecording = false
            hasUnclaimedInterruptedRecording = currentAudioURL != nil
            audioLevels = Array(repeating: -60, count: 30)
            latestAudioLevel = -60
            isFinalizingTranscript = false
            liveActivity.endRecording()

            sampleQueue.async { [weak self] in
                self?.chainedTask?.cancel()
                self?.chainedTask = nil
                self?.sampleAccumulator = []
                self?.activeWhisperKit = nil
            }

        case .ended:
            // Don't auto-resume; let the user explicitly start a new recording
            break
        @unknown default:
            break
        }
    }

    // MARK: - Timers

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
        let level = latestAudioLevel
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

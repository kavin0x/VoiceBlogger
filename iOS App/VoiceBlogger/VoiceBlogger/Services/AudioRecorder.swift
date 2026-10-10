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
    /// Grows word-by-word as background chunk transcription completes during recording (preview only).
    var liveTranscript: String = ""
    /// True while the tail chunk is being transcribed post-stop.
    var isFinalizingTranscript: Bool = false
    /// True when live text is a preview; a full-file pass will refine it.
    var isLivePreview: Bool = false
    /// Called when a phone call or a failed write ends the take. Return true after a BlogPost is saved.
    var onInterruptedRecording: ((InterruptedRecordingTake) -> Bool)?
    var onRecordingWriteFailed: (() -> Void)?

    private var audioEngine: AVAudioEngine?
    private var levelTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var didFinalizeTake = false

    // All nonisolated(unsafe) properties below are accessed exclusively from
    // sampleQueue (a serial DispatchQueue), except:
    // - outputAudioFile: written from tap (sampleQueue-dispatched), closed from
    //   stopRecording/interruption after the engine is stopped (no concurrent writers).
    // - latestAudioLevel: written from tap (background thread), read from level timer
    //   (main thread). Stale-by-one-tick reads are harmless for UI metering.
    @ObservationIgnored nonisolated(unsafe) private var outputAudioFile: AVAudioFile?
    /// Downmix / rate match into the archive. Nil when the tap format already matches the file.
    @ObservationIgnored nonisolated(unsafe) private var archiveConverter: AVAudioConverter?
    /// 16 kHz mono stream for live transcription only. Never written to the archive.
    @ObservationIgnored nonisolated(unsafe) private var whisperConverter: AVAudioConverter?
    /// True only when the microphone tap is already Whisper's 16 kHz mono format.
    @ObservationIgnored nonisolated(unsafe) private var whisperPassthrough = false
    @ObservationIgnored nonisolated(unsafe) private var activeWhisperKit: WhisperKit?
    @ObservationIgnored nonisolated(unsafe) private var sampleRingBuffer: SampleRingBuffer?
    @ObservationIgnored nonisolated(unsafe) private var chunkTaskIndex: Int = 0
    @ObservationIgnored nonisolated(unsafe) private var chainedTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var latestAudioLevel: Float = -60
    @ObservationIgnored nonisolated(unsafe) private var speechGainController = SpeechGainController()
    @ObservationIgnored nonisolated(unsafe) private var vocabularyTermsForPrompt: [String] = []
    @ObservationIgnored nonisolated(unsafe) private var didReportWriteFailure = false

    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.voiceblogger.samplequeue", qos: .userInitiated)
    @ObservationIgnored nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let liveActivity: LiveActivityCoordinator

    nonisolated private static var chunkAdvanceSamples: Int {
        InferencePerformancePolicy.liveChunkAdvanceSamples
    }

    nonisolated private static var chunkOverlapSamples: Int {
        InferencePerformancePolicy.liveChunkOverlapSamples
    }

    nonisolated private static var chunkWindowSamples: Int {
        InferencePerformancePolicy.liveChunkWindowSamples
    }

    init(liveActivity: LiveActivityCoordinator? = nil) {
        // Default arguments are nonisolated, so the MainActor coordinator is created in the body.
        self.liveActivity = liveActivity ?? LiveActivityCoordinator()
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

    func startRecording(whisperKit: WhisperKit? = nil, vocabularyTerms: [String] = []) async throws {
        if !permissionGranted {
            await requestPermission()
        }
        guard permissionGranted else {
            throw AudioRecorderError.microphonePermissionDenied
        }
        updateVocabularyTerms(vocabularyTerms)
        didReportWriteFailure = false
        didFinalizeTake = false

        // Reset live transcription state and drain any in-flight sampleQueue work
        liveTranscript = ""
        isFinalizingTranscript = false
        isLivePreview = false
        sampleQueue.sync {
            chainedTask?.cancel()
            chainedTask = nil
            sampleRingBuffer = SampleRingBuffer()
            chunkTaskIndex = 0
            activeWhisperKit = nil
        }

        let recordingsDir = URL.recordingsDirectory
        try RecordingStorage.prepareDirectory(recordingsDir)

        try await activateRecordingSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        // Voice processing is the speakerphone path: narrow band, noise gate, and AGC.
        if inputNode.isVoiceProcessingEnabled {
            try? inputNode.setVoiceProcessingEnabled(false)
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Task.detached { await AudioSessionManager.deactivate() }
            throw AudioRecorderError.recordingCouldNotStart
        }

        let archiveRate = RecordingAudioSettings.archiveSampleRate(matching: inputFormat.sampleRate)
        let outputURL: URL
        let outputFile: AVAudioFile
        do {
            (outputURL, outputFile) = try RecordingAudioSettings.makeArchiveFile(
                in: recordingsDir,
                sampleRate: archiveRate
            )
            RecordingStorage.protect(outputURL)
        } catch {
            Task.detached { await AudioSessionManager.deactivate() }
            throw error
        }

        let createdArchiveConverter = Self.makeConverter(from: inputFormat, to: outputFile.processingFormat)
        if createdArchiveConverter == nil,
           !RecordingAudioSettings.formatsMatch(inputFormat, outputFile.processingFormat) {
            try? FileManager.default.removeItem(at: outputURL)
            Task.detached { await AudioSessionManager.deactivate() }
            throw AudioRecorderError.recordingCouldNotStart
        }

        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: RecordingAudioSettings.whisperSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            try? FileManager.default.removeItem(at: outputURL)
            Task.detached { await AudioSessionManager.deactivate() }
            throw AudioRecorderError.recordingCouldNotStart
        }
        let createdWhisperConverter = Self.makeConverter(from: inputFormat, to: whisperFormat)
        if createdWhisperConverter == nil, !RecordingAudioSettings.formatsMatch(inputFormat, whisperFormat) {
            try? FileManager.default.removeItem(at: outputURL)
            Task.detached { await AudioSessionManager.deactivate() }
            throw AudioRecorderError.recordingCouldNotStart
        }

        // Assign nonisolated state before engine.start() so the tap sees it immediately
        self.archiveConverter = createdArchiveConverter
        self.whisperConverter = createdWhisperConverter
        whisperPassthrough = createdWhisperConverter == nil
        outputAudioFile = outputFile
        speechGainController.reset()
        sampleQueue.sync {
            activeWhisperKit = whisperKit
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            outputAudioFile = nil
            self.archiveConverter = nil
            self.whisperConverter = nil
            whisperPassthrough = false
            sampleQueue.sync {
                activeWhisperKit = nil
            }
            try? FileManager.default.removeItem(at: outputURL)
            Task.detached { await AudioSessionManager.deactivate() }
            throw error
        }

        audioEngine = engine
        currentAudioURL = outputURL
        isRecording = true
        recordingStartTime = .now
        duration = 0
        IntentStorage.markRecordingActive()

        startTimers()
        liveActivity.startRecording(startedAt: recordingStartTime ?? .now)
    }

    func attachWhisperKit(_ whisperKit: WhisperKit?) {
        sampleQueue.sync {
            activeWhisperKit = whisperKit
        }
    }

    func stopRecording() -> URL? {
        guard !didFinalizeTake else { return nil }
        didFinalizeTake = true
        stopTimers()
        let engine = audioEngine
        audioEngine = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        // Close the file only after the tap is removed — no more concurrent writes
        outputAudioFile = nil
        archiveConverter = nil
        whisperConverter = nil
        whisperPassthrough = false

        isRecording = false
        audioLevels = Array(repeating: -60, count: 30)
        latestAudioLevel = -60
        IntentStorage.clearRecordingActive()
        liveActivity.endRecording(saved: true)
        Task.detached { await AudioSessionManager.deactivate() }

        let url = currentAudioURL
        currentAudioURL = nil

        if let url {
            RecordingStorage.protect(url)
        }

        // Read on sampleQueue. The tap mutates this flag off the main actor.
        let hadWhisper = sampleQueue.sync { activeWhisperKit != nil }
        if hadWhisper {
            isFinalizingTranscript = true
            isLivePreview = !liveTranscript.isEmpty
        }

        sampleQueue.async { [weak self] in
            guard let self else { return }
            let remaining = self.sampleRingBuffer?.drainAll() ?? []
            let wk = self.activeWhisperKit
            self.activeWhisperKit = nil
            self.sampleRingBuffer = nil

            if !remaining.isEmpty, let whisperKit = wk {
                let idx = self.chunkTaskIndex
                self.chunkTaskIndex += 1
                let terms = self.vocabularyTermsForPrompt
                self.enqueueTranscription(
                    samples: remaining,
                    index: idx,
                    isFinal: true,
                    whisperKit: whisperKit,
                    vocabularyTerms: terms
                )
            } else {
                Task { @MainActor [weak self] in
                    self?.isFinalizingTranscript = false
                }
            }
        }

        return url
    }

    func discardRecording() {
        didFinalizeTake = true
        stopTimers()
        let engine = audioEngine
        audioEngine = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        outputAudioFile = nil
        archiveConverter = nil
        whisperConverter = nil
        whisperPassthrough = false

        let urlToDelete = currentAudioURL
        isRecording = false
        currentAudioURL = nil
        duration = 0
        audioLevels = Array(repeating: -60, count: 30)
        latestAudioLevel = -60
        isFinalizingTranscript = false
        liveTranscript = ""
        isLivePreview = false
        IntentStorage.clearRecordingActive()
        liveActivity.endRecording(saved: false)
        Task.detached { await AudioSessionManager.deactivate() }

        if let url = urlToDelete {
            try? FileManager.default.removeItem(at: url)
        }

        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.chainedTask?.cancel()
            self.chainedTask = nil
            self.sampleRingBuffer = nil
            self.activeWhisperKit = nil
        }
    }

    // MARK: - Tap Processing

    nonisolated private static func makeConverter(from source: AVAudioFormat, to target: AVAudioFormat) -> AVAudioConverter? {
        guard !RecordingAudioSettings.formatsMatch(source, target) else { return nil }
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        converter.sampleRateConverterQuality = .max
        return converter
    }

    nonisolated private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        writeArchive(buffer)
        publishLevel(from: buffer)

        let whisperBuffer: AVAudioPCMBuffer?
        if let whisperConverter {
            whisperBuffer = RecordingPCMConverter.convert(buffer, using: whisperConverter)
        } else if whisperPassthrough {
            whisperBuffer = buffer
        } else {
            whisperBuffer = nil
        }
        guard let whisperBuffer,
              whisperBuffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = whisperBuffer.floatChannelData?[0] else { return }

        let frameCount = Int(whisperBuffer.frameLength)
        guard frameCount > 0 else { return }
        var newSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        var peak: Float = 0
        for sample in newSamples {
            peak = max(peak, abs(sample))
        }
        // Boost only the live transcription copy. The archive was already written
        // from the unprocessed microphone buffer so playback is not clipped.
        let gain = speechGainController.gain(forPeak: peak)
        SpeechGainController.applyGain(gain, to: &newSamples)

        sampleQueue.async { [weak self] in
            guard let self else { return }
            if self.sampleRingBuffer == nil {
                self.sampleRingBuffer = SampleRingBuffer()
            }
            self.sampleRingBuffer?.append(newSamples)

            while self.sampleRingBuffer?.count ?? 0 >= Self.chunkWindowSamples {
                guard let wk = self.activeWhisperKit else {
                    _ = self.sampleRingBuffer?.takeAdvance(count: Self.chunkAdvanceSamples)
                    continue
                }
                guard let chunk = self.sampleRingBuffer?.takeWindow(
                    window: Self.chunkWindowSamples,
                    advance: Self.chunkAdvanceSamples
                ) else { break }
                let idx = self.chunkTaskIndex
                self.chunkTaskIndex += 1
                let terms = self.vocabularyTermsForPrompt
                self.enqueueTranscription(
                    samples: chunk,
                    index: idx,
                    isFinal: false,
                    whisperKit: wk,
                    vocabularyTerms: terms
                )
            }
        }
    }

    // MARK: - Live Transcription

    // Must be called from sampleQueue so chainedTask reads/writes are serialized.
    func updateVocabularyTerms(_ terms: [String]) {
        let snapshot = terms
        sampleQueue.sync {
            vocabularyTermsForPrompt = snapshot
        }
    }

    nonisolated private func writeArchive(_ buffer: AVAudioPCMBuffer) {
        guard let outputAudioFile else { return }
        do {
            if RecordingAudioSettings.formatsMatch(buffer.format, outputAudioFile.processingFormat) {
                try outputAudioFile.write(from: buffer)
            } else if let archiveConverter,
                      let archiveBuffer = RecordingPCMConverter.convert(buffer, using: archiveConverter) {
                try outputAudioFile.write(from: archiveBuffer)
            } else {
                reportWriteFailure()
            }
        } catch {
            reportWriteFailure()
        }
    }

    nonisolated private func publishLevel(from buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sumSquares: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        latestAudioLevel = rms > 0 ? max(20 * log10(rms), -60) : -65
    }

    nonisolated private func reportWriteFailure() {
        guard !didReportWriteFailure else { return }
        didReportWriteFailure = true
        Task { @MainActor [weak self] in
            self?.finalizeOpenTake(becauseWriteFailed: true)
        }
    }

    /// Stops the engine, keeps the audio file, and asks the app to insert a history row.
    @discardableResult
    private func finalizeOpenTake(becauseWriteFailed: Bool) -> Bool {
        guard !didFinalizeTake else { return false }
        guard isRecording || currentAudioURL != nil else { return false }
        didFinalizeTake = true
        stopTimers()
        let engine = audioEngine
        audioEngine = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        outputAudioFile = nil
        archiveConverter = nil
        whisperConverter = nil
        whisperPassthrough = false

        let filename = currentAudioURL?.lastPathComponent
        let takeDuration = duration
        let transcript = liveTranscript
        isRecording = false
        currentAudioURL = nil
        audioLevels = Array(repeating: -60, count: 30)
        latestAudioLevel = -60
        isFinalizingTranscript = false
        IntentStorage.clearRecordingActive()
        Task.detached { await AudioSessionManager.deactivate() }

        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.chainedTask?.cancel()
            self.chainedTask = nil
            self.activeWhisperKit = nil
        }

        let saved: Bool
        if let filename {
            let take = InterruptedRecordingTake(
                filename: filename,
                duration: takeDuration,
                liveTranscript: transcript
            )
            saved = onInterruptedRecording?(take) ?? false
        } else {
            saved = false
        }
        liveActivity.endRecording(saved: saved)
        if becauseWriteFailed {
            onRecordingWriteFailed?()
        }
        return saved
    }

    nonisolated private func enqueueTranscription(
        samples: [Float],
        index: Int,
        isFinal: Bool,
        whisperKit: WhisperKit,
        vocabularyTerms: [String]
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
            let text = await Self.transcribeChunk(
                samples,
                whisperKit: whisperKit,
                vocabularyTerms: vocabularyTerms
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !text.isEmpty {
                    self.liveTranscript = TranscriptMergeUtility.merge(existing: self.liveTranscript, newChunk: text)
                    self.isLivePreview = true
                    // Keep live transcription running for post-stop handoff, but do not
                    // surface partial text in the Live Activity while recording.
                }
                if isFinal {
                    self.isFinalizingTranscript = false
                }
            }
        }
    }

    nonisolated private static func transcribeChunk(
        _ samples: [Float],
        whisperKit: WhisperKit,
        vocabularyTerms: [String]
    ) async -> String {
        let suppressTokens = TranscriptionService.nonSpeechAnnotationTokens(for: whisperKit.tokenizer)
        let promptTokens = TranscriptionService.musicAwarePromptTokens(
            for: whisperKit.tokenizer,
            vocabularyTerms: vocabularyTerms
        )
        let options = TranscriptionService.liveChunkDecodingOptions(
            suppressTokens: suppressTokens,
            promptTokens: promptTokens
        )
        do {
            let results = try await OffMain.run {
                try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            }
            let rawText = results.map(\.text).joined(separator: " ")
            return TranscriptionService.filterTokens(rawText)
        } catch {
            return ""
        }
    }

    // MARK: - Audio Session

    private func activateRecordingSession() async throws {
        try await AudioSessionManager.activateRecording()
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
            finalizeOpenTake(becauseWriteFailed: false)

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

    func recoverStaleRecordingActivityIfNeeded() {
        guard !isRecording, IntentStorage.consumeRecordingActive() else { return }
        // The activity outlived the process, so the take never became a library row.
        liveActivity.endRecording(saved: false)
    }
}

// MARK: - Sample ring buffer (reduces allocations in the audio hot path)

private final class SampleRingBuffer: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func append(_ samples: [Float]) {
        lock.lock()
        storage.append(contentsOf: samples)
        lock.unlock()
    }

    func takeWindow(window: Int, advance: Int) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard storage.count >= window else { return nil }
        let chunk = Array(storage.prefix(window))
        storage.removeFirst(min(advance, storage.count))
        return chunk
    }

    func takeAdvance(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let removed = min(count, storage.count)
        storage.removeFirst(removed)
        return []
    }

    func drainAll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let all = storage
        storage = []
        return all
    }
}

enum AudioRecorderError: LocalizedError {
    case recordingCouldNotStart
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .recordingCouldNotStart:
            "The microphone could not start recording."
        case .microphonePermissionDenied:
            "Microphone access is required to record. Enable it in Settings."
        }
    }
}

struct InterruptedRecordingTake: Sendable {
    let filename: String
    let duration: TimeInterval
    let liveTranscript: String
}

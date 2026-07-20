import Foundation
import WhisperKit
import CoreML
import AVFoundation

enum TranscriptionMode {
    case transcribe(language: String?)  // speech -> text in original language
    case translate                      // speech -> English (Whisper translation task)
}

enum TranscriptionProgressPhase: String, Sendable {
    case loadingAudio
    case transcribing
    case finishing
}

/// The result of a Whisper transcription pass.
struct SpeakerAnnotatedTranscript: Sendable {
    /// Cleaned flat transcript (control tokens and noise annotations removed).
    let text: String
    /// Reserved for future diarization-backed speaker labels.
    /// Pause-based turn splitting is intentionally not exposed as speaker attribution.
    let speakerAnnotatedText: String?
    /// 0 = only noise/silence detected, 1 = speech detected. Values above 1 are reserved
    /// for future diarization-backed speaker recognition.
    let detectedSpeakerCount: Int

    /// The best text to show the user: speaker-annotated when available, otherwise flat.
    var displayText: String { speakerAnnotatedText ?? text }
}

// WhisperKit is open class without Sendable; @unchecked is safe here because
// WhisperKit is only ever accessed from a single Task at a time in this service.
final class TranscriptionService: @unchecked Sendable {
    private var whisperKit: WhisperKit?

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    // Pass an existing WhisperKit instance (e.g. from ModelDownloadManager) to skip reloading from disk.
    static func make(reusing existing: WhisperKit? = nil) async throws -> TranscriptionService {
        if let existing {
            return TranscriptionService(whisperKit: existing)
        }
        // Pass modelFolder when files are on disk so WhisperKit skips all network calls.
        let localDir = localWhisperModelDirectory()
        let config = WhisperKitConfig(
            model: localDir == nil ? ModelIDs.whisper : nil,
            modelFolder: localDir?.path,
            computeOptions: whisperComputeOptions()
        )
        let kit = try await WhisperKit(config)
        return TranscriptionService(whisperKit: kit)
    }

    // Choose compute backend based on available RAM.
    // On constrained devices, ANE is still preferred for the audio encoder (fastest path)
    // but if RAM is critically low we drop to CPU-only so CoreML doesn't compete with
    // MLX's Metal allocator for the limited GPU shared memory.
    static func whisperComputeOptions() -> ModelComputeOptions {
        if hasAvailableMemory(requiredMB: 600) {
            return ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )
        }
        return ModelComputeOptions(
            audioEncoderCompute: .cpuOnly,
            textDecoderCompute: .cpuOnly
        )
    }

    private static func localWhisperModelDirectory() -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let whisperCacheDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")

        let canonical = whisperCacheDir.appendingPathComponent(ModelIDs.whisper)
        if directoryContainsFiles(canonical) { return canonical }

        guard let entries = try? fm.contentsOfDirectory(
            at: whisperCacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for entry in entries where entry.lastPathComponent != ModelIDs.whisper {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir && directoryContainsFiles(entry) { return entry }
        }
        return nil
    }

    private static func directoryContainsFiles(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in enumerator {
            let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if vals?.isRegularFile == true || vals?.isSymbolicLink == true { return true }
        }
        return false
    }

    // Explicitly unload CoreML models before releasing the WhisperKit instance.
    // WhisperKit's deinit only stops audio recording - it does NOT call unloadModels(),
    // so without this call the MLModel Metal buffers remain allocated until the OS reclaims
    // them under pressure, causing an OOM kill when the LLM then loads in the same process.
    func cleanup() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
    }

    func transcribe(
        audioURL: URL,
        mode: TranscriptionMode,
        onProgress: (@Sendable (TranscriptionProgressPhase) -> Void)? = nil,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> SpeakerAnnotatedTranscript {
        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }
        try validateAudioFile(at: audioURL)

        let suppressTokens = Self.nonSpeechAnnotationTokens(for: whisperKit.tokenizer)
        let promptTokens = Self.musicAwarePromptTokens(for: whisperKit.tokenizer)
        let options = Self.decodingOptions(
            for: mode,
            suppressTokens: suppressTokens,
            promptTokens: promptTokens,
            livePreview: false
        )

        let previousStateCallback = whisperKit.transcriptionStateCallback
        whisperKit.transcriptionStateCallback = { state in
            previousStateCallback?(state)
            switch state {
            case .convertingAudio:
                onProgress?(.loadingAudio)
            case .transcribing:
                onProgress?(.transcribing)
            case .finished:
                onProgress?(.finishing)
            }
        }
        defer { whisperKit.transcriptionStateCallback = previousStateCallback }

        let results = try await transcribeWithStallWatchdog(
            whisperKit: whisperKit,
            audioPath: audioURL.path,
            decodeOptions: options,
            onPartial: onPartial
        )
        let rawJoined = results.map { $0.text }.joined(separator: " ")
        let finalText = Self.filterTokens(rawJoined)
        // If annotation filtering removed everything (e.g. Whisper tagged the entire
        // recording as [singing] or [music] due to background noise), fall back to the
        // control-token-stripped raw text so we never silently discard real speech.
        let cleanedText: String
        if !finalText.isEmpty {
            cleanedText = finalText
        } else {
            let rawFallback = Self.stripControlTokens(rawJoined)
            guard !rawFallback.isEmpty else {
                throw TranscriptionError.emptyResult
            }
            cleanedText = rawFallback
        }

        // Count whether speech was detected without inventing speaker labels. WhisperKit's
        // segments do not identify speakers, and pause-based alternation caused false
        // attribution in transcripts and generated notes.
        let allSegments = results.flatMap { $0.segments }
        let hasSpeech = Self.containsSpeech(allSegments)
        return SpeakerAnnotatedTranscript(
            text: cleanedText,
            speakerAnnotatedText: nil,
            detectedSpeakerCount: hasSpeech ? 1 : 0
        )
    }

    private func validateAudioFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.missingAudio
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
                throw TranscriptionError.unreadableAudio
            }

            let audioFile = try AVAudioFile(forReading: url)
            guard audioFile.length > 0 else {
                throw TranscriptionError.unreadableAudio
            }
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.unreadableAudio
        }
    }

    /// Shared decode options for full-file and live-chunk transcription.
    nonisolated static func decodingOptions(
        for mode: TranscriptionMode,
        suppressTokens: [Int],
        promptTokens: [Int]? = nil,
        livePreview: Bool
    ) -> DecodingOptions {
        switch mode {
        case .transcribe(let language):
            return DecodingOptions(
                task: .transcribe,
                language: language,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                usePrefillPrompt: language != nil,
                detectLanguage: language == nil,
                withoutTimestamps: true,
                windowClipTime: 1.0,
                promptTokens: promptTokens,
                suppressBlank: livePreview,
                suppressTokens: suppressTokens,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                noSpeechThreshold: 0.45,
                chunkingStrategy: ChunkingStrategy.none
            )
        case .translate:
            return DecodingOptions(
                task: .translate,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                usePrefillPrompt: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                windowClipTime: 1.0,
                promptTokens: promptTokens,
                suppressBlank: livePreview,
                suppressTokens: suppressTokens,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                noSpeechThreshold: 0.45,
                chunkingStrategy: ChunkingStrategy.none
            )
        }
    }

    /// Live-chunk transcription uses the same quality settings as the full-file pass.
    nonisolated static func liveChunkDecodingOptions(
        suppressTokens: [Int],
        promptTokens: [Int]? = nil,
        mode: TranscriptionMode = TranscriptionSettings.transcriptionMode
    ) -> DecodingOptions {
        decodingOptions(for: mode, suppressTokens: suppressTokens, promptTokens: promptTokens, livePreview: true)
    }

    /// Condition the decoder so spoken words and lyrics are kept, while instrumental
    /// background music is less likely to be hallucinated into fake speech.
    nonisolated static func musicAwarePromptTokens(for tokenizer: (any WhisperTokenizer)?) -> [Int]? {
        guard let tokenizer else { return nil }
        let prompt = """
        Transcribe spoken words and sung lyrics accurately. \
        Ignore instrumental background music. \
        Do not invent lyrics or speech from music alone.
        """
        let encoded = tokenizer.encode(text: prompt)
        let filtered = encoded.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return filtered.isEmpty ? nil : filtered
    }

    private static let stallTimeoutSeconds: TimeInterval = 120

    private final class StallTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var lastProgressAt = ContinuousClock.now

        func bump() {
            lock.lock()
            lastProgressAt = ContinuousClock.now
            lock.unlock()
        }

        func isStalled(timeout: TimeInterval) -> Bool {
            lock.lock()
            let elapsed = ContinuousClock.now - lastProgressAt
            lock.unlock()
            return elapsed >= .seconds(timeout)
        }
    }

    private func transcribeWithStallWatchdog(
        whisperKit: WhisperKit,
        audioPath: String,
        decodeOptions: DecodingOptions,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> [TranscriptionResult] {
        let tracker = StallTracker()

        return try await withThrowingTaskGroup(of: [TranscriptionResult].self) { group in
            group.addTask {
                try await whisperKit.transcribe(
                    audioPath: audioPath,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        let filtered = Self.filterTokens(progress.text)
                        if !filtered.isEmpty {
                            tracker.bump()
                            onPartial?(filtered)
                        }
                        return true
                    }
                )
            }
            group.addTask {
                tracker.bump()
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    if tracker.isStalled(timeout: Self.stallTimeoutSeconds) {
                        throw TranscriptionError.stalled
                    }
                }
                try Task.checkCancellation()
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw TranscriptionError.stalled
            }
            group.cancelAll()
            return result
        }
    }

    nonisolated static func nonSpeechAnnotationTokens(for tokenizer: (any WhisperTokenizer)?) -> [Int] {
        guard let tokenizer else { return [] }
        // Only suppress tokens for noise/non-content events.
        // Music notes, [Music], and [Singing] are intentionally excluded so that
        // Whisper can transcribe sung audio rather than skipping those segments.
        let candidates = [
            "[Applause]", "[applause]", "(Applause)", "(applause)",
            "[Laughter]", "[laughter]", "(Laughter)", "(laughter)",
            "[Inaudible]", "[inaudible]", "(Inaudible)", "(inaudible)",
            "[Silence]", "[silence]", "(Silence)", "(silence)",
            "[Noise]", "[noise]", "(Noise)", "(noise)",
            // Common Whisper hallucinations on uncertain/silent/short audio clips
            "[Fast forward]", "[fast forward]", "(Fast forward)",
            "[Slow motion]", "[slow motion]", "(Slow motion)",
            "[Crowd cheering]", "[crowd cheering]",
            "[Cheering]", "[cheering]",
            "[Coughing]", "[coughing]",
            "[Sniffling]", "[sniffling]",
            "[Clapping]", "[clapping]",
            "[Beep]", "[beep]",
            "[Static]", "[static]"
        ]
        let tokens = candidates.compactMap { candidate -> Int? in
            let encoded = tokenizer.encode(text: candidate)
            return encoded.count == 1 ? encoded[0] : nil
        }
        return Array(Set(tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin })).sorted()
    }

    // nonisolated(unsafe): immutable after init, Sendable types - safe to read from any context.
    // (Suppresses a Swift 6 strict-concurrency warning on static properties of @unchecked Sendable classes.)
    nonisolated private static let _tokenFilterRegex = try! NSRegularExpression(pattern: "<\\|[^|>]+\\|>")
    nonisolated private static let _nonSpeechAnnotationRegex = try! NSRegularExpression(
        // Strips noise/non-content annotations and common Whisper hallucination phrases.
        // "music" and "singing" are intentionally excluded so lyric transcripts are preserved.
        // "fast forward", "slow motion", etc. are hallucinations Whisper emits when uncertain
        // about the start or end of a clip — they carry no speech content.
        pattern: #"(?i)(?:"# +
            #"\*\s*(?:applause|laughter|laughing|inaudible|silence|noise|background noise|fast forward|slow motion|crowd cheering|cheering|clapping|sniffling|coughing|beep|static|distortion)\s*\*"# +
            #"|\[\s*(?:applause|laughter|laughing|inaudible|silence|noise|background noise|fast forward|slow motion|crowd cheering|cheering|clapping|sniffling|coughing|beep|static|distortion)\s*\]"# +
            #"|\(\s*(?:applause|laughter|laughing|inaudible|silence|noise|background noise|fast forward|slow motion|crowd cheering|cheering|clapping|sniffling|coughing|beep|static|distortion)\s*\)"# +
        #")"#
    )
    nonisolated private static let _extraWhitespaceRegex = try! NSRegularExpression(pattern: #"[ \t]{2,}"#)
    // Whisper emits this literal when it detects a language mismatch (e.g. audio is non-English
    // but the decoder was primed with an English prefill token).
    nonisolated private static let _foreignLanguagePlaceholder = "[Speaking in a foreign language]"

    // Strip WhisperKit control tokens like <|startoftranscript|>, <|en|>, <|0.00|>, etc.,
    // plus non-speech placeholders emitted when Whisper chooses an annotation over speech.
    nonisolated static func filterTokens(_ text: String) -> String {
        let tokenRange = NSRange(text.startIndex..., in: text)
        let withoutTokens = _tokenFilterRegex.stringByReplacingMatches(in: text, range: tokenRange, withTemplate: "")
            .replacingOccurrences(of: _foreignLanguagePlaceholder, with: "")
        let annotationRange = NSRange(withoutTokens.startIndex..., in: withoutTokens)
        let withoutAnnotations = _nonSpeechAnnotationRegex.stringByReplacingMatches(in: withoutTokens, range: annotationRange, withTemplate: "")
        let whitespaceRange = NSRange(withoutAnnotations.startIndex..., in: withoutAnnotations)
        return _extraWhitespaceRegex.stringByReplacingMatches(in: withoutAnnotations, range: whitespaceRange, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Strips only the angle-bracket control tokens (e.g. <|startoftranscript|>, <|en|>, <|0.00|>)
    // and the foreign-language placeholder, but leaves annotation phrases like [singing] intact.
    // Used as a fallback when full filterTokens() produces an empty string so that background
    // music or singing does not cause a wholesale rejection of an otherwise valid transcript.
    nonisolated static func stripControlTokens(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let withoutTokens = _tokenFilterRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: _foreignLanguagePlaceholder, with: "")
        let wsRange = NSRange(withoutTokens.startIndex..., in: withoutTokens)
        return _extraWhitespaceRegex.stringByReplacingMatches(in: withoutTokens, range: wsRange, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Speech detection

    /// Log-probability threshold below which a segment is treated as noise/non-speech.
    /// Whisper assigns avgLogprob close to 0 for confident speech; values below -1.2 typically
    /// indicate background noise, music, or hallucinated filler rather than real words.
    nonisolated private static let noiseProbThreshold: Float = -1.2

    /// Returns true when Whisper produced at least one confident speech segment.
    nonisolated static func containsSpeech(
        _ segments: [TranscriptionSegment]
    ) -> Bool {
        segments.contains { segment in
            guard segment.avgLogprob >= noiseProbThreshold else { return false }
            let cleaned = filterTokens(segment.text)
            return !cleaned.isEmpty
        }
    }
}

enum TranscriptionError: LocalizedError {
    case notInitialized
    case missingAudio
    case unreadableAudio
    case emptyResult
    case stalled

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcription service was already cleaned up."
        case .missingAudio:
            return "Audio file not found. The recording may have been deleted."
        case .unreadableAudio:
            return "This recording could not be read. Share the audio file and try recording again."
        case .emptyResult:
            return "No speech was detected in this recording. You can retry transcription or share the audio file."
        case .stalled:
            return "Transcription stopped making progress. Retry transcription or share the audio file."
        }
    }
}

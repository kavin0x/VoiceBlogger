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
            model: localDir == nil ? kWhisperModelID : nil,
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

        let canonical = whisperCacheDir.appendingPathComponent(kWhisperModelID)
        if directoryContainsFiles(canonical) { return canonical }

        guard let entries = try? fm.contentsOfDirectory(
            at: whisperCacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for entry in entries {
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
    ) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }
        try validateAudioFile(at: audioURL)

        let suppressTokens = Self.nonSpeechAnnotationTokens(for: whisperKit.tokenizer)
        let options: DecodingOptions
        switch mode {
        case .transcribe(let language):
            // Disable prefill when language is nil so Whisper performs true auto-detection.
            // With usePrefillPrompt: true and no explicit language, WhisperKit primes the
            // decoder with the device locale (often English), causing Whisper to output
            // "[Speaking in a foreign language]" instead of transcribing multilingual audio.
            // VAD chunking skips silent segments, speeding up transcription proportionally.
            options = DecodingOptions(
                task: .transcribe,
                language: language,
                temperature: 0,
                usePrefillPrompt: language != nil,
                suppressBlank: true,
                suppressTokens: suppressTokens,
                chunkingStrategy: .vad
            )
        case .translate:
            options = DecodingOptions(
                task: .translate,
                temperature: 0,
                usePrefillPrompt: true,
                suppressBlank: true,
                suppressTokens: suppressTokens,
                chunkingStrategy: .vad
            )
        }

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

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: { progress in
                let filtered = Self.filterTokens(progress.text)
                if !filtered.isEmpty {
                    onPartial?(filtered)
                }
                return true
            }
        )
        let finalText = Self.filterTokens(results.map { $0.text }.joined(separator: " "))
        guard !finalText.isEmpty else {
            throw TranscriptionError.emptyResult
        }
        return finalText
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

    private static func nonSpeechAnnotationTokens(for tokenizer: (any WhisperTokenizer)?) -> [Int] {
        guard let tokenizer else { return [] }
        let candidates = [
            "*", " *", "♪", " ♪", "♫", " ♫", "♬", " ♬", "♩", " ♩",
            "[Music]", "[music]", "(Music)", "(music)",
            "[Singing]", "[singing]", "(Singing)", "(singing)",
            "*Singing*", " *Singing*", "*singing*", " *singing*",
            "[Applause]", "[applause]", "(Applause)", "(applause)",
            "[Laughter]", "[laughter]", "(Laughter)", "(laughter)"
        ]
        let tokens = candidates.compactMap { candidate -> Int? in
            let encoded = tokenizer.encode(text: candidate)
            return encoded.count == 1 ? encoded[0] : nil
        }
        return Array(Set(tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin })).sorted()
    }

    // nonisolated(unsafe): immutable after init, Sendable types - safe to read from any context.
    // (Suppresses a Swift 6 strict-concurrency warning on static properties of @unchecked Sendable classes.)
    private static let _tokenFilterRegex = try! NSRegularExpression(pattern: "<\\|[^|>]+\\|>")
    private static let _nonSpeechAnnotationRegex = try! NSRegularExpression(
        pattern: #"(?i)(?:\*\s*(?:singing|music|applause|laughter|laughing|inaudible|silence|noise|background noise)\s*\*|\[\s*(?:singing|music|applause|laughter|laughing|inaudible|silence|noise|background noise)\s*\]|\(\s*(?:singing|music|applause|laughter|laughing|inaudible|silence|noise|background noise)\s*\))"#
    )
    private static let _extraWhitespaceRegex = try! NSRegularExpression(pattern: #"[ \t]{2,}"#)
    // Whisper emits this literal when it detects a language mismatch (e.g. audio is non-English
    // but the decoder was primed with an English prefill token).
    private static let _foreignLanguagePlaceholder = "[Speaking in a foreign language]"

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

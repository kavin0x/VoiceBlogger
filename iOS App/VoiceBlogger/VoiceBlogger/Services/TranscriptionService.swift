import Foundation
import WhisperKit
import CoreML

enum TranscriptionMode {
    case transcribe(language: String?)  // speech → text in original language
    case translate                       // speech → English (Whisper translation task)
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
        let config = WhisperKitConfig(
            model: kWhisperModelID,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU
            )
        )
        let kit = try await WhisperKit(config)
        return TranscriptionService(whisperKit: kit)
    }

    // Release the WhisperKit instance so GPU/ANE memory is freed before LLM runs.
    func cleanup() {
        whisperKit = nil
    }

    func transcribe(
        audioURL: URL,
        mode: TranscriptionMode,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }

        let options: DecodingOptions
        switch mode {
        case .transcribe(let language):
            options = DecodingOptions(
                task: .transcribe,
                language: language,
                temperature: 0,
                usePrefillPrompt: true
            )
        case .translate:
            options = DecodingOptions(
                task: .translate,
                temperature: 0,
                usePrefillPrompt: true
            )
        }

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: { progress in
                guard let onPartial else { return true }
                let filtered = Self.filterTokens(progress.text)
                if !filtered.isEmpty {
                    onPartial(filtered)
                }
                return true
            }
        )
        return Self.filterTokens(results.map { $0.text }.joined(separator: " "))
    }

    // Strip WhisperKit control tokens like <|startoftranscript|>, <|en|>, <|0.00|>, etc.
    nonisolated private static func filterTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|>]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

enum TranscriptionError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Transcription service was already cleaned up."
        }
    }
}

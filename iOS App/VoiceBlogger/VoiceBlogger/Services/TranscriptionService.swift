import Foundation
import WhisperKit

enum TranscriptionMode {
    case transcribe(language: String?)  // speech → text in original language
    case translate                       // speech → English (Whisper translation task)
}

// WhisperKit is open class without Sendable; @unchecked is safe here because
// WhisperKit is only ever accessed from a single Task at a time in this service.
final class TranscriptionService: @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    static func make() async throws -> TranscriptionService {
        let kit = try await WhisperKit(model: kWhisperModelID)
        return TranscriptionService(whisperKit: kit)
    }

    func transcribe(audioURL: URL, mode: TranscriptionMode) async throws -> String {
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

        // Returns [TranscriptionResult] (non-optional per WhisperKit API)
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

import Foundation

enum BlogGenerationHandoff {
    static func preparedTranscript(from transcript: String) -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canGenerateBlog(from transcript: String, isBusy: Bool) -> Bool {
        !isBusy && !preparedTranscript(from: transcript).isEmpty
    }
}

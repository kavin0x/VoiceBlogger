import Foundation

/// Polish must not replace a long transcript with a token-capped summary.
enum TranscriptPolishPolicy: Sendable {
    /// Each piece is short enough that a few thousand output tokens can cover it.
    nonisolated static let chunkCharacterLimit = 2_000

    nonisolated static func chunks(of transcript: String) -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > chunkCharacterLimit else { return [trimmed] }
        return PromptBuilder.splitTranscript(
            trimmed,
            chunkSize: chunkCharacterLimit,
            overlap: 0,
            threshold: chunkCharacterLimit
        )
    }

    nonisolated static func maxTokens(for text: String) -> Int {
        let estimated = text.count / 3 + 128
        return min(max(estimated, 256), 4_096)
    }

    nonisolated static func acceptedText(original: String, polished: String, maxTokens: Int) -> String {
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let polishedTrimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !polishedTrimmed.isEmpty else { return originalTrimmed }
        if looksTruncated(original: originalTrimmed, polished: polishedTrimmed, maxTokens: maxTokens) {
            return originalTrimmed
        }
        return polishedTrimmed
    }

    /// A polish that hits the token ceiling, or that throws away most of a long source, is a truncation.
    nonisolated static func looksTruncated(original: String, polished: String, maxTokens: Int) -> Bool {
        guard original.count >= 600 else { return false }
        if polished.count < Int(Double(original.count) * 0.65) {
            return true
        }
        let capCharacters = max(maxTokens * 4, 1)
        let nearCap = polished.count >= Int(Double(capCharacters) * 0.85)
        let lostSubstantialText = polished.count < Int(Double(original.count) * 0.8)
        return nearCap && lostSubstantialText
    }
}

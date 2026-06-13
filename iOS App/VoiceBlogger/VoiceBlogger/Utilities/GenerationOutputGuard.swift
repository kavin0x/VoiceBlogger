import Foundation

struct GenerationOutputGuard {
    enum Failure: LocalizedError, Equatable {
        case repetitiveOutput
        case outputTooLong

        var errorDescription: String? {
            switch self {
            case .repetitiveOutput:
                return "Generation started repeating itself. The saved draft was kept; regenerate to try again."
            case .outputTooLong:
                return "Generation produced more text than expected. The saved draft was kept; regenerate to try again."
            }
        }
    }

    private let maxCharacters: Int

    init(maxCharacters: Int) {
        self.maxCharacters = maxCharacters
    }

    func appending(_ chunk: String, to currentText: String) throws -> String {
        guard !chunk.isEmpty else { return currentText }
        let candidate = currentText + chunk
        guard candidate.count <= maxCharacters else { throw Failure.outputTooLong }
        guard !Self.hasRunawayRepetition(in: candidate) else { throw Failure.repetitiveOutput }
        return candidate
    }

    nonisolated static func hasRunawayRepetition(in text: String) -> Bool {
        hasRepeatedSuffixSegments(in: text) || hasRepeatedRecentParagraphs(in: text)
    }

    nonisolated private static func hasRepeatedSuffixSegments(in text: String) -> Bool {
        let normalized = normalizedInlineSuffix(from: text)
        guard normalized.count >= 240 else { return false }

        let characters = Array(normalized)
        let maximumUnitLength = min(220, characters.count / 4)
        guard maximumUnitLength >= 30 else { return false }

        for unitLength in 30...maximumUnitLength {
            if repeatedSuffixCount(in: characters, unitLength: unitLength) >= 4 {
                return true
            }
        }

        return false
    }

    nonisolated private static func hasRepeatedRecentParagraphs(in text: String) -> Bool {
        let paragraphs = text
            .components(separatedBy: "\n")
            .map(normalizedParagraph)
            .filter { $0.count >= 24 }
            .suffix(5)

        guard paragraphs.count >= 4, let last = paragraphs.last else { return false }
        return paragraphs.suffix(4).allSatisfy { $0 == last }
    }

    nonisolated private static func normalizedInlineSuffix(from text: String) -> String {
        String(text.suffix(2_400))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizedParagraph(_ paragraph: String) -> String {
        paragraph
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func repeatedSuffixCount(in characters: [Character], unitLength: Int) -> Int {
        guard characters.count >= unitLength * 2 else { return 1 }

        let end = characters.count
        let patternStart = end - unitLength
        let pattern = Array(characters[patternStart..<end])
        var repetitions = 1
        var cursor = patternStart

        while cursor >= unitLength {
            let previousStart = cursor - unitLength
            let previous = Array(characters[previousStart..<cursor])
            guard previous == pattern else { break }
            repetitions += 1
            cursor = previousStart
        }

        return repetitions
    }
}

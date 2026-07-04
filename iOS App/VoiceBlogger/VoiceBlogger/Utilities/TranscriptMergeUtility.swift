import Foundation

/// Merges overlapping live transcription chunks by deduplicating shared suffix/prefix words.
enum TranscriptMergeUtility {
    /// Appends `newChunk` to `existing`, removing duplicated words at the boundary.
    nonisolated static func merge(existing: String, newChunk: String) -> String {
        let trimmedNew = newChunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else { return existing }
        guard !existing.isEmpty else { return trimmedNew }

        let existingWords = words(from: existing)
        let newWords = words(from: trimmedNew)
        guard !existingWords.isEmpty, !newWords.isEmpty else {
            return existing + " " + trimmedNew
        }

        let maxOverlap = min(existingWords.count, newWords.count, 12)
        var overlapCount = 0
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = Array(existingWords.suffix(size))
            let prefix = Array(newWords.prefix(size))
            if suffix.map(normalize) == prefix.map(normalize) {
                overlapCount = size
                break
            }
        }

        let uniqueNew = overlapCount > 0 ? Array(newWords.dropFirst(overlapCount)) : newWords
        guard !uniqueNew.isEmpty else { return existing }
        return existing + " " + uniqueNew.joined(separator: " ")
    }

    nonisolated private static func words(from text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    nonisolated private static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters).lowercased()
    }
}

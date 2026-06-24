import Foundation

enum BetaFeatureSettings {
    static let automaticContentKindDetectionKey = "betaAutomaticContentKindDetection"
}

enum GeneratedContentKind: String, CaseIterable, Sendable {
    case blogPost
    case meetingNotes
    case notes

    nonisolated var displayName: String {
        switch self {
        case .blogPost: "Blog Post"
        case .meetingNotes: "Meeting Notes"
        case .notes: "Notes"
        }
    }

    nonisolated var generationActionTitle: String {
        switch self {
        case .blogPost: "Generate Blog Post"
        case .meetingNotes: "Generate Meeting Notes"
        case .notes: "Generate Notes"
        }
    }

    nonisolated var generationPhaseTitle: String {
        switch self {
        case .blogPost: "Generating blog post..."
        case .meetingNotes: "Generating meeting notes..."
        case .notes: "Generating notes..."
        }
    }

    nonisolated var regenerateTitle: String {
        switch self {
        case .blogPost: "Regenerate Blog"
        case .meetingNotes: "Regenerate Meeting Notes"
        case .notes: "Regenerate Notes"
        }
    }

    nonisolated var shareTitle: String {
        switch self {
        case .blogPost: "Share Blog"
        case .meetingNotes: "Share Meeting Notes"
        case .notes: "Share Notes"
        }
    }

    nonisolated var historyLabel: String {
        switch self {
        case .blogPost: "Blog"
        case .meetingNotes: "Meeting"
        case .notes: "Notes"
        }
    }

    nonisolated var historySymbol: String {
        switch self {
        case .blogPost: "doc.text.fill"
        case .meetingNotes: "person.2.fill"
        case .notes: "note.text"
        }
    }

    /// Classifies transcript content into the most appropriate output kind.
    ///
    /// - Parameters:
    ///   - transcript: The cleaned transcript text to analyse.
    ///   - speakerCount: Reserved for future diarization-backed speaker recognition.
    ///                   Heuristic speaker counts are ignored because they can misattribute speech.
    nonisolated static func detect(from transcript: String, speakerCount: Int = 0) -> GeneratedContentKind {
        let rawLines = transcript
            .lowercased()
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalized = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9#\n:.,!?@/ -]", with: " ", options: .regularExpression)
        let words = normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let wordSet = Set(words)
        let wordCount = words.count
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var meetingScore = 0
        var notesScore = 0
        var blogScore = 0

        _ = speakerCount

        let meetingPhrases = [
            "meeting", "agenda", "attendees", "action item", "action items", "follow up", "follow-up",
            "next steps", "decision", "decisions", "deadline", "owner", "assigned", "sync", "standup",
            "roadmap", "stakeholder", "blocker", "blockers", "minutes", "recap"
        ]
        for phrase in meetingPhrases where normalized.contains(phrase) {
            meetingScore += phrase.contains(" ") || phrase.contains("-") ? 3 : 2
        }

        if normalized.contains("we discussed") || normalized.contains("we decided") || normalized.contains("we agreed") {
            meetingScore += 4
        }
        if normalized.contains("follow up with") || normalized.contains("circle back") {
            meetingScore += 3
        }
        if rawLines.contains(where: { $0.range(of: "^[a-z][a-z0-9 ._-]{1,30}:", options: .regularExpression) != nil }) {
            meetingScore += 2
        }
        if rawLines.contains(where: { $0.hasPrefix("action") || $0.hasPrefix("agenda") || $0.hasPrefix("attendees") }) {
            meetingScore += 3
        }

        let noteMarkers: [(marker: String, score: Int)] = [
            ("remember", 3), ("todo", 3), ("to do", 3), ("reminder", 3),
            ("note", 1), ("notes", 1), ("idea", 1), ("ideas", 1),
            ("list", 1), ("draft", 1), ("brainstorm", 1)
        ]
        for item in noteMarkers where normalized.contains(item.marker) {
            notesScore += item.score
        }

        let bulletLikeLineCount = rawLines.filter { line in
            line.hasPrefix("-") ||
            line.hasPrefix("*") ||
            line.unicodeScalars.first?.value == 0x2022 ||
            line.range(of: "^\\d+[.)]", options: .regularExpression) != nil
        }.count
        if bulletLikeLineCount >= 2 {
            notesScore += 4
        } else if bulletLikeLineCount == 1 {
            notesScore += 2
        }
        if wordCount < 120 {
            notesScore += 2
        }
        if lines.count >= 3 && bulletLikeLineCount >= max(2, lines.count / 3) {
            notesScore += 3
        }

        let blogPhrases = [
            "blog post", "article", "essay", "newsletter", "publish", "audience", "readers", "story",
            "hook", "introduction", "conclusion", "share this", "personal story", "lesson learned"
        ]
        for phrase in blogPhrases where normalized.contains(phrase) {
            blogScore += phrase.contains(" ") ? 3 : 2
        }
        if wordSet.contains("i") && (wordSet.contains("think") || wordSet.contains("learned") || wordSet.contains("believe")) {
            blogScore += 2
        }
        if wordCount >= 350 {
            blogScore += 2
        }

        if meetingScore >= max(notesScore + 2, blogScore + 2), meetingScore >= 5 {
            return .meetingNotes
        }
        if notesScore >= blogScore + 2, notesScore >= 4 {
            return .notes
        }
        return .blogPost
    }
}

enum BlogGenerationHandoff {
    private static let genericSpeakerLabelPattern = #"(?m)^\s*(?:[*_]+\s*)?\[?\s*Speaker\s+\d+\s*\]?\s*:?\s*(?:[*_]+\s*)?"#

    static func preparedTranscript(from transcript: String) -> String {
        transcript
            .replacingOccurrences(
                of: genericSpeakerLabelPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contentKind(
        for transcript: String,
        speakerCount: Int = 0,
        automaticDetectionEnabled: Bool = false
    ) -> GeneratedContentKind {
        guard automaticDetectionEnabled else {
            return .blogPost
        }
        return GeneratedContentKind.detect(from: preparedTranscript(from: transcript), speakerCount: speakerCount)
    }

    static func canGenerateBlog(from transcript: String, isBusy: Bool) -> Bool {
        !isBusy && !preparedTranscript(from: transcript).isEmpty
    }
}

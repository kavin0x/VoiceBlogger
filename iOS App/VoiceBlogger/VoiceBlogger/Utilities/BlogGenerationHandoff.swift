import Foundation

enum ContentKindDetectionSettings: Sendable {
    /// Same key the beta toggle used, so existing installs keep one preference.
    nonisolated static let enabledKey = "betaAutomaticContentKindDetection"
    /// Written once when detection leaves beta. That pass turns it on for everyone.
    /// A later manual off is left alone.
    nonisolated static let promotedOnKey = "automaticContentKindDetectionPromotedOn"

    nonisolated static func promoteToDefaultOnIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: promotedOnKey) else { return }
        defaults.set(true, forKey: enabledKey)
        defaults.set(true, forKey: promotedOnKey)
    }
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
        _ = speakerCount

        let rawLines = transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let collapsed = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9#\n:.,!?'@/ -]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = collapsed.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return .blogPost }

        let bulletCount = rawLines.filter(isBulletLine).count
        let speakerLabelCount = rawLines.filter(isSpeakerLabelLine).count
        var meeting = 0
        var notes = 0
        var blog = 0

        func add(_ phrase: String, _ weight: Int, to score: inout Int) {
            if containsPhrase(phrase, in: collapsed) { score += weight }
        }

        add("action item", 5, to: &meeting)
        add("action items", 5, to: &meeting)
        add("we decided", 4, to: &meeting)
        add("we agreed", 4, to: &meeting)
        add("we discussed", 4, to: &meeting)
        add("next steps", 3, to: &meeting)
        add("follow up with", 3, to: &meeting)
        add("follow-up with", 3, to: &meeting)
        add("circle back", 3, to: &meeting)
        add("agenda", 3, to: &meeting)
        add("attendees", 4, to: &meeting)
        add("standup", 3, to: &meeting)
        add("stand-up", 3, to: &meeting)
        add("meeting notes", 4, to: &meeting)
        add("open question", 2, to: &meeting)
        if speakerLabelCount >= 2 { meeting += 4 }
        if rawLines.contains(where: {
            let line = $0.lowercased()
            return line.hasPrefix("action") || line.hasPrefix("agenda") || line.hasPrefix("attendees")
        }) {
            meeting += 3
        }
        if collapsed.range(of: #"\b[a-z]+ owns\b"#, options: .regularExpression) != nil {
            meeting += 2
        }
        let weakMeetingHits = ["meeting", "blocker", "blockers", "stakeholder", "stakeholders", "roadmap", "sync"]
            .filter { containsPhrase($0, in: collapsed) }
            .count
        if weakMeetingHits >= 2 { meeting += 2 }

        add("remember to", 5, to: &notes)
        add("don't forget", 5, to: &notes)
        add("do not forget", 5, to: &notes)
        add("todo", 4, to: &notes)
        add("to-do", 4, to: &notes)
        add("to do list", 4, to: &notes)
        add("reminder", 4, to: &notes)
        add("grocery list", 4, to: &notes)
        add("shopping list", 4, to: &notes)
        add("packing list", 4, to: &notes)
        add("checklist", 3, to: &notes)
        if bulletCount >= 2 {
            notes += 5
        } else if bulletCount == 1 {
            notes += 2
        }
        if rawLines.count >= 3 && bulletCount >= max(2, rawLines.count / 2) {
            notes += 3
        }
        if words.count <= 24 && (notes > 0 || bulletCount > 0) {
            notes += 2
        }

        add("blog post", 4, to: &blog)
        add("newsletter", 3, to: &blog)
        add("readers", 2, to: &blog)
        if isReflectiveProse(collapsed) { blog += 4 }
        if words.count >= 80 && bulletCount == 0 && speakerLabelCount < 2 { blog += 2 }
        let sentences = collapsed.split { ".!?".contains($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if sentences.count >= 3 && words.count >= 50 && bulletCount == 0 { blog += 2 }

        if meeting >= 6 && meeting >= notes + 1 && meeting >= blog {
            return .meetingNotes
        }
        if notes >= 4 && notes >= blog && meeting < 6 {
            return .notes
        }
        if bulletCount >= 2 && notes > blog && meeting < 6 {
            return .notes
        }
        return .blogPost
    }

    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isBulletLine(_ line: String) -> Bool {
        if line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("•") { return true }
        return line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil
    }

    private static func isSpeakerLabelLine(_ line: String) -> Bool {
        line.range(of: #"^[A-Za-z][A-Za-z0-9 .'-]{0,40}:\s+\S"#, options: .regularExpression) != nil
    }

    private static func isReflectiveProse(_ text: String) -> Bool {
        guard containsPhrase("i", in: text) else { return false }
        return ["think", "learned", "believe", "realized", "realised", "noticed", "felt"].contains {
            containsPhrase($0, in: text)
        }
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

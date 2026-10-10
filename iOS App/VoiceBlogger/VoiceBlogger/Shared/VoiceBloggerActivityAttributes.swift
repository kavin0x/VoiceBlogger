#if !targetEnvironment(macCatalyst) && canImport(ActivityKit)
import ActivityKit
import Foundation

nonisolated struct VoiceBloggerActivityAttributes: ActivityAttributes {
    enum ActivityKind: String, Codable, Hashable {
        case recording
        case downloading
    }

    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var progress: Double?
        var startedAt: Date?
        var symbolName: String
        var wordCount: Int?
    }

    var kind: ActivityKind
}

enum LiveActivityPresentation {
    /// Glyph drawn inside the status circle. Symbols that already include a
    /// circle (`arrow.down.circle.fill`) would stack a second ring.
    static func statusGlyph(kind: VoiceBloggerActivityAttributes.ActivityKind, symbolName: String) -> String {
        switch kind {
        case .recording:
            if symbolName.contains("exclamation") { return "exclamationmark" }
            if symbolName.contains("checkmark") { return "checkmark" }
            return "mic.fill"
        case .downloading:
            if symbolName.contains("checkmark") { return "checkmark" }
            if symbolName.contains("pause") { return "pause.fill" }
            return "arrow.down"
        }
    }

    /// The expanded island's leading column sits beside the camera. Long titles
    /// hyphenate there ("Down-loading"), so downloads keep the title in the
    /// full-width bottom region.
    static func showsTitleInExpandedLeading(kind: VoiceBloggerActivityAttributes.ActivityKind) -> Bool {
        kind == .recording
    }
}
#else
import Foundation

nonisolated struct VoiceBloggerActivityAttributes {
    enum ActivityKind: String, Codable, Hashable {
        case recording
        case downloading
    }

    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var progress: Double?
        var startedAt: Date?
        var symbolName: String
        var wordCount: Int?
    }

    var kind: ActivityKind
}

enum LiveActivityPresentation {
    static func statusGlyph(kind: VoiceBloggerActivityAttributes.ActivityKind, symbolName: String) -> String {
        switch kind {
        case .recording:
            if symbolName.contains("exclamation") { return "exclamationmark" }
            if symbolName.contains("checkmark") { return "checkmark" }
            return "mic.fill"
        case .downloading:
            if symbolName.contains("checkmark") { return "checkmark" }
            if symbolName.contains("pause") { return "pause.fill" }
            return "arrow.down"
        }
    }

    static func showsTitleInExpandedLeading(kind: VoiceBloggerActivityAttributes.ActivityKind) -> Bool {
        kind == .recording
    }
}
#endif

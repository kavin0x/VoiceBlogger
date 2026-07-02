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
    }

    var kind: ActivityKind
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
    }

    var kind: ActivityKind
}
#endif

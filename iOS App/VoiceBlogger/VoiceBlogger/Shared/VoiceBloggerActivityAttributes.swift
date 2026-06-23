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
        /// Coarse audio levels for the recording waveform (values in -60...0 dB).
        /// Empty when not recording; the widget falls back to a decorative static waveform.
        var audioLevels: [Float]
    }

    var kind: ActivityKind
}

import Foundation

/// Start and stop flags that arrive together must run in that order.
/// Running stop before start has flipped `isRecording` leaves the microphone on.
enum RecordingIntentSequence: Sendable {
    enum Step: Equatable, Sendable {
        case start
        case stop
    }

    nonisolated static func steps(startPending: Bool, stopPending: Bool) -> [Step] {
        var steps: [Step] = []
        if startPending { steps.append(.start) }
        if stopPending { steps.append(.stop) }
        return steps
    }
}

/// A Whisper progress callback is progress even when the filtered text is empty.
/// Silence, music, and non-speech still advance the file.
enum TranscriptionStallPolicy: Sendable {
    nonisolated static func resetsTimer(callbackInvoked: Bool) -> Bool {
        callbackInvoked
    }
}

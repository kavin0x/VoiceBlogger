import Foundation
import SwiftData

enum TranscriptionState: Int, Codable {
    case untranscribed  // recorded, never transcribed
    case inProgress     // was transcribing when app exited
    case complete       // transcript is final
}

enum TranscriptionFailureResolution: Equatable {
    case retainPreview
    case retryableFailure

    var showsError: Bool {
        self == .retryableFailure
    }

    var transcriptionState: TranscriptionState {
        switch self {
        case .retainPreview: .complete
        case .retryableFailure: .inProgress
        }
    }
}

enum TranscriptionFailurePolicy {
    static func resolve(isRefinement: Bool, hasUsableTranscript: Bool) -> TranscriptionFailureResolution {
        isRefinement && hasUsableTranscript ? .retainPreview : .retryableFailure
    }
}

@Model
final class BlogPost {
    var id: UUID = UUID()
    var title: String = ""
    var transcript: String = ""
    var blogContent: String = ""
    var instagramCaptions: String = ""
    var linkedinPost: String = ""
    var audioFilename: String?
    var createdAt: Date = Date()
    var duration: TimeInterval = 0
    var transcriptionState: TranscriptionState? = TranscriptionState.untranscribed
    /// Number of distinct speakers inferred by heuristic turn-detection during transcription.
    /// 0 = noise only / not yet transcribed, 1 = solo recording, 2+ = multi-speaker meeting.
    var detectedSpeakerCount: Int = 0

    init(
        title: String = "",
        transcript: String = "",
        blogContent: String = "",
        instagramCaptions: String = "",
        linkedinPost: String = "",
        audioFilename: String? = nil,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        transcriptionState: TranscriptionState? = .untranscribed,
        detectedSpeakerCount: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.transcript = transcript
        self.blogContent = blogContent
        self.instagramCaptions = instagramCaptions
        self.linkedinPost = linkedinPost
        self.audioFilename = audioFilename
        self.createdAt = createdAt
        self.duration = duration
        self.transcriptionState = transcriptionState
        self.detectedSpeakerCount = detectedSpeakerCount
    }

    var audioFileURL: URL? {
        guard let name = audioFilename else { return nil }
        return URL.recordingsDirectory.appendingPathComponent(name)
    }
}

extension URL {
    static var recordingsDirectory: URL {
        // FileManager always returns at least one URL for .documentDirectory on iOS,
        // but guard defensively rather than force-subscript.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("recordings", isDirectory: true)
    }
}

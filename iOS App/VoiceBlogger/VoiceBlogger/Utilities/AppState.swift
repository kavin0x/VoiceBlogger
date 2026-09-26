import Foundation
import Observation
import SwiftData

enum AppStage: Equatable {
    case modelDownload
    case recording
    case transcribing(post: BlogPost)
    case preparingBlog(postID: UUID)
    case generatingBlog(post: BlogPost)
    case viewingBlog(post: BlogPost)
    case viewingInstagram(post: BlogPost)
    case viewingLinkedIn(post: BlogPost)
    case history

    var keepsWritingAssistantLoaded: Bool {
        switch self {
        case .preparingBlog, .generatingBlog, .viewingBlog, .viewingInstagram, .viewingLinkedIn:
            return true
        case .modelDownload, .recording, .transcribing, .history:
            return false
        }
    }

    static func == (lhs: AppStage, rhs: AppStage) -> Bool {
        switch (lhs, rhs) {
        case (.modelDownload, .modelDownload): return true
        case (.recording, .recording): return true
        case (.history, .history): return true
        case (.transcribing(let a), .transcribing(let b)): return a.id == b.id
        case (.preparingBlog(let a), .preparingBlog(let b)): return a == b
        case (.generatingBlog(let a), .generatingBlog(let b)): return a.id == b.id
        case (.viewingBlog(let a), .viewingBlog(let b)): return a.id == b.id
        case (.viewingInstagram(let a), .viewingInstagram(let b)): return a.id == b.id
        case (.viewingLinkedIn(let a), .viewingLinkedIn(let b)): return a.id == b.id
        default: return false
        }
    }
}

enum MainTab: String, CaseIterable {
    case record
    case history
    case settings
}

@Observable
final class AppState {
    var stage: AppStage = .recording
    var selectedTab: MainTab = .record
    var errorMessage: String?
    var showError = false
    /// Set by Dictate to Clipboard. Transcription copies the finished transcript, then clears this.
    var copyTranscriptToClipboard = false
    @ObservationIgnored var generationModelContext: ModelContext?

    func navigateTo(_ stage: AppStage) {
        if stage == .history {
            selectedTab = .history
            self.stage = .recording
            return
        }
        self.stage = stage
    }

    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func dismissError() {
        showError = false
        errorMessage = nil
    }
}

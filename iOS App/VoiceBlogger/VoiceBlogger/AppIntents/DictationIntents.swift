import AppIntents
import UIKit

struct DictateToClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Dictate to Clipboard"
    static var description = IntentDescription("Opens Voice Blogger to capture speech and copy the transcript to your clipboard.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentStorage.markStartRecordingPending()
        IntentStorage.markDictateToClipboardPending()
        #if MAIN_APP
        IntentBridge.handlePendingIntentsFromAppProcess()
        #endif
        return .result()
    }
}

struct QuickNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Note"
    static var description = IntentDescription("Start a quick voice note in Voice Blogger.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentStorage.markStartRecordingPending()
        #if MAIN_APP
        IntentBridge.handlePendingIntentsFromAppProcess()
        #endif
        return .result()
    }
}

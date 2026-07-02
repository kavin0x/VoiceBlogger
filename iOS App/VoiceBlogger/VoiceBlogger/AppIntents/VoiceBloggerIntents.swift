import AppIntents

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Opens VoiceBlogger and starts a new voice recording.")
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

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stops the current voice recording in VoiceBlogger.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentStorage.markStopRecordingPending()
        #if MAIN_APP
        IntentBridge.handlePendingIntentsFromAppProcess()
        #endif
        return .result()
    }
}

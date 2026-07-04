import AppIntents

struct VoiceBloggerShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Record in \(.applicationName)",
                "Start a new recording in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
                "Stop \(.applicationName) recording"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: DictateToClipboardIntent(),
            phrases: [
                "Dictate to clipboard in \(.applicationName)",
                "Voice note to clipboard in \(.applicationName)"
            ],
            shortTitle: "Dictate to Clipboard",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: [
                "Quick note in \(.applicationName)",
                "Capture a note in \(.applicationName)"
            ],
            shortTitle: "Quick Note",
            systemImageName: "note.text"
        )
    }
}

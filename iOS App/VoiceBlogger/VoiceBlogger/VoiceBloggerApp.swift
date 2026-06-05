import SwiftUI
import SwiftData

@main
struct VoiceBloggerApp: App {
    @State private var appState = AppState()
    @State private var audioRecorder = AudioRecorder()
    @State private var downloadManager = ModelDownloadManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([BlogPost.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(audioRecorder)
                .environment(downloadManager)
                .task {
                    await downloadManager.warmWhisper()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

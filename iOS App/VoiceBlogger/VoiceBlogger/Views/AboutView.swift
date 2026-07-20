import SwiftUI

struct AboutView: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(AppState.self) var appState
    @AppStorage(BetaFeatureSettings.automaticContentKindDetectionKey) private var automaticContentKindDetectionEnabled = false
    @AppStorage(HapticFeedback.hapticsKey) private var hapticsEnabled = true
    @AppStorage("wifiOnlyDownloads") private var wifiOnlyDownloads = false
    @State private var translateToEnglish = TranscriptionSettings.translateToEnglish
    @State private var polishEnabled = TranscriptionSettings.polishTranscriptEnabled
    @State private var selectedLanguageCode: String? = TranscriptionSettings.pinnedLanguage
    @State private var showResetConfirm = false

    private let githubURL = URL(string: "https://github.com/kavin0x/VoiceBlogger") ?? URL(string: "https://github.com")!
    private let version: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Made by", value: "Kavin Shah")
                    LabeledContent("Version", value: version)
                    LabeledContent("Model quality", value: ModelQualityLevel.current.displayName)
                }

                Section("Beta (may not work as expected or decrease quality)") {
                    Toggle("Automatic content type detection", isOn: $automaticContentKindDetectionEnabled)
                    Text("When enabled, transcripts are labeled as blog posts, meeting notes, or notes based on automatic classification.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VocabularySettingsView()

                Section("Transcription") {
                    Picker("Language", selection: $selectedLanguageCode) {
                        ForEach(TranscriptionSettings.supportedLanguages, id: \.label) { item in
                            Text(item.label).tag(item.code as String?)
                        }
                    }
                    .onChange(of: selectedLanguageCode) { _, code in
                        TranscriptionSettings.pinnedLanguage = code
                    }

                    Toggle("Translate to English", isOn: $translateToEnglish)
                        .onChange(of: translateToEnglish) { _, value in
                            TranscriptionSettings.translateToEnglish = value
                        }

                    Toggle("Polish transcript before generating", isOn: $polishEnabled)
                        .onChange(of: polishEnabled) { _, value in
                            TranscriptionSettings.polishTranscriptEnabled = value
                        }
                }

                Section("App") {
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    Toggle("Wi‑Fi only downloads", isOn: $wifiOnlyDownloads)
                    Button("Reset & Re-download Models", role: .destructive) {
                        showResetConfirm = true
                    }
                }

                Section {
                    Link(destination: githubURL) {
                        HStack {
                            Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Reset Models?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset & Re-download", role: .destructive) {
                    downloadManager.resetDownloads()
                    appState.navigateTo(.modelDownload)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes downloaded AI models and requires a fresh download.")
            }
        }
    }
}

import SwiftUI
import SwiftData

struct TranscriptionView: View {
    let audioURL: URL
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) private var modelContext

    @State private var transcript = ""
    @State private var isTranscribing = false
    @State private var useTranslation = false
    @State private var selectedLanguage = "auto"
    @State private var error: String?

    private let supportedLanguages: [(String, String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("hi", "Hindi"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ar", "Arabic")
    ]

    private var currentMode: TranscriptionMode {
        if useTranslation {
            return .translate
        }
        return .transcribe(language: selectedLanguage == "auto" ? nil : selectedLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Mode", selection: $useTranslation) {
                        Text("Transcribe").tag(false)
                        Text("Translate → English").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if !useTranslation {
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(supportedLanguages, id: \.0) { code, name in
                                Text(name).tag(code)
                            }
                        }
                    }
                }

                if isTranscribing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing with Whisper…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { runTranscription() }
                    }
                } else if !transcript.isEmpty {
                    Section("Transcript") {
                        Text(transcript)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    Section {
                        Button("Generate Blog Post") {
                            generateBlog()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Discard") {
                        try? FileManager.default.removeItem(at: audioURL)
                        appState.navigateTo(.recording)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Transcribe") { runTranscription() }
                        .disabled(isTranscribing)
                }
            }
            .task { runTranscription() }
        }
    }

    private func runTranscription() {
        isTranscribing = true
        error = nil
        Task {
            do {
                let service = try await TranscriptionService.make()
                transcript = try await service.transcribe(audioURL: audioURL, mode: currentMode)
            } catch {
                self.error = error.localizedDescription
            }
            isTranscribing = false
        }
    }

    private func generateBlog() {
        let post = BlogPost(
            title: "",
            transcript: transcript,
            audioFilename: audioURL.lastPathComponent
        )
        modelContext.insert(post)
        appState.navigateTo(.generatingBlog(transcript: transcript, post: post))
    }
}

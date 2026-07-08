import SwiftUI
import SwiftData

struct BlogView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BetaFeatureSettings.automaticContentKindDetectionKey) private var automaticContentKindDetectionEnabled = false

    @State private var streamedText = ""
    @State private var isGenerating = false
    @State private var generationPhase = "Generating..."
    @State private var generationError: String?
    @State private var showShareSheet = false
    @State private var showAudioShareSheet = false
    @State private var showTranscriptShareSheet = false
    @State private var didComplete = false
    @State private var isEditing = false
    @State private var editableText = ""
    @State private var showCopiedFeedback = false
    @State private var generationTask: Task<Void, Never>?

    var contentKind: GeneratedContentKind {
        BlogGenerationHandoff.contentKind(
            for: post.transcript,
            speakerCount: post.detectedSpeakerCount,
            automaticDetectionEnabled: automaticContentKindDetectionEnabled
        )
    }
    var displayText: String { streamedText.isEmpty ? post.blogContent : streamedText }
    var shareText: String { isEditing ? editableText : displayText }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(generationPhase)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.bottom, 4)
                    }

                    if let error = generationError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                            if !isGenerating {
                                Button {
                                    reblog()
                                } label: {
                                    Label("Try Again", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }

                    if !displayText.isEmpty {
                        if isEditing {
                            TextEditor(text: $editableText)
                                .font(.body)
                                .frame(minHeight: 400)
                                .scrollContentBackground(.hidden)
                                .accessibilityLabel("Generated content")
                        } else {
                            MarkdownView(text: displayText)
                                .textSelection(.enabled)
                        }
                    }

                    if !displayText.isEmpty && !isGenerating {
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = shareText
                                HapticFeedback.success()
                                showCopiedFeedback = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    showCopiedFeedback = false
                                }
                            } label: {
                                Label(showCopiedFeedback ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                appState.navigateTo(.viewingInstagram(post: post))
                            } label: {
                                Label("Instagram", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                appState.navigateTo(.viewingLinkedIn(post: post))
                            } label: {
                                Label("LinkedIn", systemImage: "briefcase.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle(post.title.isEmpty ? contentKind.displayName : post.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("New Recording") {
                        appState.navigateTo(.recording)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Done") {
                            commitEdits()
                        }
                        .fontWeight(.semibold)
                    } else {
                        Menu {
                            if !displayText.isEmpty && !isGenerating {
                                Button {
                                    editableText = displayText
                                    isEditing = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    showShareSheet = true
                                } label: {
                                    Label(contentKind.shareTitle, systemImage: "square.and.arrow.up")
                                }
                                if post.audioFileURL != nil {
                                    Button {
                                        showAudioShareSheet = true
                                    } label: {
                                        Label("Share Audio", systemImage: "waveform")
                                    }
                                }
                                if !post.transcript.isEmpty {
                                    Button {
                                        showTranscriptShareSheet = true
                                    } label: {
                                        Label("Save Transcript", systemImage: "doc.text")
                                    }
                                }
                                Button {
                                    reblog()
                                } label: {
                                    Label(contentKind.regenerateTitle, systemImage: "arrow.clockwise")
                                }
                                Divider()
                            }
                            Button {
                                appState.navigateTo(.history)
                            } label: {
                                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")

                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareText])
            }
            .sheet(isPresented: $showAudioShareSheet) {
                if let audioURL = post.audioFileURL {
                    ShareSheet(items: [audioURL])
                }
            }
            .sheet(isPresented: $showTranscriptShareSheet) {
                ShareSheet(items: [post.transcript])
            }
            .onAppear {
                startGenerationTask()
            }
            .onDisappear {
                cancelGenerationTask()
                downloadManager.releaseLLMService()
                Task { await downloadManager.warmWhisper() }
            }
        }
    }

    private func startGenerationTask() {
        guard generationTask == nil else { return }
        generationTask = Task {
            await generateIfNeeded()
            generationTask = nil
        }
    }

    private func cancelGenerationTask() {
        generationTask?.cancel()
        generationTask = nil
        if isGenerating {
            downloadManager.releaseLLMService()
        }
    }

    private func commitEdits() {
        post.blogContent = editableText
        post.title = PromptBuilder.extractTitle(from: editableText)
        savePostContext()
        streamedText = ""
        isEditing = false
    }

    private func savePostContext() {
        try? (post.modelContext ?? modelContext).save()
    }

    private func reblog() {
        post.blogContent = ""
        post.title = ""
        streamedText = ""
        didComplete = false
        generationError = nil
        generationPhase = contentKind.generationPhaseTitle
        savePostContext()
        startGenerationTask()
    }

    private func generateIfNeeded() async {
        guard !isGenerating && post.blogContent.isEmpty && !didComplete else { return }
        let transcript = BlogGenerationHandoff.preparedTranscript(from: post.transcript)
        guard !transcript.isEmpty else {
            generationError = "Transcript is empty. Re-transcribe before generating content."
            return
        }

        isGenerating = true
        generationError = nil
        generationPhase = contentKind.generationPhaseTitle
        defer { isGenerating = false }

        do {
            let service = try await downloadManager.loadedLLMService()
            let outputGuard = GenerationOutputGuard(maxCharacters: 18_000)
            var fullText = ""
            var pendingDisplayCharacterCount = 0
            var lastDisplayUpdate = Date()
            let vocabularyTerms = VocabularyStore.terms(from: modelContext)
            let detectedKind = BlogGenerationHandoff.contentKind(
                for: transcript,
                speakerCount: post.detectedSpeakerCount,
                automaticDetectionEnabled: automaticContentKindDetectionEnabled
            )
            let isSpeakerAnnotated = false
            for try await chunk in service.generateContent(
                transcript: transcript,
                contentKind: detectedKind,
                isSpeakerAnnotated: isSpeakerAnnotated,
                vocabularyTerms: vocabularyTerms,
                onPhaseChange: { phase in
                Task { @MainActor in generationPhase = phase }
            }) {
                if Task.isCancelled { return }
                fullText = try outputGuard.appending(chunk, to: fullText)
                pendingDisplayCharacterCount += chunk.count

                if pendingDisplayCharacterCount >= 24 || Date().timeIntervalSince(lastDisplayUpdate) >= 0.05 {
                    streamedText = fullText
                    pendingDisplayCharacterCount = 0
                    lastDisplayUpdate = Date()
                    await Task.yield()
                }
            }
            streamedText = fullText
            guard !fullText.isEmpty else {
                generationError = "No content was generated. Please try again."
                return
            }
            post.blogContent = fullText
            post.title = PromptBuilder.extractTitle(from: fullText)
            savePostContext()
            didComplete = true
            // Keep LLM loaded — InstagramView reuses it immediately after blog generation.
        } catch is CancellationError {
            downloadManager.releaseLLMService()
            return
        } catch {
            downloadManager.releaseLLMService()
            generationError = error.localizedDescription
        }
    }
}

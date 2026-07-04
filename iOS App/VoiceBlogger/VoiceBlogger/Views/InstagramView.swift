import SwiftUI
import SwiftData

struct InstagramView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var streamedText = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showShareSheet = false
    @State private var didComplete = false
    @State private var generationTask: Task<Void, Never>?
    @State private var showCopied = false

    private var captionContent: String {
        let source = streamedText.isEmpty ? post.instagramCaptions : streamedText
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = generationError, !isGenerating {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            streamedText = ""
                            generationError = nil
                            didComplete = false
                            post.instagramCaptions = ""
                            startGenerationTask()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !captionContent.isEmpty {
                    captionCardView
                } else if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating caption…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: 640)
            .navigationTitle("Instagram Captions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Blog") {
                        appState.navigateTo(.viewingBlog(post: post))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appState.navigateTo(.recording)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [captionContent])
            }
            .onAppear {
                startGenerationTask()
            }
            .onDisappear {
                cancelGenerationTask()
            }
        }
    }

    private func startGenerationTask() {
        generationTask?.cancel()
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

    private var captionCardView: some View {
        VStack(spacing: 16) {
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Generating caption…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Instagram Caption", systemImage: "camera.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Divider()
                    if isGenerating {
                        Text(captionContent)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        MarkdownView(text: captionContent)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, isGenerating ? 4 : 16)
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = captionContent
                    showCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showCopied = false
                    }
                } label: {
                    Label(
                        showCopied ? "Copied!" : "Copy",
                        systemImage: showCopied ? "checkmark" : "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)

                Button {
                    regenerateCaption()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func regenerateCaption() {
        streamedText = ""
        generationError = nil
        didComplete = false
        post.instagramCaptions = ""
        savePostContext()
        startGenerationTask()
    }

    private func generateIfNeeded() async {
        guard post.instagramCaptions.isEmpty && !didComplete else { return }
        let blogContent = post.blogContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !blogContent.isEmpty else {
            generationError = "Generate a blog post before creating Instagram captions."
            return
        }

        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        do {
            // LLM is already loaded from blog generation; just clear whisperKit residual.
            await downloadManager.prepareForLLMGeneration()
            let service = try await downloadManager.loadedLLMService()
            let outputGuard = GenerationOutputGuard(maxCharacters: 2_000)
            var fullText = ""
            var pendingCount = 0
            for try await chunk in service.generateInstagramCaptions(blogContent: blogContent) {
                if Task.isCancelled { return }
                fullText = try outputGuard.appending(chunk, to: fullText)
                pendingCount += chunk.count
                if pendingCount >= 20 {
                    streamedText = fullText
                    pendingCount = 0
                    await Task.yield()
                }
            }
            streamedText = fullText
            guard !fullText.isEmpty else { return }
            post.instagramCaptions = fullText
            savePostContext()
            didComplete = true
            downloadManager.releaseLLMService()
        } catch is CancellationError {
            downloadManager.releaseLLMService()
            return
        } catch {
            downloadManager.releaseLLMService()
            generationError = error.localizedDescription
        }
    }

    private func savePostContext() {
        try? (post.modelContext ?? modelContext).save()
    }
}

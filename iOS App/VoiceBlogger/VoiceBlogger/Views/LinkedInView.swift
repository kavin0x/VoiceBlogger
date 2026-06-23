import SwiftUI
import SwiftData

struct LinkedInView: View {
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

    private var postContent: String {
        streamedText.isEmpty ? post.linkedinPost : streamedText
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
                            post.linkedinPost = ""
                            startGenerationTask()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !postContent.isEmpty {
                    postCardView
                } else if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating LinkedIn post…")
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
            .navigationTitle("LinkedIn Post")
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
                ShareSheet(items: [postContent])
            }
            .onAppear {
                startGenerationTask()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    cancelGenerationForBackground()
                }
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

    private func cancelGenerationForBackground() {
        guard isGenerating else { return }
        cancelGenerationTask()
        generationError = "Generation stopped because the app left the foreground. Try again when the app is active."
    }

    private var postCardView: some View {
        VStack(spacing: 16) {
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Generating LinkedIn post…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("LinkedIn Post", systemImage: "briefcase.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Divider()
                    if isGenerating {
                        Text(postContent)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        MarkdownView(text: postContent)
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
                    UIPasteboard.general.string = postContent
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
                    regeneratePost()
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

    private func regeneratePost() {
        streamedText = ""
        generationError = nil
        didComplete = false
        post.linkedinPost = ""
        savePostContext()
        startGenerationTask()
    }

    private func generateIfNeeded() async {
        guard post.linkedinPost.isEmpty && !didComplete else { return }
        let blogContent = post.blogContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !blogContent.isEmpty else {
            generationError = "Generate a blog post before creating a LinkedIn post."
            return
        }

        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        do {
            await downloadManager.prepareForLLMGeneration()
            let service = try await downloadManager.loadedLLMService()
            let outputGuard = GenerationOutputGuard(maxCharacters: 5_000)
            var fullText = ""
            var pendingCount = 0
            for try await chunk in service.generateLinkedInPost(blogContent: blogContent) {
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
            post.linkedinPost = fullText
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

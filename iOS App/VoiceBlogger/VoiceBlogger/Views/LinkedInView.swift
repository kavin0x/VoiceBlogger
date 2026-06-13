import SwiftUI
import SwiftData

struct LinkedInView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var streamedText = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showShareSheet = false
    @State private var didComplete = false

    private var postContent: String {
        streamedText.isEmpty ? post.linkedinPost : streamedText
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating LinkedIn post…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = generationError {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                } else if !postContent.isEmpty {
                    postCardView
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
            .task { await generateIfNeeded() }
        }
    }

    private var postCardView: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("LinkedIn Post", systemImage: "briefcase.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Divider()
                    Text(postContent)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = postContent
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
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
            var fullText = ""
            for try await chunk in service.generateLinkedInPost(blogContent: blogContent) {
                if Task.isCancelled { return }
                fullText += chunk
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

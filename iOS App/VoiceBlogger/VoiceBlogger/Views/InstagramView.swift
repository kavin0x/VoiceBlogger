import SwiftUI
import SwiftData

struct InstagramView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var streamedText = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var selectedCardIndex = 0
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var didComplete = false

    private var captions: [String] {
        let source = streamedText.isEmpty ? post.instagramCaptions : streamedText
        return source
            .components(separatedBy: "\n---\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating captions…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = generationError {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                } else if captions.isEmpty && !streamedText.isEmpty {
                    Text(streamedText)
                        .padding()
                        .font(.body)
                        .textSelection(.enabled)
                } else if !captions.isEmpty {
                    captionPager
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
                        let text = captions.indices.contains(selectedCardIndex)
                            ? captions[selectedCardIndex] : post.instagramCaptions
                        shareText = text
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(captions.isEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareText])
            }
            .task { await generateIfNeeded() }
        }
    }

    private var captionPager: some View {
        VStack(spacing: 16) {
            TabView(selection: $selectedCardIndex) {
                ForEach(Array(captions.enumerated()), id: \.offset) { index, caption in
                    CaptionCardView(caption: caption, cardNumber: index + 1, total: captions.count)
                        .tag(index)
                        .padding(.horizontal, 16)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                Button {
                    let text = captions.indices.contains(selectedCardIndex)
                        ? captions[selectedCardIndex] : ""
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    let text = captions.indices.contains(selectedCardIndex)
                        ? captions[selectedCardIndex] : ""
                    shareText = text
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
            downloadManager.prepareForLLMGeneration(releaseLLM: true)
            try await Task.sleep(nanoseconds: 750_000_000)
            let service = try await downloadManager.loadedLLMService()
            var fullText = ""
            for try await chunk in service.generateInstagramCaptions(blogContent: blogContent) {
                if Task.isCancelled { return }
                streamedText += chunk
                fullText += chunk
            }
            guard !fullText.isEmpty else { return }
            post.instagramCaptions = fullText
            try? modelContext.save()
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
}

private struct CaptionCardView: View {
    let caption: String
    let cardNumber: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Caption \(cardNumber) of \(total)", systemImage: "camera.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Divider()
            ScrollView {
                Text(caption)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

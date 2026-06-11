import SwiftUI
import SwiftData
import os

// Renders markdown headings (# / ## / ###) and inline styles via AttributedString.
private struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case h1(String), h2(String), h3(String), body(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var pending: [String] = []

        func flush() {
            let joined = pending.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { result.append(.body(joined)) }
            pending = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("### ") {
                flush(); result.append(.h3(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flush(); result.append(.h2(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush(); result.append(.h1(String(line.dropFirst(2))))
            } else {
                pending.append(line)
            }
        }
        flush()
        return result
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .h1(let s):
            Text(inlineMarkdown(s)).font(.title).fontWeight(.bold)
        case .h2(let s):
            Text(inlineMarkdown(s)).font(.title2).fontWeight(.semibold)
        case .h3(let s):
            Text(inlineMarkdown(s)).font(.title3).fontWeight(.semibold)
        case .body(let s):
            Text(inlineMarkdown(s)).font(.body)
        }
    }

    private func inlineMarkdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}

struct BlogView: View {
    let post: BlogPost
    @Environment(AppState.self) var appState
    @Environment(ModelDownloadManager.self) var downloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var streamedText = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showShareSheet = false
    @State private var showAudioShareSheet = false
    @State private var didComplete = false
    @State private var isEditing = false
    @State private var editableText = ""

    var displayText: String { streamedText.isEmpty ? post.blogContent : streamedText }
    var shareText: String { isEditing ? editableText : displayText }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Generating blog post…")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.bottom, 4)
                    }

                    if let error = generationError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }

                    if !displayText.isEmpty {
                        if isEditing {
                            TextEditor(text: $editableText)
                                .font(.body)
                                .frame(minHeight: 400)
                                .scrollContentBackground(.hidden)
                                .accessibilityLabel("Blog post content")
                        } else {
                            MarkdownView(text: displayText)
                                .textSelection(.enabled)
                        }
                    }

                    if !displayText.isEmpty && !isGenerating {
                        Divider()
                        HStack(spacing: 12) {
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
            }
            .navigationTitle(post.title.isEmpty ? "Blog Post" : post.title)
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
                                    Label("Share Blog", systemImage: "square.and.arrow.up")
                                }
                                if post.audioFileURL != nil {
                                    Button {
                                        showAudioShareSheet = true
                                    } label: {
                                        Label("Share Audio", systemImage: "waveform")
                                    }
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
            .task {
                await generateIfNeeded()
            }
            .onDisappear {
                guard !isGenerating else { return }
                downloadManager.releaseLLMService()
                Task { await downloadManager.warmWhisper() }
            }
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

    private func generateIfNeeded() async {
        guard !isGenerating && post.blogContent.isEmpty && !didComplete else { return }
        let transcript = BlogGenerationHandoff.preparedTranscript(from: post.transcript)
        guard !transcript.isEmpty else {
            generationError = "Transcript is empty. Re-transcribe before generating a blog post."
            return
        }

        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        do {
            if !downloadManager.hasLoadedLLMService {
                await downloadManager.prepareForLLMGenerationBarrier()
            }
            let availMB = os_proc_available_memory() / (1024 * 1024)
            os_log("BlogView: available memory before LLM load = %lu MB", type: .info, availMB)
            let service = try await downloadManager.loadedLLMService()
            var fullText = ""
            for try await chunk in service.generateBlog(transcript: transcript) {
                if Task.isCancelled { return }
                streamedText += chunk
                fullText += chunk
            }
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

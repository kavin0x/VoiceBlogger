import SwiftUI
import SwiftData
import os

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
        case h1(String), h2(String), h3(String)
        case paragraph(String)
        case bulletList([String])
        case orderedList([String])
        case codeBlock(String)
        case blockquote(String)
        case divider
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                result.append(.h3(String(trimmed.dropFirst(4)))); i += 1
            } else if trimmed.hasPrefix("## ") {
                result.append(.h2(String(trimmed.dropFirst(3)))); i += 1
            } else if trimmed.hasPrefix("# ") {
                result.append(.h1(String(trimmed.dropFirst(2)))); i += 1
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(.divider); i += 1
            } else if trimmed.hasPrefix("```") {
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }
                result.append(.codeBlock(codeLines.joined(separator: "\n")))
            } else if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quoteLines.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2))); i += 1
                }
                result.append(.blockquote(quoteLines.joined(separator: "\n")))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                        items.append(String(t.dropFirst(2))); i += 1
                    } else { break }
                }
                result.append(.bulletList(items))
            } else if trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = t.range(of: #"^\d+\. "#, options: .regularExpression) {
                        items.append(String(t[range.upperBound...])); i += 1
                    } else { break }
                }
                result.append(.orderedList(items))
            } else if trimmed.isEmpty {
                i += 1
            } else {
                var paraLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix("> ") ||
                       t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") ||
                       t == "---" || t == "***" || t == "___" ||
                       t.range(of: #"^\d+\. "#, options: .regularExpression) != nil { break }
                    paraLines.append(lines[i]); i += 1
                }
                let joined = paraLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { result.append(.paragraph(joined)) }
            }
        }

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
        case .paragraph(let s):
            Text(inlineMarkdown(s)).font(.body)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(inlineMarkdown(item))
                    }
                    .font(.body)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).").monospacedDigit()
                        Text(inlineMarkdown(item))
                    }
                    .font(.body)
                }
            }
        case .codeBlock(let code):
            Text(code)
                .font(.system(.footnote, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .blockquote(let s):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                Text(inlineMarkdown(s))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        case .divider:
            Divider()
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
    @State private var showTranscriptShareSheet = false
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
                                    Label("Regenerate Blog", systemImage: "arrow.clockwise")
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

    private func reblog() {
        post.blogContent = ""
        post.title = ""
        streamedText = ""
        didComplete = false
        savePostContext()
        Task { await generateIfNeeded() }
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

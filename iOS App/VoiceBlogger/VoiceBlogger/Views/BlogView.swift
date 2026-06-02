import SwiftUI
import SwiftData

struct BlogView: View {
    let post: BlogPost
    let transcript: String
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
                        } else {
                            Text(displayText)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    if !displayText.isEmpty && !isGenerating {
                        Divider()
                        Button {
                            appState.navigateTo(.viewingInstagram(post: post))
                        } label: {
                            Label("Generate Instagram Captions", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
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
        }
    }

    private func commitEdits() {
        post.blogContent = editableText
        post.title = PromptBuilder.extractTitle(from: editableText)
        try? modelContext.save()
        streamedText = ""
        isEditing = false
    }

    private func generateIfNeeded() async {
        guard post.blogContent.isEmpty && !didComplete else { return }
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        do {
            downloadManager.prepareForLLMGeneration(releaseLLM: true)
            try await Task.sleep(nanoseconds: 750_000_000)
            let service = try await downloadManager.loadedLLMService()
            var fullText = ""
            for try await chunk in service.generateBlog(transcript: transcript) {
                if Task.isCancelled { return }
                streamedText += chunk
                fullText += chunk
            }
            guard !fullText.isEmpty else { return }
            post.blogContent = fullText
            post.title = PromptBuilder.extractTitle(from: fullText)
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

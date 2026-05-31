import SwiftUI
import SwiftData

struct BlogView: View {
    let post: BlogPost
    let transcript: String
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) private var modelContext

    @State private var streamedText = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showShareSheet = false
    @State private var didComplete = false

    var displayText: String { streamedText.isEmpty ? post.blogContent : streamedText }

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
                        Text(displayText)
                            .font(.body)
                            .textSelection(.enabled)
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
                    if !displayText.isEmpty && !isGenerating {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Button("History") {
                        appState.navigateTo(.history)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [displayText])
            }
            .task {
                await generateIfNeeded()
            }
        }
    }

    private func generateIfNeeded() async {
        guard post.blogContent.isEmpty && !didComplete else { return }
        isGenerating = true
        generationError = nil
        do {
            let service = try await LLMService.make()
            var fullText = ""
            for try await chunk in service.generateBlog(transcript: transcript) {
                streamedText += chunk
                fullText += chunk
            }
            post.blogContent = fullText
            post.title = PromptBuilder.extractTitle(from: fullText)
            try? modelContext.save()
            didComplete = true
        } catch {
            generationError = error.localizedDescription
        }
        isGenerating = false
    }
}

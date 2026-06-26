import SwiftUI
import SwiftData

struct BlogListView: View {
    @Environment(AppState.self) var appState
    @Query(sort: \BlogPost.createdAt, order: .reverse) private var posts: [BlogPost]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(BetaFeatureSettings.automaticContentKindDetectionKey) private var automaticContentKindDetectionEnabled = false
    @State private var searchText = ""

    private var filteredPosts: [BlogPost] {
        SearchUtility.filter(posts, query: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if posts.isEmpty {
                    ContentUnavailableView(
                        "No Content Yet",
                        systemImage: "doc.text",
                        description: Text("Record your voice and generate notes or a post to see it here.")
                    )
                } else if filteredPosts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredPosts) { post in
                            Button {
                                if post.transcriptionState == nil || post.transcriptionState == .complete {
                                    appState.navigateTo(.viewingBlog(post: post))
                                } else {
                                    appState.navigateTo(.transcribing(post: post))
                                }
                            } label: {
                                BlogPostRowView(
                                    post: post,
                                    automaticDetectionEnabled: automaticContentKindDetectionEnabled
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteFilteredPosts)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search history")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("New Recording") {
                        appState.navigateTo(.recording)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func deleteFilteredPosts(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredPosts[index])
        }
        try? modelContext.save()
    }
}

private struct BlogPostRowView: View {
    let post: BlogPost
    let automaticDetectionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let contentKind = BlogGenerationHandoff.contentKind(
                for: post.transcript,
                automaticDetectionEnabled: automaticDetectionEnabled
            )
            Text(post.title.isEmpty ? "Untitled \(contentKind.displayName)" : post.title)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if post.duration > 0 {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(formattedDuration(post.duration))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if post.transcriptionState == .untranscribed {
                    Label("Untranscribed", systemImage: "waveform.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if post.transcriptionState == .inProgress {
                    Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if !post.blogContent.isEmpty {
                    Label(contentKind.historyLabel, systemImage: contentKind.historySymbol)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if !post.instagramCaptions.isEmpty {
                    Label("IG", systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            if !post.transcript.isEmpty {
                Text(String(post.transcript.prefix(200)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

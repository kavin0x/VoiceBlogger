import SwiftUI
import SwiftData

struct BlogListView: View {
    @Environment(AppState.self) var appState
    @Query(sort: \BlogPost.createdAt, order: .reverse) private var posts: [BlogPost]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if posts.isEmpty {
                    ContentUnavailableView(
                        "No Blog Posts Yet",
                        systemImage: "doc.text",
                        description: Text("Record your voice and generate a blog post to see it here.")
                    )
                } else {
                    List {
                        ForEach(posts) { post in
                            Button {
                                if post.transcriptionState == nil || post.transcriptionState == .complete {
                                    appState.navigateTo(.viewingBlog(post: post))
                                } else {
                                    appState.navigateTo(.transcribing(post: post))
                                }
                            } label: {
                                BlogPostRowView(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deletePosts)
                    }
                }
            }
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

    private func deletePosts(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(posts[index])
        }
        try? modelContext.save()
    }
}

private struct BlogPostRowView: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title.isEmpty ? "Untitled Post" : post.title)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Label("Blog", systemImage: "doc.text.fill")
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
}

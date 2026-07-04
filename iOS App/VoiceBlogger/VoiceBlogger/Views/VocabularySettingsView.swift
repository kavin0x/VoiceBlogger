import SwiftUI
import SwiftData

struct VocabularySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomVocabularyEntry.term) private var entries: [CustomVocabularyEntry]
    @State private var newTerm = ""

    var body: some View {
        Section("Personal Dictionary") {
            HStack {
                TextField("Add name, acronym, or jargon", text: $newTerm)
                Button("Add") { addTerm() }
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(entries) { entry in
                Text(entry.term)
            }
            .onDelete(perform: deleteEntries)
            Text("Custom terms help transcription and generation spell names correctly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        modelContext.insert(CustomVocabularyEntry(term: term))
        try? modelContext.save()
        newTerm = ""
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }
}

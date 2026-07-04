import Foundation
import SwiftData

@Model
final class CustomVocabularyEntry {
    var id: UUID = UUID()
    var term: String = ""
    var createdAt: Date = Date()

    init(term: String) {
        self.id = UUID()
        self.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = .now
    }
}

@Model
final class CustomDictationMode {
    var id: UUID = UUID()
    var name: String = ""
    var systemPrompt: String = ""
    var isDefault: Bool = false
    var createdAt: Date = Date()

    init(name: String, systemPrompt: String, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.isDefault = isDefault
        self.createdAt = .now
    }
}

enum VocabularyStore {
    static func terms(from context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<CustomVocabularyEntry>(
            sortBy: [SortDescriptor(\.term)]
        )
        return (try? context.fetch(descriptor))?.map(\.term).filter { !$0.isEmpty } ?? []
    }

    static func promptInjection(from context: ModelContext) -> String {
        let terms = terms(from: context)
        guard !terms.isEmpty else { return "" }
        return "Custom vocabulary (spell these correctly): " + terms.joined(separator: ", ")
    }
}

import Foundation

/// Recordings must stay writable after the phone locks. `FileProtectionType.complete`
/// rejects writes until the next unlock, and the audio tap was dropping those samples.
enum RecordingStorage: Sendable {
    nonisolated static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    nonisolated static func prepareDirectory(_ url: URL = .recordingsDirectory) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
    }

    nonisolated static func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: url.path
        )
    }

    /// Removes `recordings/<filename>` for a deleted history row.
    /// `filename` is used only as a last path component so a stored value cannot escape the directory.
    nonisolated static func deleteAudioFile(named filename: String?, in directory: URL = .recordingsDirectory) {
        guard let filename else { return }
        let name = (filename as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return }
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }
}

enum ModelCacheLocations: Sendable {
    /// Speech models live under Documents. The writing model lives under Library/Caches.
    nonisolated static func huggingFaceDirectories(documents: URL, caches: URL) -> [URL] {
        [
            documents.appendingPathComponent("huggingface", isDirectory: true),
            caches.appendingPathComponent("huggingface", isDirectory: true),
        ]
    }

    nonisolated static func removeDownloadedModels(fileManager: FileManager = .default) {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        for url in huggingFaceDirectories(documents: documents, caches: caches) {
            try? fileManager.removeItem(at: url)
        }
    }
}

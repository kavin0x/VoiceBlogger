import Foundation

/// Where recordings live. iCloud mode uses the ubiquity container, not the whole Documents directory,
/// so the on-device model cache is never uploaded.
enum RecordingLocations: Sendable {
    nonisolated(unsafe) private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedUbiquityDirectory: URL?

    nonisolated static func localDirectory(fileManager: FileManager = .default) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("recordings", isDirectory: true)
    }

    nonisolated static func ubiquityDirectory(
        containerIdentifier: String = ICloudSyncSettings.containerIdentifier,
        fileManager: FileManager = .default
    ) -> URL? {
        cacheLock.lock()
        let cached = cachedUbiquityDirectory
        cacheLock.unlock()
        if let cached { return cached }

        guard let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        let recordings = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
        cacheLock.lock()
        cachedUbiquityDirectory = recordings
        cacheLock.unlock()
        return recordings
    }

    nonisolated static func recordingsDirectory(
        syncEnabled: Bool = ICloudSyncSettings.isEnabled(),
        fileManager: FileManager = .default
    ) -> URL {
        if syncEnabled, let cloud = ubiquityDirectory(fileManager: fileManager) {
            return cloud
        }
        return localDirectory(fileManager: fileManager)
    }

    /// Test hook so a cached container URL from another process state does not leak into unit tests.
    nonisolated static func resetUbiquityCache() {
        cacheLock.lock()
        cachedUbiquityDirectory = nil
        cacheLock.unlock()
    }
}

struct RecordingMoveResult: Equatable {
    var moved: [String]
    var copied: [String]
    var skipped: [String]
}

enum RecordingLibraryMigration: Sendable {
    nonisolated static func isSafeFilename(_ filename: String) -> Bool {
        let name = (filename as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name == filename else { return false }
        return !name.contains("/") && !name.contains("\\")
    }

    nonisolated static func fileURL(named filename: String, in directory: URL) -> URL? {
        guard isSafeFilename(filename) else { return nil }
        return directory.appendingPathComponent(filename)
    }

    nonisolated static func moveRecordings(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) -> RecordingMoveResult {
        transfer(from: source, to: destination, fileManager: fileManager, copy: false)
    }

    nonisolated static func copyRecordings(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) -> RecordingMoveResult {
        transfer(from: source, to: destination, fileManager: fileManager, copy: true)
    }

    nonisolated static func moveLocalRecordingsIntoUbiquity(fileManager: FileManager = .default) {
        guard let cloud = RecordingLocations.ubiquityDirectory(fileManager: fileManager) else { return }
        _ = moveRecordings(
            from: RecordingLocations.localDirectory(fileManager: fileManager),
            to: cloud,
            fileManager: fileManager
        )
    }

    nonisolated static func copyUbiquityRecordingsToLocal(fileManager: FileManager = .default) {
        guard let cloud = RecordingLocations.ubiquityDirectory(fileManager: fileManager) else { return }
        _ = copyRecordings(
            from: cloud,
            to: RecordingLocations.localDirectory(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    nonisolated private static func transfer(
        from source: URL,
        to destination: URL,
        fileManager: FileManager,
        copy: Bool
    ) -> RecordingMoveResult {
        var result = RecordingMoveResult(moved: [], copied: [], skipped: [])
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return result
        }
        // Only the recordings directory is transferred. A sibling model cache is never visited.
        let resolvedSource = source.standardizedFileURL
        let resolvedDestination = destination.standardizedFileURL
        guard resolvedSource != resolvedDestination else { return result }

        do {
            try RecordingStorage.prepareDirectory(resolvedDestination)
        } catch {
            return result
        }

        let names = (try? fileManager.contentsOfDirectory(atPath: resolvedSource.path)) ?? []
        for name in names.sorted() {
            guard isSafeFilename(name),
                  let from = fileURL(named: name, in: resolvedSource),
                  let to = fileURL(named: name, in: resolvedDestination),
                  from.standardizedFileURL.deletingLastPathComponent() == resolvedSource,
                  to.standardizedFileURL.deletingLastPathComponent() == resolvedDestination
            else {
                result.skipped.append(name)
                continue
            }
            if fileManager.fileExists(atPath: to.path) {
                result.skipped.append(name)
                continue
            }
            do {
                if copy {
                    try fileManager.copyItem(at: from, to: to)
                    result.copied.append(name)
                } else {
                    try fileManager.moveItem(at: from, to: to)
                    result.moved.append(name)
                }
                RecordingStorage.protect(to)
            } catch {
                result.skipped.append(name)
            }
        }
        return result
    }
}

enum RecordingReadiness: Equatable, Sendable {
    case ready
    case downloading
    case missing

    /// Why the file cannot be played or shared yet. Nil when the bytes are already local.
    var unavailableMessage: String? {
        switch self {
        case .ready:
            nil
        case .downloading:
            "This recording is still downloading from iCloud."
        case .missing:
            "Could not find this recording on this device."
        }
    }
}

enum RecordingFileAccess: Sendable {
    nonisolated static func readiness(at url: URL, fileManager: FileManager = .default) -> RecordingReadiness {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .fileSizeKey,
        ])
        let isUbiquitous = values?.isUbiquitousItem == true
        if isUbiquitous, values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            return .downloading
        }
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        if isUbiquitous, (values?.fileSize ?? 0) == 0 {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            return .downloading
        }
        return .ready
    }
}

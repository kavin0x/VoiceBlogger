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

    /// The folder in use can change during a session: a take is written locally while the
    /// iCloud container is still unavailable, then later lookups use the container. Export
    /// must open the file that was actually written.
    nonisolated static func resolveRecordingURL(
        named filename: String,
        syncEnabled: Bool = ICloudSyncSettings.isEnabled(),
        fileManager: FileManager = .default
    ) -> URL? {
        guard let primary = RecordingLibraryMigration.fileURL(
            named: filename,
            in: recordingsDirectory(syncEnabled: syncEnabled, fileManager: fileManager)
        ) else { return nil }
        if RecordingFileAccess.isPresent(at: primary, fileManager: fileManager) { return primary }

        let local = localDirectory(fileManager: fileManager)
        if let localURL = RecordingLibraryMigration.fileURL(named: filename, in: local),
           localURL.path != primary.path,
           RecordingFileAccess.isPresent(at: localURL, fileManager: fileManager) {
            return localURL
        }
        if let cloud = ubiquityDirectory(fileManager: fileManager),
           let cloudURL = RecordingLibraryMigration.fileURL(named: filename, in: cloud),
           cloudURL.path != primary.path,
           RecordingFileAccess.isPresent(at: cloudURL, fileManager: fileManager) {
            return cloudURL
        }
        return RecordingLibraryMigration.conflictRecordingURL(
            named: filename,
            syncEnabled: syncEnabled,
            fileManager: fileManager
        ) ?? primary
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

    /// iCloud keeps a losing copy beside the real folder (`recordings 2`) or renames a
    /// file `name 2.ext`. History still stores the original filename, so those copies
    /// are folded back before the app looks them up.
    nonisolated static func absorbConflictCopies(fileManager: FileManager = .default) {
        absorbConflicts(into: RecordingLocations.localDirectory(fileManager: fileManager), fileManager: fileManager)
        if let cloud = RecordingLocations.ubiquityDirectory(fileManager: fileManager) {
            absorbConflicts(into: cloud, fileManager: fileManager)
        }
    }

    nonisolated static func absorbConflicts(into canonical: URL, fileManager: FileManager = .default) {
        let parent = canonical.deletingLastPathComponent()
        let names = (try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names.sorted() where isNumberedConflictName(name, of: "recordings") {
            guard isSafeFilename(name) else { continue }
            let source = parent.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            _ = moveRecordings(from: source, to: canonical, fileManager: fileManager)
            let leftover = (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? ["kept"]
            if leftover.isEmpty {
                try? fileManager.removeItem(at: source)
            }
        }
        renameNumberedFiles(in: canonical, fileManager: fileManager)
    }

    nonisolated static func conflictRecordingURL(
        named filename: String,
        syncEnabled: Bool,
        fileManager: FileManager
    ) -> URL? {
        let directories = searchDirectories(syncEnabled: syncEnabled, fileManager: fileManager)
        for directory in directories {
            guard let url = fileURL(named: filename, in: directory),
                  RecordingFileAccess.isPresent(at: url, fileManager: fileManager) else { continue }
            return url
        }
        for directory in directories {
            let names = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
            for name in names where isConflictFile(named: name, of: filename) {
                guard let url = fileURL(named: name, in: directory),
                      RecordingFileAccess.isPresent(at: url, fileManager: fileManager) else { continue }
                return url
            }
        }
        return nil
    }

    /// `recordings 2` and `take 2.m4a` are the names iCloud uses for a conflict.
    /// `recordings 2 3` is a conflict of a conflict. `recordings backup` is not.
    nonisolated static func isNumberedConflictName(_ candidate: String, of original: String) -> Bool {
        guard candidate.count > original.count else { return false }
        let suffix = candidate.dropFirst(original.count)
        var index = suffix.startIndex
        var groups = 0
        while index < suffix.endIndex {
            guard suffix[index] == " " else { return false }
            let digits = suffix.index(after: index)
            var cursor = digits
            while cursor < suffix.endIndex, suffix[cursor].isNumber {
                cursor = suffix.index(after: cursor)
            }
            if cursor == digits { return false }
            groups += 1
            index = cursor
        }
        return groups > 0
    }

    nonisolated static func isConflictFile(named candidate: String, of filename: String) -> Bool {
        let originalExtension = (filename as NSString).pathExtension
        let candidateExtension = (candidate as NSString).pathExtension
        guard originalExtension == candidateExtension else { return false }
        return isNumberedConflictName(
            (candidate as NSString).deletingPathExtension,
            of: (filename as NSString).deletingPathExtension
        )
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

    nonisolated private static func searchDirectories(
        syncEnabled: Bool,
        fileManager: FileManager
    ) -> [URL] {
        var ordered: [URL] = []
        func add(_ url: URL?) {
            guard let url else { return }
            let path = url.standardizedFileURL.path
            guard !ordered.contains(where: { $0.standardizedFileURL.path == path }) else { return }
            ordered.append(url)
        }
        add(RecordingLocations.recordingsDirectory(syncEnabled: syncEnabled, fileManager: fileManager))
        add(RecordingLocations.localDirectory(fileManager: fileManager))
        add(RecordingLocations.ubiquityDirectory(fileManager: fileManager))
        let seeds = ordered
        for directory in seeds {
            let parent = directory.deletingLastPathComponent()
            let names = (try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? []
            for name in names.sorted() where isNumberedConflictName(name, of: "recordings") && isSafeFilename(name) {
                add(parent.appendingPathComponent(name, isDirectory: true))
            }
        }
        return ordered
    }

    nonisolated private static func renameNumberedFiles(in directory: URL, fileManager: FileManager) {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted() {
            guard let canonical = unnumberedFilename(name), isSafeFilename(canonical), isSafeFilename(name),
                  let from = fileURL(named: name, in: directory),
                  let to = fileURL(named: canonical, in: directory),
                  !fileManager.fileExists(atPath: to.path) else { continue }
            do {
                try fileManager.moveItem(at: from, to: to)
                RecordingStorage.protect(to)
            } catch {
                continue
            }
        }
    }

    /// `take 2.m4a` and `take 2 3.m4a` both belong to `take.m4a`.
    nonisolated private static func unnumberedFilename(_ name: String) -> String? {
        let ext = (name as NSString).pathExtension
        var base = (name as NSString).deletingPathExtension
        var changed = false
        while let space = base.lastIndex(of: " ") {
            let suffix = base[base.index(after: space)...]
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { break }
            base = String(base[..<space])
            changed = true
        }
        guard changed, !base.isEmpty else { return nil }
        return ext.isEmpty ? base : base + "." + ext
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
        guard isPresent(at: url, fileManager: fileManager) else { return .missing }
        if isUbiquitous, (values?.fileSize ?? 0) == 0 {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            return .downloading
        }
        return .ready
    }

    /// `fileExists` reports false for a take that was just written into iCloud until the
    /// next launch. A reachable URL, or a downloaded ubiquitous item, is the file on disk.
    nonisolated static func isPresent(at url: URL, fileManager: FileManager = .default) -> Bool {
        if fileManager.fileExists(atPath: url.path) { return true }
        if (try? url.checkResourceIsReachable()) == true { return true }
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .fileSizeKey,
        ])
        guard values?.isUbiquitousItem == true else { return false }
        switch values?.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return true
        default:
            return (values?.fileSize ?? 0) > 0
        }
    }
}

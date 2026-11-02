import Foundation
import Testing
@testable import VoiceBlogger

struct ICloudSyncTests {
    private func isolatedDefaults() -> UserDefaults {
        let name = "icloud-sync-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func setupCannotFinishUntilAChoiceIsStored() {
        let defaults = isolatedDefaults()

        #expect(!ICloudSyncSettings.canFinishSetup(defaults: defaults))
        #expect(!ICloudSyncSettings.hasChosen(defaults: defaults))
        #expect(!ICloudSyncSettings.isEnabled(defaults: defaults))

        let local = ICloudSyncSettings.applyChoice(enable: false, accountAvailable: true, defaults: defaults)
        #expect(local.message == nil)
        #expect(local.enabled == false)
        #expect(ICloudSyncSettings.canFinishSetup(defaults: defaults))
        #expect(!ICloudSyncSettings.isEnabled(defaults: defaults))
    }

    @Test func enablingSyncPersistsTheChoice() {
        let defaults = isolatedDefaults()

        let cloud = ICloudSyncSettings.applyChoice(enable: true, accountAvailable: true, defaults: defaults)
        #expect(cloud.message == nil)
        #expect(ICloudSyncSettings.isEnabled(defaults: defaults))
        #expect(ICloudSyncSettings.canFinishSetup(defaults: defaults))
    }

    @Test func missingICloudAccountDoesNotEnableSync() {
        let defaults = isolatedDefaults()
        ICloudSyncSettings.applyChoice(enable: false, accountAvailable: true, defaults: defaults)

        let denied = ICloudSyncSettings.applyChoice(enable: true, accountAvailable: false, defaults: defaults)
        #expect(denied.message == ICloudSyncSettings.unavailableMessage)
        #expect(!ICloudSyncSettings.isEnabled(defaults: defaults))
        #expect(ICloudSyncSettings.canFinishSetup(defaults: defaults))
    }

    @Test func missingICloudAccountDoesNotCountAsAFirstChoice() {
        let defaults = isolatedDefaults()

        let denied = ICloudSyncSettings.applyChoice(enable: true, accountAvailable: false, defaults: defaults)
        #expect(denied.message == ICloudSyncSettings.unavailableMessage)
        #expect(!ICloudSyncSettings.isEnabled(defaults: defaults))
        #expect(!ICloudSyncSettings.canFinishSetup(defaults: defaults))
    }

    @Test func configurationSelectsPrivateCloudKitDatabaseOnlyWhenEnabled() {
        #expect(LibraryCloudDatabase.selection(syncEnabled: false) == .none)
        #expect(
            LibraryCloudDatabase.selection(syncEnabled: true)
                == .privateDatabase(ICloudSyncSettings.containerIdentifier)
        )
        #expect(ICloudSyncSettings.containerIdentifier == "iCloud.anup.VoiceBlogger")
    }

    @Test func storeProtectionRelaxesOnlyWhileSyncIsOn() {
        #expect(LibraryStoreProtection.fileProtection(syncEnabled: false) == .complete)
        #expect(
            LibraryStoreProtection.fileProtection(syncEnabled: true)
                == .completeUntilFirstUserAuthentication
        )
    }

    @Test func recordingMoveRefusesPathsThatEscapeTheRecordingsFolder() {
        let recordings = FileManager.default.temporaryDirectory
            .appendingPathComponent("recordings-\(UUID().uuidString)", isDirectory: true)
        #expect(RecordingLibraryMigration.fileURL(named: "../huggingface/model.bin", in: recordings) == nil)
        #expect(RecordingLibraryMigration.fileURL(named: "nested/take.m4a", in: recordings) == nil)
        #expect(!RecordingLibraryMigration.isSafeFilename(".."))
        #expect(!RecordingLibraryMigration.isSafeFilename("."))
        #expect(RecordingLibraryMigration.fileURL(named: "take.m4a", in: recordings)?.lastPathComponent == "take.m4a")
    }

    @Test func recordingMoveTransfersOnlyTheRecordingsDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-\(UUID().uuidString)", isDirectory: true)
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        let models = root.appendingPathComponent("huggingface", isDirectory: true)
        let destination = root.appendingPathComponent("cloud-recordings", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: models, withIntermediateDirectories: true)
        let audio = recordings.appendingPathComponent("take.m4a")
        let weights = models.appendingPathComponent("model.bin")
        try Data("audio".utf8).write(to: audio)
        try Data("weights".utf8).write(to: weights)

        let moved = RecordingLibraryMigration.moveRecordings(from: recordings, to: destination, fileManager: fileManager)

        #expect(moved.moved == ["take.m4a"])
        #expect(moved.copied.isEmpty)
        #expect(!fileManager.fileExists(atPath: audio.path))
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("take.m4a").path))
        #expect(fileManager.fileExists(atPath: weights.path))
        #expect(!fileManager.fileExists(atPath: destination.appendingPathComponent("model.bin").path))

        let copied = RecordingLibraryMigration.copyRecordings(from: destination, to: recordings, fileManager: fileManager)
        #expect(copied.copied == ["take.m4a"])
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("take.m4a").path))
        #expect(fileManager.fileExists(atPath: audio.path))

        try fileManager.removeItem(at: root)
    }

    @Test func localFileIsReadyAndMissingFileIsMissing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("take.m4a")
        try Data("audio".utf8).write(to: audio)

        #expect(RecordingFileAccess.readiness(at: audio) == .ready)
        #expect(RecordingFileAccess.readiness(at: folder.appendingPathComponent("gone.m4a")) == .missing)
        #expect(RecordingReadiness.ready.unavailableMessage == nil)
        #expect(RecordingReadiness.downloading.unavailableMessage == "This recording is still downloading from iCloud.")
        #expect(RecordingReadiness.missing.unavailableMessage == "Could not find this recording on this device.")

        try FileManager.default.removeItem(at: folder)
    }

    @Test func resolveRecordingURLFindsATakeWrittenBeforeTheContainerWasReady() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolve-\(UUID().uuidString)", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let container = root.appendingPathComponent("iCloud", isDirectory: true)
        let fileManager = FixedUbiquityFileManager(documents: documents, container: container)
        let filename = "take.m4a"
        let local = documents
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(filename)
        try fileManager.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: local)
        RecordingLocations.resetUbiquityCache()
        defer {
            RecordingLocations.resetUbiquityCache()
            try? FileManager.default.removeItem(at: root)
        }

        let resolved = RecordingLocations.resolveRecordingURL(
            named: filename,
            syncEnabled: true,
            fileManager: fileManager
        )

        #expect(resolved?.path == local.path)
        #expect(RecordingFileAccess.isPresent(at: local, fileManager: fileManager))
    }

    @Test func conflictNamesMatchOnlyNumberedCopies() {
        #expect(RecordingLibraryMigration.isNumberedConflictName("recordings 2", of: "recordings"))
        #expect(RecordingLibraryMigration.isNumberedConflictName("recordings 2 3", of: "recordings"))
        #expect(!RecordingLibraryMigration.isNumberedConflictName("recordings", of: "recordings"))
        #expect(!RecordingLibraryMigration.isNumberedConflictName("recordings backup", of: "recordings"))
        #expect(RecordingLibraryMigration.isConflictFile(named: "take 2.m4a", of: "take.m4a"))
        #expect(RecordingLibraryMigration.isConflictFile(named: "take 2 3.m4a", of: "take.m4a"))
        #expect(!RecordingLibraryMigration.isConflictFile(named: "take 2.caf", of: "take.m4a"))
        #expect(!RecordingLibraryMigration.isConflictFile(named: "take-notes.m4a", of: "take.m4a"))
    }

    @Test func conflictFolderAndNumberedFileAreFoldedBackIntoRecordings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conflicts-\(UUID().uuidString)", isDirectory: true)
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        let conflict = root.appendingPathComponent("recordings 2", isDirectory: true)
        let nested = root.appendingPathComponent("recordings 2 3", isDirectory: true)
        let backup = root.appendingPathComponent("recordings backup", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: conflict, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("from-conflict".utf8).write(to: conflict.appendingPathComponent("take.m4a"))
        try Data("from-nested".utf8).write(to: nested.appendingPathComponent("nested.m4a"))
        try Data("numbered".utf8).write(to: recordings.appendingPathComponent("other 2.m4a"))
        try Data("double".utf8).write(to: recordings.appendingPathComponent("double 2 3.caf"))
        try Data("canonical".utf8).write(to: recordings.appendingPathComponent("both.m4a"))
        try Data("duplicate".utf8).write(to: recordings.appendingPathComponent("both 2.m4a"))
        try Data("leave".utf8).write(to: backup.appendingPathComponent("model.bin"))
        defer { try? fileManager.removeItem(at: root) }

        RecordingLibraryMigration.absorbConflicts(into: recordings, fileManager: fileManager)

        #expect(try Data(contentsOf: recordings.appendingPathComponent("take.m4a")) == Data("from-conflict".utf8))
        #expect(try Data(contentsOf: recordings.appendingPathComponent("nested.m4a")) == Data("from-nested".utf8))
        #expect(try Data(contentsOf: recordings.appendingPathComponent("other.m4a")) == Data("numbered".utf8))
        #expect(try Data(contentsOf: recordings.appendingPathComponent("double.caf")) == Data("double".utf8))
        #expect(try Data(contentsOf: recordings.appendingPathComponent("both.m4a")) == Data("canonical".utf8))
        #expect(fileManager.fileExists(atPath: recordings.appendingPathComponent("both 2.m4a").path))
        #expect(!fileManager.fileExists(atPath: recordings.appendingPathComponent("other 2.m4a").path))
        #expect(!fileManager.fileExists(atPath: conflict.path))
        #expect(!fileManager.fileExists(atPath: nested.path))
        #expect(fileManager.fileExists(atPath: backup.appendingPathComponent("model.bin").path))
    }

    @Test func resolveRecordingURLFindsConflictFolderAndNumberedFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolve-conflict-\(UUID().uuidString)", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let container = root.appendingPathComponent("iCloud", isDirectory: true)
        let fileManager = FixedUbiquityFileManager(documents: documents, container: container)
        let cloudDocuments = container.appendingPathComponent("Documents", isDirectory: true)
        let conflict = cloudDocuments.appendingPathComponent("recordings 2", isDirectory: true)
        let recordings = cloudDocuments.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: conflict, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
        let folded = conflict.appendingPathComponent("folded.m4a")
        let numbered = recordings.appendingPathComponent("numbered 2.m4a")
        try Data("folded".utf8).write(to: folded)
        try Data("numbered".utf8).write(to: numbered)
        RecordingLocations.resetUbiquityCache()
        defer {
            RecordingLocations.resetUbiquityCache()
            try? FileManager.default.removeItem(at: root)
        }

        let foldedURL = RecordingLocations.resolveRecordingURL(
            named: "folded.m4a",
            syncEnabled: true,
            fileManager: fileManager
        )
        let numberedURL = RecordingLocations.resolveRecordingURL(
            named: "numbered.m4a",
            syncEnabled: true,
            fileManager: fileManager
        )

        #expect(foldedURL?.path == folded.path)
        #expect(numberedURL?.path == numbered.path)
    }

    @Test func recordingsStayLocalWhenTheUbiquityContainerIsUnavailable() {
        let fileManager = UbiquityDeniedFileManager()
        RecordingLocations.resetUbiquityCache()
        defer { RecordingLocations.resetUbiquityCache() }

        #expect(RecordingLocations.ubiquityDirectory(fileManager: fileManager) == nil)
        #expect(
            RecordingLocations.recordingsDirectory(syncEnabled: true, fileManager: fileManager)
                == RecordingLocations.localDirectory(fileManager: fileManager)
        )
    }
}

private final class UbiquityDeniedFileManager: FileManager, @unchecked Sendable {
    override func url(forUbiquityContainerIdentifier identifier: String?) -> URL? {
        nil
    }
}

private final class FixedUbiquityFileManager: FileManager, @unchecked Sendable {
    let documents: URL
    let container: URL

    init(documents: URL, container: URL) {
        self.documents = documents
        self.container = container
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .documentDirectory { return [documents] }
        return super.urls(for: directory, in: domainMask)
    }

    override func url(forUbiquityContainerIdentifier identifier: String?) -> URL? {
        container
    }
}

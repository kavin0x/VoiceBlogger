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

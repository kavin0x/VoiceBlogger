import CloudKit
import Foundation
import SwiftData

enum ICloudAccount: Sendable {
    nonisolated static func isAvailable(
        containerIdentifier: String = ICloudSyncSettings.containerIdentifier
    ) async -> Bool {
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}

struct OpenedLibrary {
    var container: ModelContainer
    var usingCloudKit: Bool
    var fallbackMessage: String?
}

enum LibraryContainerFactory {
    static var storeURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("VoiceBlogger-v2.store")
    }

    static func open(syncEnabled: Bool) -> OpenedLibrary {
        if syncEnabled {
            do {
                let container = try makeContainer(syncEnabled: true)
                return OpenedLibrary(container: container, usingCloudKit: true, fallbackMessage: nil)
            } catch {
                do {
                    let container = try makeContainer(syncEnabled: false)
                    return OpenedLibrary(
                        container: container,
                        usingCloudKit: false,
                        fallbackMessage: "iCloud sync could not start (\(error.localizedDescription)). Your library stays on this device for now and will try again the next time you open Voice Blogger."
                    )
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }

        do {
            let container = try makeContainer(syncEnabled: false)
            return OpenedLibrary(container: container, usingCloudKit: false, fallbackMessage: nil)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    static func makeContainer(syncEnabled: Bool) throws -> ModelContainer {
        let schema = Schema([BlogPost.self, CustomVocabularyEntry.self, CustomDictationMode.self])
        let storeURL = storeURL
        let database = LibraryCloudDatabase.selection(syncEnabled: syncEnabled).cloudKitDatabase
        let config = ModelConfiguration(
            "VoiceBloggerV2",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: database
        )
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            container = try ModelContainer(for: schema, configurations: [config])
        }
        applyDataProtection(to: storeURL, syncEnabled: syncEnabled)
        return container
    }

    private static func applyDataProtection(to storeURL: URL, syncEnabled: Bool) {
        let fm = FileManager.default
        let protection = LibraryStoreProtection.fileProtection(syncEnabled: syncEnabled)
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent(storeURL.lastPathComponent + suffix)
            guard fm.fileExists(atPath: fileURL.path) else { continue }
            try? fm.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: fileURL.path
            )
        }
    }
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var container: ModelContainer
    private(set) var generation = UUID()
    var syncError: String?

    init() {
        if ICloudSyncSettings.isEnabled() {
            RecordingLibraryMigration.moveLocalRecordingsIntoUbiquity()
        }
        let opened = LibraryContainerFactory.open(syncEnabled: ICloudSyncSettings.isEnabled())
        container = opened.container
        if ICloudSyncSettings.isEnabled() && !opened.usingCloudKit {
            syncError = opened.fallbackMessage
        }
    }

    /// Stores the choice and points new recordings at the matching folder.
    /// Returns a message when iCloud was requested but the account is unavailable.
    /// A CloudKit open failure still keeps the choice and is reported through `syncError`.
    func updateSync(enabled: Bool, accountAvailable: Bool) -> String? {
        let decision = ICloudSyncSettings.applyChoice(enable: enabled, accountAvailable: accountAvailable)
        if let message = decision.message {
            return message
        }
        if decision.enabled {
            RecordingLibraryMigration.moveLocalRecordingsIntoUbiquity()
        } else {
            RecordingLibraryMigration.copyUbiquityRecordingsToLocal()
        }
        // The open ModelContainer keeps serving this session. The next launch opens the same
        // store with or without CloudKit so rows are not copied into a second database.
        return nil
    }

    func consumeSyncError() -> String? {
        let message = syncError
        syncError = nil
        return message
    }
}

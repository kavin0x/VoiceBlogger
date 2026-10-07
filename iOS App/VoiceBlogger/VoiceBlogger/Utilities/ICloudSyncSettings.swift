import Foundation
import SwiftData

/// Opt-in iCloud sync for the library. Models stay on each device.
enum ICloudSyncSettings: Sendable {
    nonisolated static let containerIdentifier = "iCloud.anup.VoiceBlogger"
    nonisolated static let enabledKey = "iCloudSyncEnabled"
    nonisolated static let choiceMadeKey = "iCloudSyncChoiceMade"
    nonisolated static let unavailableMessage = "iCloud is signed out or restricted. Your library stays on this device."

    struct ChoiceResult: Equatable {
        var enabled: Bool
        var message: String?
    }

    nonisolated static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    nonisolated static func hasChosen(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: choiceMadeKey)
    }

    /// Setup cannot finish until the person picks on-device or iCloud.
    nonisolated static func canFinishSetup(defaults: UserDefaults = .standard) -> Bool {
        hasChosen(defaults: defaults)
    }

    /// Records a choice. A request to enable sync when the iCloud account is unavailable
    /// leaves the stored flag unchanged and does not count as a completed choice.
    nonisolated static func applyChoice(
        enable: Bool,
        accountAvailable: Bool,
        defaults: UserDefaults = .standard
    ) -> ChoiceResult {
        if enable && !accountAvailable {
            return ChoiceResult(enabled: isEnabled(defaults: defaults), message: unavailableMessage)
        }
        defaults.set(enable, forKey: enabledKey)
        defaults.set(true, forKey: choiceMadeKey)
        return ChoiceResult(enabled: enable, message: nil)
    }
}

enum LibraryCloudDatabase: Equatable, Sendable {
    case none
    case privateDatabase(String)

    nonisolated var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
        switch self {
        case .none:
            .none
        case .privateDatabase(let identifier):
            .private(identifier)
        }
    }

    nonisolated static func selection(syncEnabled: Bool) -> LibraryCloudDatabase {
        syncEnabled ? .privateDatabase(ICloudSyncSettings.containerIdentifier) : .none
    }
}

enum LibraryStoreProtection: Sendable {
    nonisolated static func fileProtection(syncEnabled: Bool) -> FileProtectionType {
        syncEnabled ? .completeUntilFirstUserAuthentication : .complete
    }
}

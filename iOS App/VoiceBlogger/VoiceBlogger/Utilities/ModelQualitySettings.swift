import Foundation

/// User-selectable model quality tier (model names are not shown in UI).
enum ModelQualityLevel: String, CaseIterable, Codable, Sendable {
    case high
    case medium
    case low

    private static let storageKey = "modelQualityLevel"
    private static let lockedKey = "modelQualityLevelLocked"

    /// Default for new installs based on device RAM.
    static var recommended: ModelQualityLevel {
        switch DeviceRAMTier.current {
        case .ample: return .high
        case .standard: return .medium
        case .constrained: return .low
        }
    }

    /// Current quality level. Existing users with downloaded models keep medium unless they opt in.
    static var current: ModelQualityLevel {
        if UserDefaults.standard.bool(forKey: lockedKey),
           let raw = UserDefaults.standard.string(forKey: storageKey),
           let level = ModelQualityLevel(rawValue: raw) {
            return level
        }
        if UserDefaults.standard.bool(forKey: "whisperModelReady_v4") {
            lockExistingInstall(to: .medium)
            return .medium
        }
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let level = ModelQualityLevel(rawValue: raw) {
            return level
        }
        return recommended
    }

    static func select(_ level: ModelQualityLevel, forNewInstall: Bool) {
        guard forNewInstall || !UserDefaults.standard.bool(forKey: lockedKey) else { return }
        UserDefaults.standard.set(level.rawValue, forKey: storageKey)
    }

    static func lockExistingInstall(to level: ModelQualityLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: storageKey)
        UserDefaults.standard.set(true, forKey: lockedKey)
    }

    var displayName: String {
        switch self {
        case .high: return "High Quality"
        case .medium: return "Balanced"
        case .low: return "Compact"
        }
    }

    var subtitle: String {
        switch self {
        case .high: return "Best accuracy · ~3.2 GB"
        case .medium: return "Recommended · ~2.5 GB"
        case .low: return "Faster download · ~1.7 GB"
        }
    }

    var tagline: String {
        switch self {
        case .high: return "Best accuracy"
        case .medium: return "Recommended for most devices"
        case .low: return "Faster download, lowest accuracy"
        }
    }

    var whisperModelID: String {
        switch self {
        case .high: return "openai_whisper-large-v3-turbo"
        case .medium: return "openai_whisper-medium"
        case .low: return "openai_whisper-small"
        }
    }

    var llmModelID: String {
        switch self {
        case .high: return "mlx-community/Qwen2.5-3B-Instruct-4bit"
        case .medium, .low: return "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        }
    }

    var whisperDownloadSizeLabel: String {
        switch self {
        case .high: return "~2.0 GB"
        case .medium: return "~1.5 GB"
        case .low: return "~0.7 GB"
        }
    }

    var llmDownloadSizeLabel: String {
        switch self {
        case .high: return "~1.8 GB"
        case .medium, .low: return "~1.0 GB"
        }
    }

    var totalDownloadSizeLabel: String {
        switch self {
        case .high: return "~3.2 GB"
        case .medium: return "~2.5 GB"
        case .low: return "~1.7 GB"
        }
    }
}

/// Resolved model IDs for the active quality tier.
enum ModelIDs {
    static var whisper: String { ModelQualityLevel.current.whisperModelID }
    static var llm: String { ModelQualityLevel.current.llmModelID }
}

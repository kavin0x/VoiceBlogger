import Foundation

/// User-selectable model quality tier (model names are not shown in UI).
nonisolated enum ModelQualityLevel: String, CaseIterable, Codable, Sendable {
    case high
    case medium
    case low

    private static let storageKey = "modelQualityLevel"
    private static let lockedKey = "modelQualityLevelLocked"

    /// Default for new installs based on device RAM.
    static var recommended: ModelQualityLevel {
        recommended(for: DeviceRAMTier.current)
    }

    static func recommended(for tier: DeviceRAMTier) -> ModelQualityLevel {
        switch tier {
        case .ample: return .high
        case .standard: return .medium
        case .constrained: return .low
        }
    }

    /// Smallest RAM tier that can load this quality without a jetsam kill.
    var minimumRAMTier: DeviceRAMTier {
        switch self {
        case .high: return .ample
        case .medium: return .standard
        case .low: return .constrained
        }
    }

    func isSupported(on tier: DeviceRAMTier) -> Bool {
        tier >= minimumRAMTier
    }

    var isSupportedOnThisDevice: Bool {
        isSupported(on: DeviceRAMTier.current)
    }

    /// Falls back to the best tier this device can actually run.
    static func clamped(_ level: ModelQualityLevel, to tier: DeviceRAMTier) -> ModelQualityLevel {
        level.isSupported(on: tier) ? level : recommended(for: tier)
    }

    var unavailableReason: String? {
        guard !isSupportedOnThisDevice else { return nil }
        switch self {
        case .high:
            return String(localized: "Needs a device with more memory")
        case .medium:
            return String(localized: "Too large for this device")
        case .low:
            return nil
        }
    }

    /// MLX allocator ceiling. The 3B High Quality weights already occupy ~2 GB,
    /// so the cache stays smaller than the tier default to avoid a jetsam kill.
    func mlxCacheLimitBytes(on tier: DeviceRAMTier) -> Int {
        switch self {
        case .high:
            return 512 * 1024 * 1024
        case .medium, .low:
            return tier.mlxCacheLimitBytes
        }
    }

    static func minimumTier(forWhisperModelID id: String) -> DeviceRAMTier {
        if let known = ModelQualityLevel.allCases.first(where: { $0.whisperModelID == id }) {
            return known.minimumRAMTier
        }
        let lower = id.lowercased()
        if lower.contains("large") { return .ample }
        if lower.contains("medium") { return .standard }
        return .constrained
    }

    static func isSafeToLoad(whisperModelID id: String, on tier: DeviceRAMTier) -> Bool {
        tier >= minimumTier(forWhisperModelID: id)
    }

    static func minimumTier(forLLMModelID id: String) -> DeviceRAMTier {
        if id == ModelQualityLevel.high.llmModelID { return .ample }
        let lower = id.lowercased()
        if lower.contains("3b") || lower.contains("7b") || lower.contains("8b")
            || lower.contains("14b") || lower.contains("32b") || lower.contains("70b") {
            return .ample
        }
        return .constrained
    }

    static func isSafeToLoad(llmModelID id: String, on tier: DeviceRAMTier) -> Bool {
        tier >= minimumTier(forLLMModelID: id)
    }

    /// Current quality level. Existing users with downloaded models keep medium unless they opt in.
    /// A stored High Quality choice on a phone that cannot run it is rewritten to a safe tier
    /// before any model load, so the next launch does not jetsam.
    static var current: ModelQualityLevel {
        let decision = ModelQualityResolution.decide(
            ModelQualityResolution.Input(
                tier: DeviceRAMTier.current,
                storedRaw: UserDefaults.standard.string(forKey: storageKey),
                isLocked: UserDefaults.standard.bool(forKey: lockedKey),
                whisperReady: UserDefaults.standard.bool(forKey: "whisperModelReady_v4")
            )
        )
        if decision.shouldPersist {
            lockExistingInstall(to: decision.level)
        }
        return decision.level
    }

    static func select(_ level: ModelQualityLevel, forNewInstall: Bool) {
        let safe = clamped(level, to: DeviceRAMTier.current)
        let locked = UserDefaults.standard.bool(forKey: lockedKey)
        if locked && !forNewInstall {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let stored = ModelQualityLevel(rawValue: raw),
               !stored.isSupported(on: DeviceRAMTier.current) {
                lockExistingInstall(to: safe)
            }
            return
        }
        lockExistingInstall(to: safe)
    }

    static func lockExistingInstall(to level: ModelQualityLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: storageKey)
        UserDefaults.standard.set(true, forKey: lockedKey)
    }

    var displayName: String {
        switch self {
        case .high: return String(localized: "High Quality")
        case .medium: return String(localized: "Balanced")
        case .low: return String(localized: "Compact")
        }
    }

    var subtitle: String {
        switch self {
        case .high: return String(localized: "Best accuracy · ~2.4 GB")
        case .medium: return String(localized: "Recommended · ~2.5 GB")
        case .low: return String(localized: "Faster download · ~1.7 GB")
        }
    }

    var tagline: String {
        switch self {
        case .high: return String(localized: "Best accuracy")
        case .medium: return String(localized: "Recommended for most devices")
        case .low: return String(localized: "Faster download, lowest accuracy")
        }
    }

    var whisperModelID: String {
        switch self {
        case .high: return "openai_whisper-large-v3-v20240930_turbo_632MB"
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
        case .high: return String(localized: "~0.6 GB")
        case .medium: return String(localized: "~1.5 GB")
        case .low: return String(localized: "~0.7 GB")
        }
    }

    var llmDownloadSizeLabel: String {
        switch self {
        case .high: return String(localized: "~1.8 GB")
        case .medium, .low: return String(localized: "~1.0 GB")
        }
    }

    var totalDownloadSizeLabel: String {
        switch self {
        case .high: return String(localized: "~2.4 GB")
        case .medium: return String(localized: "~2.5 GB")
        case .low: return String(localized: "~1.7 GB")
        }
    }
}

/// Resolved model IDs for the active quality tier.
enum ModelIDs {
    static var whisper: String { ModelQualityLevel.current.whisperModelID }
    static var llm: String { ModelQualityLevel.current.llmModelID }
}

/// Pure quality selection. Reading `ModelQualityLevel.current` applies the decision
/// and persists a clamp so an oversized choice cannot survive until the next launch.
nonisolated enum ModelQualityResolution {
    struct Input: Equatable, Sendable {
        var tier: DeviceRAMTier
        var storedRaw: String?
        var isLocked: Bool
        var whisperReady: Bool
    }

    struct Decision: Equatable, Sendable {
        var level: ModelQualityLevel
        /// Rewrite UserDefaults when the stored choice is missing a lock or is too large.
        var shouldPersist: Bool
    }

    static func decide(_ input: Input) -> Decision {
        if let stored = input.storedRaw.flatMap(ModelQualityLevel.init(rawValue:)) {
            let safe = ModelQualityLevel.clamped(stored, to: input.tier)
            let needsWrite = safe != stored || !input.isLocked
            return Decision(level: safe, shouldPersist: needsWrite)
        }

        if input.whisperReady {
            // Installs from before the picker existed stay on Balanced, unless Balanced
            // itself does not fit (phones under 3 GiB), in which case they get Compact.
            let legacy = ModelQualityLevel.clamped(.medium, to: input.tier)
            return Decision(level: legacy, shouldPersist: true)
        }

        return Decision(level: ModelQualityLevel.recommended(for: input.tier), shouldPersist: false)
    }
}

/// Free memory that must exist before a model is compiled or deserialized.
/// The requirement is not lowered on retry. Starting a load below the model's
/// footprint is a jetsam kill, which App Store Connect reports with no app log.
nonisolated enum ModelMemoryBudget {
    static func llmLoadMegabytes(for level: ModelQualityLevel) -> Int {
        switch level {
        case .high: return 2400
        case .medium, .low: return 1100
        }
    }

    static func whisperCompileMegabytes(for level: ModelQualityLevel) -> Int {
        switch level {
        case .high: return 1600
        case .medium: return 1100
        case .low: return 600
        }
    }

    /// `availableBytes == 0` means the OS did not report a limit (simulator).
    /// On device, a short reading must fail closed at the full requirement.
    static func allowsLoad(availableBytes: UInt64, requiredMB: Int) -> Bool {
        guard availableBytes > 0 else { return true }
        guard requiredMB > 0 else { return true }
        return availableBytes >= UInt64(requiredMB) * 1024 * 1024
    }
}

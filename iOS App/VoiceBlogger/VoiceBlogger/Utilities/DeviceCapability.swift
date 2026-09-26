import Foundation
import os

// Classifies device RAM tier so model loading can adapt cache limits and
// compute backend choices without hard-coded device name lists.
//
// Buckets use reported gibibytes (ProcessInfo.physicalMemory), which is lower
// than the marketed gigabyte figure. A 6 GB iPhone typically reports ~5.5 GiB
// and stays `.standard`. High Quality (3B) is limited to `.ample` (>= 7 GiB,
// marketed 8 GB and up) because loading it on smaller phones is a jetsam kill.
nonisolated enum DeviceRAMTier: Comparable, Sendable {
    case constrained   // < 3 GiB reported   (2–3 GB marketed: iPhone SE, XR)
    case standard      // 3–6 GiB reported   (4–6 GB marketed: iPhone 11–15)
    case ample         // >= 7 GiB reported  (8 GB marketed and up)

    static let current: DeviceRAMTier = tier(forPhysicalRAMBytes: physicalRAMBytes)

    static func tier(forPhysicalRAMBytes bytes: UInt64) -> DeviceRAMTier {
        let gib = bytes / (1024 * 1024 * 1024)
        switch gib {
        case ..<3: return .constrained
        case 3..<7: return .standard
        default: return .ample
        }
    }

    private var sortOrder: Int {
        switch self {
        case .constrained: return 0
        case .standard: return 1
        case .ample: return 2
        }
    }

    static func < (lhs: DeviceRAMTier, rhs: DeviceRAMTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private static var physicalRAMBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    // MLX KV-cache limit appropriate for this tier.
    // Constrained: 512 MB  — leaves headroom for CoreML and the OS
    // Standard:    768 MB  — current default, safe for Qwen2.5-1.5B
    // Ample:       1024 MB — allows longer context without eviction pressure
    var mlxCacheLimitBytes: Int {
        switch self {
        case .constrained: return 512 * 1024 * 1024
        case .standard:    return 768 * 1024 * 1024
        case .ample:       return 1024 * 1024 * 1024
        }
    }
}

// Returns the number of bytes that os_proc_available_memory() reports right now.
// os_proc_available_memory() returns size_t (Int on 64-bit iOS). Returns 0 on simulator.
func availableMemoryBytes() -> UInt64 {
    let raw = os_proc_available_memory()
    guard raw > 0 else { return 0 }
    return UInt64(raw)
}

// Returns true if there is at least `requiredMB` MB of headroom before loading
// a model. On constrained or moderate-RAM devices this prevents OOM kills when
// both Whisper and the LLM would otherwise be resident simultaneously.
func hasAvailableMemory(requiredMB: Int) -> Bool {
    let available = availableMemoryBytes()
    guard available > 0 else { return true }  // unknown — optimistic
    return available >= UInt64(requiredMB) * 1024 * 1024
}

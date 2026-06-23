import Foundation
import os

// Classifies device RAM tier so model loading can adapt cache limits and
// compute backend choices without hard-coded device name lists.
enum DeviceRAMTier {
    case constrained   // < 3 GB physical RAM  (iPhone SE, older iPads)
    case standard      // 3–5 GB              (iPhone 12/13/14, iPad base)
    case ample         // > 5 GB              (iPhone 15 Pro/Max, M-chip iPads)

    static let current: DeviceRAMTier = {
        let gb = physicalRAMBytes / (1024 * 1024 * 1024)
        switch gb {
        case ..<3:  return .constrained
        case 3..<6: return .standard
        default:    return .ample
        }
    }()

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

import Foundation

enum MLXMetalStartup {
    /// Non-empty GPU architecture for `MLX_METAL_GPU_ARCH`. MLX aborts if it has to
    /// read a Metal name whose UTF-8 pointer is NULL, which happens on iOS 27 and Mac
    /// regardless of which quality tier was selected.
    nonisolated static func resolvedArchitecture(reported: String?, runningOnMac: Bool) -> String {
        MLXMetalResolvedArchitecture(reported, runningOnMac)
    }

    nonisolated static func installIfNeeded() {
        MLXMetalInstallStartupGuard()
    }
}

import Foundation
import os

/// DEBUG-only timing logs for on-device model loading. Filter Xcode Console with `ModelLoad`.
enum ModelLoadDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoiceBlogger",
        category: "ModelLoad"
    )

    static func timed<T>(_ operation: String, _ work: () async throws -> T) async rethrows -> T {
        #if DEBUG
        let start = ContinuousClock.now
        do {
            let result = try await work()
            let elapsed = ContinuousClock.now - start
            logger.info("\(operation, privacy: .public) finished in \(formatted(elapsed), privacy: .public)")
            return result
        } catch {
            let elapsed = ContinuousClock.now - start
            logger.error("\(operation, privacy: .public) failed after \(formatted(elapsed), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
        #else
        return try await work()
        #endif
    }

    #if DEBUG
    private static func formatted(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        return String(format: "%.2fs", seconds)
    }
    #endif
}

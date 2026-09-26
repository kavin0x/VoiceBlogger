import Foundation
import Network

enum DownloadNetworkPolicy: Sendable {
    nonisolated static let wifiOnlyDefaultsKey = "wifiOnlyDownloads"
    nonisolated static let blockedMessage = "Wi-Fi only downloads is on. Connect to Wi-Fi and tap Retry."

    nonisolated static var wifiOnlyEnabled: Bool {
        UserDefaults.standard.bool(forKey: wifiOnlyDefaultsKey)
    }

    nonisolated static func applyNetworkAccess(to config: URLSessionConfiguration, wifiOnly: Bool) {
        config.allowsCellularAccess = !wifiOnly
        config.allowsExpensiveNetworkAccess = !wifiOnly
        config.allowsConstrainedNetworkAccess = !wifiOnly
    }

    /// True when the user asked for Wi-Fi only and the current path is cellular or marked expensive.
    nonisolated static func blockedByWifiOnlySetting() async -> Bool {
        guard wifiOnlyEnabled else { return false }
        return await currentPathDisallowsWifiOnlyDownload()
    }

    nonisolated private static func currentPathDisallowsWifiOnlyDownload() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.voiceblogger.wifi-only")
            let resumed = ResumeOnce()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                let blocked = path.status != .satisfied
                    || path.usesInterfaceType(.cellular)
                    || path.isExpensive
                resumed.resume(continuation, returning: blocked)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                monitor.cancel()
                // No path report: fail closed while Wi-Fi only is on.
                resumed.resume(continuation, returning: true)
            }
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var didResume = false

        nonisolated init() {}

        nonisolated func resume(_ continuation: CheckedContinuation<Bool, Never>, returning value: Bool) {
            lock.lock()
            let shouldResume = !didResume
            didResume = true
            lock.unlock()
            if shouldResume {
                continuation.resume(returning: value)
            }
        }
    }
}

struct DownloadBlockedOnCellularError: LocalizedError {
    var errorDescription: String? { DownloadNetworkPolicy.blockedMessage }
}

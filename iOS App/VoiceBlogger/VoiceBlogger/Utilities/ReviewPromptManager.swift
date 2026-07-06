import StoreKit
import UIKit

enum ReviewPromptManager {
    private static let launchCountKey = "appLaunchCount"
    private static let permanentlyDismissedKey = "reviewPromptPermanentlyDismissed"
    private static let deferredAtLaunchCountKey = "reviewPromptDeferredAtLaunchCount"
    private static let launchThreshold = 15

    static var shouldShowPrompt: Bool {
        guard ProcessInfo.processInfo.environment["UI_TESTING"] == nil else { return false }
        guard !UserDefaults.standard.bool(forKey: permanentlyDismissedKey) else { return false }

        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        let deferredAt = UserDefaults.standard.integer(forKey: deferredAtLaunchCountKey)
        let nextPromptAt = max(launchThreshold, deferredAt + launchThreshold)
        return launchCount >= nextPromptAt
    }

    static func recordLaunch() {
        let count = UserDefaults.standard.integer(forKey: launchCountKey) + 1
        UserDefaults.standard.set(count, forKey: launchCountKey)
    }

    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }

    static func deferPrompt() {
        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        UserDefaults.standard.set(launchCount, forKey: deferredAtLaunchCountKey)
    }

    static func dismissPermanently() {
        UserDefaults.standard.set(true, forKey: permanentlyDismissedKey)
    }
}

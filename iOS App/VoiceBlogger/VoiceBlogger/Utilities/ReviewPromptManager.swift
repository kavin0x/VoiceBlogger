import UIKit

enum ReviewPromptManager {
    static let appStoreID = "6777303710"
    /// Opens the App Store write-review page. `AppStore.requestReview` is rate-limited
    /// and often shows nothing, so the explicit Rate button uses this link instead.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!

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

    @MainActor
    static func requestReview() {
        UIApplication.shared.open(writeReviewURL)
    }

    static func deferPrompt() {
        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        UserDefaults.standard.set(launchCount, forKey: deferredAtLaunchCountKey)
    }

    static func dismissPermanently() {
        UserDefaults.standard.set(true, forKey: permanentlyDismissedKey)
    }
}

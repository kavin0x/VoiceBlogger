import Foundation

/// Entry point for App Intents compiled into the main app target.
@MainActor
enum IntentBridge {
    static func handlePendingIntentsFromAppProcess() {
        let onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        IntentFulfillment.shared.processPendingIntents(onboardingComplete: onboardingComplete)
    }
}

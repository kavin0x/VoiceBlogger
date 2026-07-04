import UIKit

enum HapticFeedback {
    static let hapticsKey = "settingsHapticsEnabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: hapticsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: hapticsKey)
    }

    static func recordToggle() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

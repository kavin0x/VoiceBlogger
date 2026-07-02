import Foundation

/// Shared intent flags written by App Intents (main app + widget extension) and read on launch.
enum IntentStorage {
    static let appGroupID = "group.anup.VoiceBlogger"
    private static let startKey = "intentStartRecording"
    private static let stopKey = "intentStopRecording"
    private static let recordingActiveKey = "recordingActive"
    private static let darwinNotificationName = CFNotificationName("anup.VoiceBlogger.intentFlagsChanged" as CFString)

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var isAppGroupAvailable: Bool {
        defaults != nil
    }

    static func markStartRecordingPending() {
        guard let defaults else { return }
        defaults.set(true, forKey: startKey)
        postDarwinNotification()
    }

    static func markStopRecordingPending() {
        guard let defaults else { return }
        defaults.set(true, forKey: stopKey)
        postDarwinNotification()
    }

    static func hasStartRecordingPending() -> Bool {
        defaults?.bool(forKey: startKey) ?? false
    }

    static func hasStopRecordingPending() -> Bool {
        defaults?.bool(forKey: stopKey) ?? false
    }

    static func consumeStartRecordingPending() -> Bool {
        guard let defaults else { return false }
        let pending = defaults.bool(forKey: startKey)
        if pending { defaults.removeObject(forKey: startKey) }
        return pending
    }

    static func consumeStopRecordingPending() -> Bool {
        guard let defaults else { return false }
        let pending = defaults.bool(forKey: stopKey)
        if pending { defaults.removeObject(forKey: stopKey) }
        return pending
    }

    static func markRecordingActive() {
        defaults?.set(true, forKey: recordingActiveKey)
    }

    static func clearRecordingActive() {
        defaults?.removeObject(forKey: recordingActiveKey)
    }

    static func consumeRecordingActive() -> Bool {
        guard let defaults else { return false }
        let active = defaults.bool(forKey: recordingActiveKey)
        if active { defaults.removeObject(forKey: recordingActiveKey) }
        return active
    }

    static func addDarwinObserver(_ handler: @escaping () -> Void) -> UnsafeMutableRawPointer {
        let token = ObserverToken(handler: handler)
        let pointer = Unmanaged.passRetained(token).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let token = Unmanaged<ObserverToken>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async(execute: token.handler)
            },
            darwinNotificationName.rawValue,
            nil,
            .deliverImmediately
        )
        return pointer
    }

    static func removeDarwinObserver(_ pointer: UnsafeMutableRawPointer) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            darwinNotificationName,
            nil
        )
        Unmanaged<ObserverToken>.fromOpaque(pointer).release()
    }

    private static func postDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            darwinNotificationName,
            nil,
            nil,
            true
        )
    }

    private final class ObserverToken {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }
}

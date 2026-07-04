import Foundation

/// User preferences for transcription, persisted in UserDefaults.
enum TranscriptionSettings {
    private static let languageKey = "transcriptionLanguage"
    private static let translateKey = "transcriptionTranslateToEnglish"
    private static let polishKey = "transcriptionPolishEnabled"

    /// ISO 639-1 code, or nil for auto-detect.
    static var pinnedLanguage: String? {
        get {
            let value = UserDefaults.standard.string(forKey: languageKey)
            return value?.isEmpty == true ? nil : value
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: languageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageKey)
            }
        }
    }

    static var translateToEnglish: Bool {
        get { UserDefaults.standard.bool(forKey: translateKey) }
        set { UserDefaults.standard.set(newValue, forKey: translateKey) }
    }

    static var polishTranscriptEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: polishKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: polishKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: polishKey) }
    }

    static var transcriptionMode: TranscriptionMode {
        if translateToEnglish { return .translate }
        return .transcribe(language: pinnedLanguage)
    }

    /// Common languages for the picker UI.
    static let supportedLanguages: [(code: String?, label: String)] = [
        (nil, "Auto-detect"),
        ("en", "English"),
        ("hi", "Hindi"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("pt", "Portuguese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("it", "Italian"),
        ("ru", "Russian"),
        ("ta", "Tamil"),
        ("te", "Telugu"),
        ("bn", "Bengali"),
    ]

    static func languageLabel(for code: String?) -> String {
        guard let code else { return "Auto" }
        return supportedLanguages.first(where: { $0.code == code })?.label ?? code.uppercased()
    }
}

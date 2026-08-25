import Foundation

/// Target languages offered in Settings and menu bar.
/// The raw value is the BCP-47-ish code interpolated into the LLM prompt.
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    /// Human-readable name shown in the picker (displayed in that language).
    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    /// Name used inside prompts ("Translate into: ...").
    var promptName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese (简体中文)"
        case .traditionalChinese: return "Traditional Chinese (繁體中文)"
        case .japanese: return "Japanese (日本語)"
        case .korean: return "Korean (한국어)"
        case .spanish: return "Spanish (Español)"
        case .french: return "French (Français)"
        case .german: return "German (Deutsch)"
        }
    }
}

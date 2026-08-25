import Foundation

/// Available Text-to-Speech synthesis engines in Glance.
enum TTSEngine: String, Codable, CaseIterable, Identifiable {
    case edgeNeural = "edge_neural"
    case systemNative = "system_native"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .edgeNeural:
            return "Microsoft Edge Neural (Online, Natural)"
        case .systemNative:
            return "macOS System Synthesizer (Offline)"
        }
    }

    var subtitle: String {
        switch self {
        case .edgeNeural:
            return "Cloud neural voices with natural prosody and multilingual support"
        case .systemNative:
            return "Local system synthesizer; works without internet access"
        }
    }

    /// Resolves the optimal Microsoft Edge Neural voice identifier for a given target language.
    static func defaultVoice(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "en-US-JennyNeural"
        case .simplifiedChinese:
            return "zh-CN-XiaoxiaoNeural"
        case .traditionalChinese:
            return "zh-TW-HsiaoChenNeural"
        case .japanese:
            return "ja-JP-NanamiNeural"
        case .korean:
            return "ko-KR-SunHiNeural"
        case .spanish:
            return "es-ES-ElviraNeural"
        case .french:
            return "fr-FR-DeniseNeural"
        case .german:
            return "de-DE-KatjaNeural"
        }
    }

    /// Locale identifier for macOS native AVSpeechSynthesisVoice.
    static func bcp47Locale(for language: AppLanguage) -> String {
        switch language {
        case .english: return "en-US"
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        }
    }
}

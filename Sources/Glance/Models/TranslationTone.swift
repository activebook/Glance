import Foundation

/// Distinctive translation personas and functional styles in Glance.
enum TranslationTone: String, CaseIterable, Codable, Identifiable {
    case natural = "natural"
    case technical = "technical"
    case casual = "casual"
    case concise = "concise"
    case explanatory = "explanatory"
    case polite = "polite"
    case imaginative = "imaginative"
    case sarcastic = "sarcastic"

    var id: String { rawValue }

    /// Human-readable title shown in menus, settings, and pickers.
    var displayName: String {
        switch self {
        case .natural: return "Natural & Fluent"
        case .technical: return "Technical & Professional"
        case .casual: return "Casual & Conversational"
        case .concise: return "Ultra-Concise Summary"
        case .explanatory: return "Bilingual Explanatory"
        case .polite: return "Polite & Honorific"
        case .imaginative: return "Imaginative & Creative"
        case .sarcastic: return "Sarcastic & Witty"
        }
    }

    /// Subtitle describing when to use this translation style.
    var subtitle: String {
        switch self {
        case .natural: return "Balanced, idiomatic everyday translation"
        case .technical: return "Preserves code, API names & engineering specs"
        case .casual: return "Colloquial chat, slang & localized idiom"
        case .concise: return "Distills essential core meaning in minimal words"
        case .explanatory: return "Translates with key vocab & grammar nuance notes"
        case .polite: return "Formal business courtesy & honorific register"
        case .imaginative: return "Vivid imagery, rich metaphors & storytelling flair"
        case .sarcastic: return "Sharp irony, humorous sarcasm & witty cynicism"
        }
    }

    /// Detailed condition and purpose description for the settings UI.
    var useCase: String {
        switch self {
        case .natural:
            return "Best for everyday reading, articles, and general browsing. Produces balanced, idiomatic translation that sounds natural to native speakers."
        case .technical:
            return "Best for developer docs, code comments, and technical manuals. Accurately preserves APIs, code syntax, variable identifiers, and engineering jargon."
        case .casual:
            return "Best for chat messages, social media, forums, and dialogue. Uses relaxed, localized slang and colloquial phrasing."
        case .concise:
            return "Best for quick glance overviews and fast reading. Strips conversational filler and delivers the essential factual message in minimal words."
        case .explanatory:
            return "Best for language learning and study. Translates the full text and provides helpful context notes explaining key vocabulary and idioms."
        case .polite:
            return "Best for business emails, official correspondence, and client communication. Uses formal honorifics and respectful etiquette."
        case .imaginative:
            return "Best for fiction, poetry, marketing copy, and gaming lore. Translates with vivid imagery, literary metaphors, and expressive storytelling flair."
        case .sarcastic:
            return "Best for memes, jokes, entertainment, and banter. Delivers punchy translations with sharp wit, irony, and humorous cynicism."
        }
    }

    /// Explicit directive interpolated into the LLM system prompt.
    var promptInstruction: String {
        switch self {
        case .natural:
            return "Translate naturally, accurately, and fluently while preserving original context and nuance."
        case .technical:
            return "Translate with high technical precision. Preserve code syntax, API/function names, framework terms, variable identifiers, and engineering jargon without translating them unless standard in the target language."
        case .casual:
            return "Translate using a relaxed, localized, conversational tone suitable for chats, casual articles, and social media."
        case .concise:
            return "Translate with maximum conciseness. Strip conversational filler and boilerplate; deliver the core factual message directly in minimal words."
        case .explanatory:
            return "Translate fluently, then provide brief parenthetical or bulleted explanations for key technical terms, idioms, or grammar nuances."
        case .polite:
            return "Translate using a highly polite, respectful, and honorific tone suitable for formal business correspondence (e.g., Keigo, formal polite register)."
        case .imaginative:
            return "Translate with vivid imagination, poetic flair, evocative metaphors, and creative storytelling while preserving thematic depth."
        case .sarcastic:
            return "Translate with sharp wit, playful sarcasm, subtle irony, and humorous cynicism while faithfully reflecting the original meaning."
        }
    }

    /// Backward-compatible decoder fallback for older stored settings.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "technical", "formal": self = .technical
        case "casual": self = .casual
        case "concise": self = .concise
        case "explanatory", "literary": self = .explanatory
        case "polite": self = .polite
        case "imaginative": self = .imaginative
        case "sarcastic": self = .sarcastic
        default: self = .natural
        }
    }
}

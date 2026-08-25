import Foundation

/// One source-text/translation pair extracted from a screenshot.
struct TranslationItem: Codable, Equatable {
    let source: String
    let translation: String
}

struct TranslationItemsEnvelope: Codable, Equatable {
    let items: [TranslationItem]
}

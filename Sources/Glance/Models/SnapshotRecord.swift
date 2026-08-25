import AppKit

/// One row in the snapshots table. Translation fields are part of the schema
/// from day one (design §6.1) but are only populated from M3 onward.
struct SnapshotRecord: Identifiable, Equatable {
    enum Status: String {
        case pending    // captured, awaiting translation (M2)
        case ok
        case empty      // no translatable text found
        case failed     // translation error; error_message holds why
    }

    let id: UUID
    var createdAt: Date
    var imagePath: String          // relative to the Glance app-support dir
    var pixelWidth: Int
    var pixelHeight: Int
    var status: Status
    var targetLanguage: String?
    var sourceLanguage: String?
    var translatedText: String
    var sourceText: String
    var itemsJSON: String
    var endpointID: UUID?
    var endpointLabel: String?
    var model: String?
    var latencyMs: Int?
    var errorMessage: String?

    /// Decodes the structured items from itemsJSON on demand.
    var decodedItems: [TranslationItem] {
        guard let data = itemsJSON.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(TranslationItemsEnvelope.self, from: data) else {
            return []
        }
        return envelope.items
    }

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         imagePath: String = "",              // filled in by HistoryStore on write
         pixelWidth: Int,
         pixelHeight: Int,
         status: Status,
         targetLanguage: String? = nil,
         sourceLanguage: String? = nil,
         translatedText: String = "",
         sourceText: String = "",
         itemsJSON: String = "[]",
         endpointID: UUID? = nil,
         endpointLabel: String? = nil,
         model: String? = nil,
         latencyMs: Int? = nil,
         errorMessage: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.status = status
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
        self.translatedText = translatedText
        self.sourceText = sourceText
        self.itemsJSON = itemsJSON
        self.endpointID = endpointID
        self.endpointLabel = endpointLabel
        self.model = model
        self.latencyMs = latencyMs
        self.errorMessage = errorMessage
    }
}

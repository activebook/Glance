import Foundation

/// A configured translation endpoint (OpenAI-compatible chat-completions API).
/// The API key is NOT stored here — it lives in the Keychain under the endpoint id.
struct EndpointConfig: Identifiable, Codable, Equatable, Hashable {
    enum ValidationError: Equatable, CaseIterable, Error {
        case emptyLabel
        case emptyModel
        case invalidURL
        case insecureURL

        var errorDescription: String? {
            switch self {
            case .emptyLabel: return "Name cannot be empty."
            case .emptyModel: return "Model cannot be empty."
            case .invalidURL: return "Base URL must include a scheme and host."
            case .insecureURL: return "Only https:// URLs are allowed (http://localhost and 127.0.0.1 excepted)."
            }
        }
    }

    let id: UUID
    var label: String
    var baseURL: URL
    var model: String

    init(id: UUID = UUID(), label: String, baseURL: URL, model: String) {
        self.id = id
        self.label = label
        self.baseURL = baseURL
        self.model = model
    }

    /// Returns all current validation problems; an empty array means valid.
    func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        if label.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyLabel)
        }
        if model.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyModel)
        }
        guard let host = baseURL.host, !host.isEmpty,
              baseURL.scheme != nil else {
            errors.append(.invalidURL)
            return errors // URL-level problems make scheme checks meaningless
        }
        if baseURL.scheme?.lowercased() != "https" && !isLocalhost(host) {
            errors.append(.insecureURL)
        }
        return errors
    }

    private func isLocalhost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost" || lowered == "127.0.0.1" || lowered == "::1"
    }

    // MARK: - Example defaults

    /// Real default values used when creating a NEW endpoint (shown as actual
    /// editable field content, not placeholder text — per M1.2).
    static let exampleLabel = "gemini-flash-lite"
    static let exampleBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!
    static let exampleModel = "gemini-flash-lite-latest"
}

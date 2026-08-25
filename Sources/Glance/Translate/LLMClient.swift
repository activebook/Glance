import Foundation

/// Minimal OpenAI-compatible client: connection testing (M1.3) and
/// vision-translation of screenshots (M3), sharing one request core.
enum LLMClient {

    enum ConnectionOutcome: Equatable {
        case success(latencyMs: Int)
        case failure(String)
    }

    enum TranslateOutcome: Equatable {
        case ok(items: [TranslationItem], latencyMs: Int)
        case empty(latencyMs: Int)
        case failure(String, latencyMs: Int?)
    }

    enum TranslateError: Error {
        case noJSONFound
        case decodingFailed
    }

    /// Pings `{baseURL}/chat/completions` with a 1-token completion.
    /// Uses a real chat request (not GET /models) so it also validates the
    /// model name — many OpenAI-compatible gateways omit /models.
    static func testConnection(baseURL: URL,
                               apiKey: String,
                               model: String,
                               timeout: TimeInterval = 15) async -> ConnectionOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure("Could not build request: \(error.localizedDescription)")
        }

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return .failure("Timed out after \(Int(timeout)) s — endpoint unreachable.")
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .failure("Cannot reach host — check the Base URL.")
            case .notConnectedToInternet:
                return .failure("No network connection.")
            case .appTransportSecurityRequiresSecureConnection:
                return .failure("Insecure connection blocked — use https://.")
            default:
                return .failure("Network error: \(error.localizedDescription)")
            }
        } catch {
            return .failure("Network error: \(error.localizedDescription)")
        }

        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let http = response as? HTTPURLResponse else {
            return .failure("Invalid server response.")
        }

        switch http.statusCode {
        case 200...299:
            return .success(latencyMs: latencyMs)
        case 401, 403:
            return .failure(detail(data, fallback: "Authentication failed (\(http.statusCode)) — check the API key."))
        case 404:
            return .failure(detail(data, fallback: "Not found (404) — check the Base URL and model name."))
        case 429:
            return .failure(detail(data, fallback: "Rate limited (429) — key works but quota is exhausted."))
        default:
            return .failure(detail(data, fallback: "Server error (\(http.statusCode))."))
        }
    }

    /// Extracts an API-provided error message when present; falls back to a
    /// truncated raw-body excerpt (gateways often return unexpected shapes).
    private static func detail(_ data: Data, fallback: String) -> String {
        struct ErrorBody: Decodable {
            struct Err: Decodable { let message: String? }
            let error: Err?
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = body.error?.message, !message.isEmpty {
            return "\(fallback) — \(message)"
        }
        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let excerpt = raw.count > 140 ? String(raw.prefix(140)) + "…" : raw
            return "\(fallback) — \(excerpt)"
        }
        return fallback
    }

    // MARK: - Vision translation (design §5.5)

    /// System prompt per design.md §5.5; target language and tone interpolated.
    static func prompt(targetLanguage: AppLanguage, tone: TranslationTone = .natural) -> String {
        """
        You are a translation engine embedded in a screenshot tool. \
        Find ALL human-readable text in this image (UI labels, subtitles, documents, \
        signs, handwriting). Translate every piece of text into: \(targetLanguage.promptName). \
        Translation style directive: \(tone.promptInstruction) \
        Preserve reading order top-to-bottom, left-to-right. Keep proper nouns' \
        romanization sensible. If the image contains no translatable text, return an empty items array. \
        Respond ONLY with minified JSON matching exactly: \
        {"items":[{"source":"<original text>","translation":"<translated text>"}]}
        """
    }

    /// Pure request builder (unit-tested).
    static func buildTranslateRequest(baseURL: URL,
                                      apiKey: String,
                                      model: String,
                                      pngBase64: String,
                                      targetLanguage: AppLanguage,
                                      tone: TranslationTone = .natural,
                                      includeJSONMode: Bool = true) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt(targetLanguage: targetLanguage, tone: tone)],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(pngBase64)"]]
                ]
            ]]
        ]
        if includeJSONMode {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parses the model reply: strict decode first, then tolerant recovery of a
    /// JSON object embedded in prose/fenced blocks.
    static func parseItems(from data: Data) throws -> [TranslationItem] {
        if let envelope = try? JSONDecoder().decode(TranslationItemsEnvelope.self, from: data) {
            return envelope.items
        }
        // Tolerant recovery.
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else {
            throw TranslateError.noJSONFound
        }
        let slice = String(text[start...end])
        guard let jsonData = slice.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(TranslationItemsEnvelope.self, from: jsonData) else {
            throw TranslateError.decodingFailed
        }
        return envelope.items
    }

    /// Extracts the assistant's message content from a chat-completion payload.
    static func assistantContent(from data: Data) -> String? {
        struct Body: Decodable {
            struct Choice: Decodable { let message: Message }
            struct Message: Decodable { let content: String? }
            let choices: [Choice]?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let content = body.choices?.first?.message.content else {
            return nil
        }
        return content
    }

    /// Full vision-translation call. Retries once WITHOUT response_format when
    /// the gateway rejects JSON mode (400), for broad OpenAI-compatibility.
    static func translate(pngData: Data,
                          targetLanguage: AppLanguage,
                          tone: TranslationTone = .natural,
                          baseURL: URL,
                          apiKey: String,
                          model: String) async -> TranslateOutcome {
        let pngBase64 = pngData.base64EncodedString()
        let started = Date()

        func latencyMs() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

        var includeJSONMode = true
        var responseData: Data?
        var httpStatus: Int?
        var serverRetryCount = 0
        // 5xx (esp. Gemini's 503 "model overloaded") is usually transient —
        // retry up to 2 extra times with backoff (M3.4).
        let serverRetryDelays: [UInt64] = [1_000_000_000, 2_500_000_000]

        // Loop until success, a terminal error, or retries exhausted.
        while responseData == nil {
            guard let request = try? buildTranslateRequest(baseURL: baseURL,
                                                           apiKey: apiKey,
                                                           model: model,
                                                           pngBase64: pngBase64,
                                                           targetLanguage: targetLanguage,
                                                           tone: tone,
                                                           includeJSONMode: includeJSONMode) else {
                return .failure("Could not build request.", latencyMs: nil)
            }

            let result: (data: Data, response: URLResponse)
            do {
                result = try await URLSession.shared.data(for: request)
            } catch let error as URLError {
                switch error.code {
                case .timedOut:
                    return .failure("Timed out after 60 s — endpoint unreachable.", latencyMs: latencyMs())
                case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    return .failure("Cannot reach host — check the Base URL.", latencyMs: latencyMs())
                case .notConnectedToInternet:
                    return .failure("No network connection.", latencyMs: latencyMs())
                default:
                    return .failure("Network error: \(error.localizedDescription)", latencyMs: latencyMs())
                }
            } catch {
                return .failure("Network error: \(error.localizedDescription)", latencyMs: latencyMs())
            }

            guard let http = result.response as? HTTPURLResponse else {
                return .failure("Invalid server response.", latencyMs: latencyMs())
            }
            httpStatus = http.statusCode

            switch http.statusCode {
            case 200...299:
                responseData = result.data
            case 400 where includeJSONMode:
                // Some gateways reject response_format — retry without it once.
                includeJSONMode = false
            case 500...599:
                guard serverRetryCount < serverRetryDelays.count else {
                    return .failure(detail(result.data, fallback: "Server error (\(http.statusCode)) — still failing after \(serverRetryCount + 1) attempts; the model may be overloaded right now."), latencyMs: latencyMs())
                }
                let delay = serverRetryDelays[serverRetryCount]
                serverRetryCount += 1
                NSLog("Glance: HTTP \(http.statusCode) — retrying in \(delay / 1_000_000_000)s (attempt \(serverRetryCount + 1))")
                try? await Task.sleep(nanoseconds: delay)
            case 401, 403:
                return .failure(detail(result.data, fallback: "Authentication failed (\(http.statusCode)) — check the API key."), latencyMs: latencyMs())
            case 404:
                return .failure(detail(result.data, fallback: "Not found (404) — check the Base URL and model name."), latencyMs: latencyMs())
            case 429:
                return .failure(detail(result.data, fallback: "Rate limited (429) — key works but quota is exhausted."), latencyMs: latencyMs())
            default:
                return .failure(detail(result.data, fallback: "Server error (\(http.statusCode))."), latencyMs: latencyMs())
            }
        }

        guard let data = responseData else {
            return .failure("No response body.", latencyMs: latencyMs())
        }

        // The reply body is the API envelope; the translatable JSON sits inside
        // the assistant message content.
        let content: String
        if let direct = try? parseItems(from: data) {
            return finalize(direct, latencyMs())
        } else if let raw = assistantContent(from: data) {
            content = raw
        } else {
            return .failure(detail(data, fallback: "Could not read the model's reply (\(httpStatus ?? 0))."), latencyMs: latencyMs())
        }

        do {
            let items = try parseItems(from: Data(content.utf8))
            return finalize(items, latencyMs())
        } catch {
            return .failure("Model reply was not valid translation JSON.", latencyMs: latencyMs())
        }
    }

    private static func finalize(_ items: [TranslationItem], _ latencyMs: Int) -> TranslateOutcome {
        items.isEmpty ? .empty(latencyMs: latencyMs)
                      : .ok(items: items, latencyMs: latencyMs)
    }
}


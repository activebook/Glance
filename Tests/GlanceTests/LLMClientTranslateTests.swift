import XCTest
@testable import Glance

final class LLMClientTranslateTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com/v1")!

    // MARK: parseItems

    func test_parse_strictJSON() throws {
        let json = #"{"items":[{"source":"Hello","translation":"你好"},{"source":"World","translation":"世界"}]}"#
        let items = try LLMClient.parseItems(from: Data(json.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], TranslationItem(source: "Hello", translation: "你好"))
        XCTAssertEqual(items[1].translation, "世界")
    }

    func test_parse_emptyItems_isEmptyArray() throws {
        let items = try LLMClient.parseItems(from: Data(#"{"items":[]}"#.utf8))
        XCTAssertTrue(items.isEmpty)
    }

    func test_parse_tolerantRecovery_fromProseWrappedJSON() throws {
        let wrapped = """
        Sure! Here is the translation:
        ```json
        {"items":[{"source":"Hi","translation":"嗨"}]}
        ```
        Hope that helps.
        """
        let items = try LLMClient.parseItems(from: Data(wrapped.utf8))
        XCTAssertEqual(items, [TranslationItem(source: "Hi", translation: "嗨")])
    }

    func test_parse_garbage_throws() {
        XCTAssertThrowsError(try LLMClient.parseItems(from: Data("no json at all".utf8)))
        XCTAssertThrowsError(try LLMClient.parseItems(from: Data(#"{"wrong":"shape"}"#.utf8)))
    }

    // MARK: buildTranslateRequest

    func test_buildRequest_containsImagePromptAndAuth() throws {
        let request = try LLMClient.buildTranslateRequest(
            baseURL: baseURL,
            apiKey: "sk-test",
            model: "vision-model",
            pngBase64: "QUJD",
            targetLanguage: .simplifiedChinese
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "vision-model")
        XCTAssertNotNil(object["response_format"], "JSON mode should be requested by default")

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "text")
        let text = try XCTUnwrap(content[0]["text"] as? String)
        XCTAssertTrue(text.contains("Simplified Chinese"))
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap((content[1]["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,QUJD"))
    }

    func test_buildRequest_canOmitJSONMode() throws {
        let request = try LLMClient.buildTranslateRequest(
            baseURL: baseURL, apiKey: "", model: "m",
            pngBase64: "x", targetLanguage: .english,
            includeJSONMode: false
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["response_format"])
    }

    // MARK: assistantContent

    func test_assistantContent_extraction() throws {
        let payload = #"{"choices":[{"message":{"content":"{\"items\":[]}"}}]}"#
        XCTAssertEqual(LLMClient.assistantContent(from: Data(payload.utf8)), #"{"items":[]}"#)
    }

    func test_buildRequest_interpolatesFuriganaToneDirective() throws {
        let request = try LLMClient.buildTranslateRequest(
            baseURL: baseURL,
            apiKey: "sk-test",
            model: "vision-model",
            pngBase64: "QUJD",
            targetLanguage: .japanese,
            tone: .furigana
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content[0]["text"] as? String)
        XCTAssertTrue(text.contains("furigana"))
    }
}

final class ImageDownscalerTests: XCTestCase {
    private func solidImage(width: Int, height: Int) -> CGImage {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        .cgImage!
    }

    func test_downscale_shrinksLongSide_toBudget() {
        let small = ImageDownscaler.downscaleIfOversized(solidImage(width: 3000, height: 1500))
        XCTAssertEqual(max(small.width, small.height), 2000)
        XCTAssertEqual(CGSize(width: small.width, height: small.height),
                       CGSize(width: 2000, height: 1000))
    }

    func test_downscale_keepsSmallImagesUntouched() {
        let original = solidImage(width: 800, height: 600)
        let result = ImageDownscaler.downscaleIfOversized(original)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }
}

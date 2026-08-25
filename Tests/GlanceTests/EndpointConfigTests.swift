import XCTest
@testable import Glance

final class EndpointConfigTests: XCTestCase {
    private let https = URL(string: "https://api.example.com/v1")!

    func test_validEndpoint_hasNoErrors() {
        let endpoint = EndpointConfig(label: "prod", baseURL: https, model: "m1")
        XCTAssertTrue(endpoint.validate().isEmpty)
    }

    func test_emptyLabel_rejected() {
        let endpoint = EndpointConfig(label: "   ", baseURL: https, model: "m1")
        XCTAssertEqual(endpoint.validate(), [.emptyLabel])
    }

    func test_emptyModel_rejected() {
        let endpoint = EndpointConfig(label: "prod", baseURL: https, model: "")
        XCTAssertEqual(endpoint.validate(), [.emptyModel])
    }

    func test_invalidURL_rejected() {
        // A URL without host cannot be constructed via URL(string:) with a scheme,
        // so exercise the missing-scheme path instead.
        let endpoint = EndpointConfig(label: "prod",
                                      baseURL: URL(string: "api.example.com/v1")!,
                                      model: "m1")
        XCTAssertTrue(endpoint.validate().contains(.invalidURL))
    }

    func test_plainHTTP_remote_rejected_but_localhost_allowed() {
        let remote = EndpointConfig(label: "x",
                                    baseURL: URL(string: "http://api.example.com/v1")!,
                                    model: "m")
        XCTAssertEqual(remote.validate(), [.insecureURL])

        let local = EndpointConfig(label: "dev",
                                   baseURL: URL(string: "http://localhost:8080/v1")!,
                                   model: "m")
        XCTAssertTrue(local.validate().isEmpty)

        let loopback = EndpointConfig(label: "dev2",
                                      baseURL: URL(string: "http://127.0.0.1:9000/v1")!,
                                      model: "m")
        XCTAssertTrue(loopback.validate().isEmpty)
    }

    func test_codableRoundtrip_preservesFields() throws {
        let original = EndpointConfig(label: "a b", baseURL: https, model: "model-x")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EndpointConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

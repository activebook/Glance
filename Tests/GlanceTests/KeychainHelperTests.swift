import XCTest
@testable import Glance

/// Exercises the real user keychain. Each test uses fresh UUID accounts so runs
/// never collide; teardown removes anything created.
final class KeychainHelperTests: XCTestCase {
    private var keychain: KeychainHelper!
    private var createdAccounts: [UUID] = []

    override func setUp() {
        super.setUp()
        keychain = KeychainHelper(service: "GlanceTests")
    }

    override func tearDown() {
        for id in createdAccounts {
            try? keychain.delete(for: id)
        }
        createdAccounts.removeAll()
        super.tearDown()
    }

    private func freshID() -> UUID {
        let id = UUID()
        createdAccounts.append(id)
        return id
    }

    func test_set_then_get_roundtrips() throws {
        let id = freshID()
        try keychain.set("sk-test-123", for: id)
        XCTAssertEqual(keychain.get(for: id), "sk-test-123")
    }

    func test_overwrite_returns_new_value() throws {
        let id = freshID()
        try keychain.set("first", for: id)
        try keychain.set("second", for: id)
        XCTAssertEqual(keychain.get(for: id), "second")
    }

    func test_get_missing_returns_nil() {
        XCTAssertNil(keychain.get(for: freshID()))
    }

    func test_delete_removes_item() throws {
        let id = freshID()
        try keychain.set("gone-soon", for: id)
        try keychain.delete(for: id)
        XCTAssertNil(keychain.get(for: id))
    }

    func test_delete_missing_isNotAnError() throws {
        XCTAssertNoThrow(try keychain.delete(for: freshID()))
    }

    func test_empty_secret_stored_and_retrieved() throws {
        // SettingsStore guards against empty keys, but the helper itself
        // must not corrupt state if asked.
        let id = freshID()
        try keychain.set("", for: id)
        XCTAssertEqual(keychain.get(for: id), "")
    }
}

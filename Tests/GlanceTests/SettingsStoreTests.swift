import XCTest
import Carbon.HIToolbox
@testable import Glance

/// Persistence and resolution tests run against an isolated UserDefaults suite
/// so they never touch the real app's settings.
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "GlanceSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeEndpoint(_ label: String = "ep") -> EndpointConfig {
        EndpointConfig(label: label,
                       baseURL: URL(string: "https://api.example.com/v1")!,
                       model: "m")
    }

    private func makeStore(keychain: KeychainHelper = KeychainHelper(service: "GlanceSettingsStoreTests")) -> SettingsStore {
        SettingsStore(defaults: defaults, keychain: keychain)
    }

    func test_defaults_whenNothingPersisted() {
        let store = makeStore()
        XCTAssertTrue(store.endpoints.isEmpty)
        XCTAssertNil(store.defaultEndpointID)
        XCTAssertEqual(store.targetLanguage, .simplifiedChinese)
        XCTAssertEqual(store.resultPanelTimeout, 10)
        XCTAssertNil(store.activeEndpoint())
    }

    func test_persistence_across_store_instances() throws {
        let first = makeStore()
        let endpoint = makeEndpoint("prod")
        first.addEndpoint(endpoint, key: "sk-secret")
        first.setDefaultEndpoint(id: endpoint.id)

        // New instance over the same defaults must see identical config.
        let second = makeStore()
        XCTAssertEqual(second.endpoints.first, endpoint)
        XCTAssertEqual(second.defaultEndpointID, endpoint.id)

        // …and the key must round-trip through the (shared test) keychain.
        XCTAssertEqual(second.key(for: endpoint.id), "sk-secret")

        // Cleanup: remove the test keychain item.
        try KeychainHelper(service: "GlanceSettingsStoreTests").delete(for: endpoint.id)
    }

    func test_activeEndpoint_fallbackChain() {
        let store = makeStore()
        let a = makeEndpoint("a")
        let b = makeEndpoint("b")
        store.addEndpoint(a, key: nil)
        store.addEndpoint(b, key: nil)

        // Neither active nor default set explicitly → addEndpoint made `a` default.
        XCTAssertEqual(store.activeEndpoint()?.id, a.id)

        // Explicit active wins over default.
        store.setActiveEndpoint(id: b.id)
        XCTAssertEqual(store.activeEndpoint()?.id, b.id)

        // Clearing active falls back to default.
        store.setActiveEndpoint(id: nil)
        XCTAssertEqual(store.activeEndpoint()?.id, a.id)

        // Deleting the default leaves the remaining endpoint as fallback.
        store.deleteEndpoint(id: a.id)
        XCTAssertEqual(store.activeEndpoint()?.id, b.id)
    }

    func test_deleteEndpoint_clears_references_and_key() throws {
        let store = makeStore()
        let keychain = KeychainHelper(service: "GlanceSettingsStoreTests")
        let endpoint = makeEndpoint("doomed")
        store.addEndpoint(endpoint, key: "sk-doomed")
        store.setActiveEndpoint(id: endpoint.id)

        store.deleteEndpoint(id: endpoint.id)

        XCTAssertTrue(store.endpoints.isEmpty)
        XCTAssertNil(store.defaultEndpointID)
        XCTAssertNil(store.activeEndpointID)
        XCTAssertNil(keychain.get(for: endpoint.id))
        XCTAssertNil(store.activeEndpoint())
    }

    func test_legacyBlobWithoutHotkey_decodesWithDefault() throws {
        // A settings blob written before M1.3 has no "hotkey" field.
        struct LegacyBlob: Codable {
            var endpoints: [EndpointConfig] = []
            var defaultEndpointID: UUID?
            var activeEndpointID: UUID?
            var targetLanguage: AppLanguage = .simplifiedChinese
            var resultPanelTimeout: TimeInterval = 10
        }
        let legacyData = try JSONEncoder().encode(LegacyBlob())
        defaults.set(legacyData, forKey: SettingsStore.storageKey)

        let store = makeStore()
        XCTAssertEqual(store.hotkey, .default)
    }

    func test_hotkeyChange_persistsAcrossInstances() {
        let first = makeStore()
        let custom = HotkeyCombo(keyCode: 15, carbonModifiers: UInt32(cmdKey | controlKey))
        first.hotkey = custom

        let second = makeStore()
        XCTAssertEqual(second.hotkey, custom)
    }

    func test_deliverySettings_persistAcrossInstances() {
        let first = makeStore()
        first.enableNotifications = false
        first.playNotificationSound = false
        first.autoCopyToClipboard = true

        let second = makeStore()
        XCTAssertFalse(second.enableNotifications)
        XCTAssertFalse(second.playNotificationSound)
        XCTAssertTrue(second.autoCopyToClipboard)
    }

    func test_typographyAndStyleSettings_persistAcrossInstances() {
        let first = makeStore()
        first.hudAppearanceStyle = .frostedGlass
        first.hudOpacity = 0.65
        first.sourceFontSize = 15
        first.sourceTextColor = ColorOption(hex: "#FF5733")
        first.translatedFontSize = 18
        first.translatedTextColor = ColorOption(hex: "#33FF57")
        first.translationTone = .imaginative

        let second = makeStore()
        XCTAssertEqual(second.hudAppearanceStyle, .frostedGlass)
        XCTAssertEqual(second.hudOpacity, 0.65, accuracy: 0.001)
        XCTAssertEqual(second.sourceFontSize, 15)
        XCTAssertEqual(second.sourceTextColor.hex, "#FF5733")
        XCTAssertEqual(second.translatedFontSize, 18)
        XCTAssertEqual(second.translatedTextColor.hex, "#33FF57")
        XCTAssertEqual(second.translationTone, .imaginative)
    }
}

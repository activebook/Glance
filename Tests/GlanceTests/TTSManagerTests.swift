import XCTest
@testable import Glance

final class TTSManagerTests: XCTestCase {
    func test_secMSGECToken_is64HexCharacters() {
        let token = EdgeTTSClient.generateSecMSGECToken()
        XCTAssertEqual(token.count, 64)
        XCTAssertTrue(token.allSatisfy { $0.isHexDigit && ($0.isUppercase || $0.isNumber) })
    }

    func test_defaultVoice_matchesSupportedLanguages() {
        XCTAssertEqual(TTSEngine.defaultVoice(for: .english), "en-US-JennyNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .simplifiedChinese), "zh-CN-XiaoxiaoNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .traditionalChinese), "zh-TW-HsiaoChenNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .japanese), "ja-JP-NanamiNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .korean), "ko-KR-SunHiNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .french), "fr-FR-DeniseNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .german), "de-DE-KatjaNeural")
        XCTAssertEqual(TTSEngine.defaultVoice(for: .spanish), "es-ES-ElviraNeural")
    }

    func test_bcp47Locale_matchesLanguages() {
        XCTAssertEqual(TTSEngine.bcp47Locale(for: .english), "en-US")
        XCTAssertEqual(TTSEngine.bcp47Locale(for: .simplifiedChinese), "zh-CN")
        XCTAssertEqual(TTSEngine.bcp47Locale(for: .traditionalChinese), "zh-TW")
        XCTAssertEqual(TTSEngine.bcp47Locale(for: .japanese), "ja-JP")
        XCTAssertEqual(TTSEngine.bcp47Locale(for: .korean), "ko-KR")
    }

    func test_settingsStore_persistsTTSEngineAndRate() throws {
        let suiteName = "test.glance.tts.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store1 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store1.ttsEngine, .edgeNeural)
        XCTAssertEqual(store1.ttsRate, 1.0)

        store1.ttsEngine = .systemNative
        store1.ttsRate = 1.25

        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.ttsEngine, .systemNative)
        XCTAssertEqual(store2.ttsRate, 1.25)
    }

    func test_ttsManager_stop_clearsState() {
        let manager = TTSManager.shared
        manager.stop()
        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.currentPlayingText)
    }
}

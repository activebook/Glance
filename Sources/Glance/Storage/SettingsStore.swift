import Foundation
import Combine

/// Central app settings. Config (without secrets) persists as one JSON blob in
/// UserDefaults under `glance.settings.v1`; API keys live in the Keychain.
///
/// Mutations go through explicit methods (not raw Bindings into the arrays) so
/// that invariants — e.g. "deleting an endpoint clears references to it" — are
/// enforced in exactly one place.
final class SettingsStore: ObservableObject {
    static let storageKey = "glance.settings.v1"

    // MARK: - Published state

    @Published private(set) var endpoints: [EndpointConfig]
    @Published private(set) var defaultEndpointID: UUID?
    /// The endpoint chosen from the menu-bar switcher; nil means "follow default".
    @Published private(set) var activeEndpointID: UUID?
    @Published var targetLanguage: AppLanguage {
        didSet { persist() }
    }
    @Published var translationTone: TranslationTone {
        didSet { persist() }
    }
    @Published var hudAppearanceStyle: HUDAppearanceStyle {
        didSet { persist() }
    }
    @Published var hudOpacity: Double {
        didSet { persist() }
    }
    @Published var sourceFontSize: Double {
        didSet { persist() }
    }
    @Published var sourceTextColor: ColorOption {
        didSet { persist() }
    }
    @Published var translatedFontSize: Double {
        didSet { persist() }
    }
    @Published var translatedTextColor: ColorOption {
        didSet { persist() }
    }
    @Published var resultPanelTimeout: TimeInterval {
        didSet { persist() }
    }
    @Published var hotkey: HotkeyCombo {
        didSet { persist() }
    }
    @Published var repeatHotkey: HotkeyCombo {
        didSet { persist() }
    }
    @Published var enableNotifications: Bool {
        didSet { persist() }
    }
    @Published var playNotificationSound: Bool {
        didSet { persist() }
    }
    @Published var autoCopyToClipboard: Bool {
        didSet { persist() }
    }
    @Published var automaticallyCheckForUpdates: Bool {
        didSet { persist() }
    }
    @Published var ttsEngine: TTSEngine {
        didSet { persist() }
    }
    @Published var ttsRate: Double {
        didSet { persist() }
    }
    @Published var historyLayoutMode: HistoryLayoutMode {
        didSet { persist() }
    }
    @Published var showFurigana: Bool {
        didSet { persist() }
    }
    @Published var furiganaScaleFactor: Double {
        didSet { persist() }
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let keychain: KeychainHelper

    // MARK: - Init / persistence

    init(defaults: UserDefaults = .standard,
         keychain: KeychainHelper = KeychainHelper()) {
        self.defaults = defaults
        self.keychain = keychain

        if let data = defaults.data(forKey: Self.storageKey),
           let loaded = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            endpoints = loaded.endpoints
            defaultEndpointID = loaded.defaultEndpointID
            activeEndpointID = loaded.activeEndpointID
            targetLanguage = loaded.targetLanguage
            translationTone = loaded.translationTone ?? .natural
            hudAppearanceStyle = loaded.hudAppearanceStyle ?? .translucentDark
            hudOpacity = loaded.hudOpacity ?? 0.85
            sourceFontSize = loaded.sourceFontSize ?? 12
            sourceTextColor = loaded.sourceTextColor ?? .secondary
            translatedFontSize = loaded.translatedFontSize ?? 14
            translatedTextColor = loaded.translatedTextColor ?? .primary
            resultPanelTimeout = loaded.resultPanelTimeout
            hotkey = loaded.hotkey ?? .default
            repeatHotkey = loaded.repeatHotkey ?? .defaultRepeat
            enableNotifications = loaded.enableNotifications ?? true
            playNotificationSound = loaded.playNotificationSound ?? true
            autoCopyToClipboard = loaded.autoCopyToClipboard ?? false
            automaticallyCheckForUpdates = loaded.automaticallyCheckForUpdates ?? true
            ttsEngine = loaded.ttsEngine ?? .edgeNeural
            ttsRate = loaded.ttsRate ?? 1.0
            historyLayoutMode = loaded.historyLayoutMode ?? .sidebar
            showFurigana = loaded.showFurigana ?? true
            furiganaScaleFactor = loaded.furiganaScaleFactor ?? 0.6
        } else {
            endpoints = []
            defaultEndpointID = nil
            activeEndpointID = nil
            targetLanguage = .english
            translationTone = .natural
            hudAppearanceStyle = .translucentDark
            hudOpacity = 0.85
            sourceFontSize = 12
            sourceTextColor = .secondary
            translatedFontSize = 14
            translatedTextColor = .primary
            resultPanelTimeout = 10
            hotkey = .default
            repeatHotkey = .defaultRepeat
            enableNotifications = true
            playNotificationSound = true
            autoCopyToClipboard = false
            automaticallyCheckForUpdates = true
            ttsEngine = .edgeNeural
            ttsRate = 1.0
            historyLayoutMode = .sidebar
            showFurigana = true
            furiganaScaleFactor = 0.6
        }
    }

    private struct PersistedSettings: Codable {
        var endpoints: [EndpointConfig] = []
        var defaultEndpointID: UUID?
        var activeEndpointID: UUID?
        var targetLanguage: AppLanguage = .english
        var translationTone: TranslationTone? = .natural
        var hudAppearanceStyle: HUDAppearanceStyle? = .translucentDark
        var hudOpacity: Double? = 0.85
        var sourceFontSize: Double? = 12
        var sourceTextColor: ColorOption? = .secondary
        var translatedFontSize: Double? = 14
        var translatedTextColor: ColorOption? = .primary
        var resultPanelTimeout: TimeInterval = 10
        var hotkey: HotkeyCombo?
        var repeatHotkey: HotkeyCombo?
        var enableNotifications: Bool? = true
        var playNotificationSound: Bool? = true
        var autoCopyToClipboard: Bool? = false
        var automaticallyCheckForUpdates: Bool? = true
        var ttsEngine: TTSEngine? = .edgeNeural
        var ttsRate: Double? = 1.0
        var historyLayoutMode: HistoryLayoutMode? = .sidebar
        var showFurigana: Bool? = true
        var furiganaScaleFactor: Double? = 0.6

        init(endpoints: [EndpointConfig],
             defaultEndpointID: UUID?,
             activeEndpointID: UUID?,
             targetLanguage: AppLanguage,
             translationTone: TranslationTone? = .natural,
             hudAppearanceStyle: HUDAppearanceStyle? = .translucentDark,
             hudOpacity: Double? = 0.85,
             sourceFontSize: Double? = 12,
             sourceTextColor: ColorOption? = .secondary,
             translatedFontSize: Double? = 14,
             translatedTextColor: ColorOption? = .primary,
             resultPanelTimeout: TimeInterval,
             hotkey: HotkeyCombo?,
             repeatHotkey: HotkeyCombo? = .defaultRepeat,
             enableNotifications: Bool = true,
             playNotificationSound: Bool = true,
             autoCopyToClipboard: Bool = false,
             automaticallyCheckForUpdates: Bool = true,
             ttsEngine: TTSEngine = .edgeNeural,
             ttsRate: Double = 1.0,
             historyLayoutMode: HistoryLayoutMode = .sidebar,
             showFurigana: Bool = true,
             furiganaScaleFactor: Double = 0.6) {
            self.endpoints = endpoints
            self.defaultEndpointID = defaultEndpointID
            self.activeEndpointID = activeEndpointID
            self.targetLanguage = targetLanguage
            self.translationTone = translationTone
            self.hudAppearanceStyle = hudAppearanceStyle
            self.hudOpacity = hudOpacity
            self.sourceFontSize = sourceFontSize
            self.sourceTextColor = sourceTextColor
            self.translatedFontSize = translatedFontSize
            self.translatedTextColor = translatedTextColor
            self.resultPanelTimeout = resultPanelTimeout
            self.hotkey = hotkey
            self.repeatHotkey = repeatHotkey
            self.enableNotifications = enableNotifications
            self.playNotificationSound = playNotificationSound
            self.autoCopyToClipboard = autoCopyToClipboard
            self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
            self.ttsEngine = ttsEngine
            self.ttsRate = ttsRate
            self.historyLayoutMode = historyLayoutMode
            self.showFurigana = showFurigana
            self.furiganaScaleFactor = furiganaScaleFactor
        }

        /// Backward-compatible decode (M1.3+): blobs written before new
        /// fields existed must still decode — missing keys fall back to defaults.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            endpoints = try container.decodeIfPresent([EndpointConfig].self, forKey: .endpoints) ?? []
            defaultEndpointID = try container.decodeIfPresent(UUID.self, forKey: .defaultEndpointID)
            activeEndpointID = try container.decodeIfPresent(UUID.self, forKey: .activeEndpointID)
            targetLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .targetLanguage) ?? .english
            translationTone = try container.decodeIfPresent(TranslationTone.self, forKey: .translationTone) ?? .natural
            hudAppearanceStyle = try container.decodeIfPresent(HUDAppearanceStyle.self, forKey: .hudAppearanceStyle) ?? .translucentDark
            hudOpacity = try container.decodeIfPresent(Double.self, forKey: .hudOpacity) ?? 0.85
            sourceFontSize = try container.decodeIfPresent(Double.self, forKey: .sourceFontSize) ?? 12
            sourceTextColor = try container.decodeIfPresent(ColorOption.self, forKey: .sourceTextColor) ?? .secondary
            translatedFontSize = try container.decodeIfPresent(Double.self, forKey: .translatedFontSize) ?? 14
            translatedTextColor = try container.decodeIfPresent(ColorOption.self, forKey: .translatedTextColor) ?? .primary
            resultPanelTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .resultPanelTimeout) ?? 10
            hotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .hotkey)
            repeatHotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .repeatHotkey) ?? .defaultRepeat
            enableNotifications = try container.decodeIfPresent(Bool.self, forKey: .enableNotifications) ?? true
            playNotificationSound = try container.decodeIfPresent(Bool.self, forKey: .playNotificationSound) ?? true
            autoCopyToClipboard = try container.decodeIfPresent(Bool.self, forKey: .autoCopyToClipboard) ?? false
            automaticallyCheckForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? true
            ttsEngine = try container.decodeIfPresent(TTSEngine.self, forKey: .ttsEngine) ?? .edgeNeural
            ttsRate = try container.decodeIfPresent(Double.self, forKey: .ttsRate) ?? 1.0
            historyLayoutMode = try container.decodeIfPresent(HistoryLayoutMode.self, forKey: .historyLayoutMode) ?? .sidebar
            showFurigana = try container.decodeIfPresent(Bool.self, forKey: .showFurigana) ?? true
            furiganaScaleFactor = try container.decodeIfPresent(Double.self, forKey: .furiganaScaleFactor) ?? 0.6
        }
    }

    private func persist() {
        // Called from didSet of value-type properties and after each mutation below.
        // Endpoints/default/active mutations call persist() explicitly because
        // their didSet would also fire for intermediate states during batch edits.
        let blob = PersistedSettings(
            endpoints: endpoints,
            defaultEndpointID: defaultEndpointID,
            activeEndpointID: activeEndpointID,
            targetLanguage: targetLanguage,
            translationTone: translationTone,
            hudAppearanceStyle: hudAppearanceStyle,
            hudOpacity: hudOpacity,
            sourceFontSize: sourceFontSize,
            sourceTextColor: sourceTextColor,
            translatedFontSize: translatedFontSize,
            translatedTextColor: translatedTextColor,
            resultPanelTimeout: resultPanelTimeout,
            hotkey: hotkey,
            repeatHotkey: repeatHotkey,
            enableNotifications: enableNotifications,
            playNotificationSound: playNotificationSound,
            autoCopyToClipboard: autoCopyToClipboard,
            automaticallyCheckForUpdates: automaticallyCheckForUpdates,
            ttsEngine: ttsEngine,
            ttsRate: ttsRate,
            historyLayoutMode: historyLayoutMode,
            showFurigana: showFurigana,
            furiganaScaleFactor: furiganaScaleFactor
        )
        if let data = try? JSONEncoder().encode(blob) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Endpoint CRUD

    func addEndpoint(_ endpoint: EndpointConfig, key: String?) {
        endpoints.append(endpoint)
        if defaultEndpointID == nil {
            defaultEndpointID = endpoint.id
        }
        storeKeySilently(key, for: endpoint.id)
        persist()
    }

    func updateEndpoint(_ endpoint: EndpointConfig) {
        guard let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) else { return }
        endpoints[index] = endpoint
        persist()
    }

    /// Deletes an endpoint, its Keychain item, and any references to it.
    func deleteEndpoint(id: UUID) {
        endpoints.removeAll { $0.id == id }
        if defaultEndpointID == id { defaultEndpointID = nil }
        if activeEndpointID == id { activeEndpointID = nil }
        try? keychain.delete(for: id)
        persist()
    }

    /// First configured endpoint becomes default when none is set.
    func setDefaultEndpoint(id: UUID?) {
        defaultEndpointID = id
        persist()
    }

    /// nil clears the override so the active endpoint follows the default again.
    func setActiveEndpoint(id: UUID?) {
        activeEndpointID = id
        persist()
    }

    // MARK: - Resolution

    /// active ?? default ?? first — per plans/M1-skeleton.md §4.6.
    func activeEndpoint() -> EndpointConfig? {
        if let activeID = activeEndpointID,
           let match = endpoints.first(where: { $0.id == activeID }) {
            return match
        }
        if let defaultID = defaultEndpointID,
           let match = endpoints.first(where: { $0.id == defaultID }) {
            return match
        }
        return endpoints.first
    }

    // MARK: - API keys (Keychain-backed)

    func setKey(_ key: String, for id: UUID) {
        do {
            if key.isEmpty {
                try keychain.delete(for: id)
            } else {
                try keychain.set(key, for: id)
            }
        } catch {
            // Keychain failures must not crash the UI thread; surface via console.
            // TODO(M3): route into an in-app error banner.
            NSLog("Glance: failed to store API key for \(id): \(error)")
        }
    }

    func key(for id: UUID) -> String? {
        keychain.get(for: id)
    }

    private func storeKeySilently(_ key: String?, for id: UUID) {
        guard let key, !key.isEmpty else { return }
        try? keychain.set(key, for: id)
    }
}

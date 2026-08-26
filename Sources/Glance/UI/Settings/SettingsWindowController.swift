import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case translation
    case aiService
    case appearance
    case general
}

/// Standard titled window hosting the SwiftUI settings tabs.
/// Created lazily by AppDelegate; ⌘, opens it (wired through MenuBarController).
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private var selectedTab: SettingsTab = .translation {
        didSet {
            rootViewModel.selectedTab = selectedTab
        }
    }
    private let rootViewModel: SettingsRootViewModel

    init(settings: SettingsStore, initialTab: SettingsTab = .translation) {
        self.settings = settings
        self.selectedTab = initialTab
        let model = SettingsRootViewModel(selectedTab: initialTab)
        self.rootViewModel = model
        let rootView = SettingsRootView(settings: settings, model: model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Glance Settings"
        window.minSize = NSSize(width: 800, height: 540)
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func select(tab: SettingsTab) {
        rootViewModel.selectedTab = tab
    }
}

final class SettingsRootViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .translation) {
        self.selectedTab = selectedTab
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: SettingsRootViewModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            TranslationTab(settings: settings)
                .tabItem { Label("Translation", systemImage: "character.bubble") }
                .tag(SettingsTab.translation)

            EndpointsTab(settings: settings)
                .tabItem { Label("AI Service", systemImage: "cpu") }
                .tag(SettingsTab.aiService)

            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush.fill") }
                .tag(SettingsTab.appearance)

            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .frame(minWidth: 800, minHeight: 540)
    }
}

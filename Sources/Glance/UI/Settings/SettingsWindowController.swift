import AppKit
import SwiftUI

/// Standard titled window hosting the SwiftUI settings tabs.
/// Created lazily by AppDelegate; ⌘, opens it (wired through MenuBarController).
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore) {
        let rootView = SettingsRootView(settings: settings)
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
}

struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush.fill") }
            EndpointsTab(settings: settings)
                .tabItem { Label("Endpoints", systemImage: "network") }
            HotkeyTab(settings: settings)
                .tabItem { Label("Hotkey", systemImage: "command.square") }
        }
        .frame(minWidth: 800, minHeight: 540)
    }
}

import AppKit

// Entry point for the Glance executable target.
// We drive NSApplication manually (instead of SwiftUI @main App) because the
// app is an accessory (menu-bar-only) application and we want explicit control
// over activation policy before the run loop starts.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // regular app: shows Dock icon and supports ⌘+Tab switcher

if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
   let iconImage = NSImage(contentsOf: iconURL) {
    app.applicationIconImage = iconImage
}

app.run()


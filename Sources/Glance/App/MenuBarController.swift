import AppKit
import SwiftUI

/// Owns the NSStatusItem in the macOS menu bar.
/// Presents a streamlined, native control center menu for immediate switching of
/// AI Service, Target Language, Tone & Style, triggering capture, and accessing
/// the Glance Main Window & Settings.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let historyStore: HistoryStore?
    private let menu: NSMenu

    var onShowSettings: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onTriggerCapture: (() -> Void)?
    var onTriggerRepeatCapture: (() -> Void)?

    init(settings: SettingsStore, historyStore: HistoryStore? = nil) {
        self.settings = settings
        self.historyStore = historyStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        super.init()

        menu.delegate = self
        menu.autoenablesItems = false

        configureButton()
    }

    // MARK: - Status Item Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = Self.makeMenuBarIcon()
        image.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Primary menu bar status icon: custom minimalist viewfinder frame enclosing the '文' character.
    static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            let pad: CGFloat = 1.0
            let vfRect = bounds.insetBy(dx: pad, dy: pad)
            
            let bracketLen: CGFloat = 4.0
            let bracketRadius: CGFloat = 2.0
            let lineWidth: CGFloat = 1.35
            
            ctx.saveGState()
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.black.cgColor)
            
            // Top-Left Bracket
            let tl = CGMutablePath()
            tl.move(to: CGPoint(x: vfRect.minX, y: vfRect.maxY - bracketLen))
            tl.addArc(tangent1End: CGPoint(x: vfRect.minX, y: vfRect.maxY),
                      tangent2End: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.maxY),
                      radius: bracketRadius)
            tl.addLine(to: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.maxY))
            ctx.addPath(tl)
            ctx.strokePath()
            
            // Top-Right Bracket
            let tr = CGMutablePath()
            tr.move(to: CGPoint(x: vfRect.maxX - bracketLen, y: vfRect.maxY))
            tr.addArc(tangent1End: CGPoint(x: vfRect.maxX, y: vfRect.maxY),
                      tangent2End: CGPoint(x: vfRect.maxX, y: vfRect.maxY - bracketLen),
                      radius: bracketRadius)
            tr.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.maxY - bracketLen))
            ctx.addPath(tr)
            ctx.strokePath()
            
            // Bottom-Left Bracket
            let bl = CGMutablePath()
            bl.move(to: CGPoint(x: vfRect.minX, y: vfRect.minY + bracketLen))
            bl.addArc(tangent1End: CGPoint(x: vfRect.minX, y: vfRect.minY),
                      tangent2End: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.minY),
                      radius: bracketRadius)
            bl.addLine(to: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.minY))
            ctx.addPath(bl)
            ctx.strokePath()
            
            // Bottom-Right Bracket
            let br = CGMutablePath()
            br.move(to: CGPoint(x: vfRect.maxX - bracketLen, y: vfRect.minY))
            br.addArc(tangent1End: CGPoint(x: vfRect.maxX, y: vfRect.minY),
                      tangent2End: CGPoint(x: vfRect.maxX, y: vfRect.minY + bracketLen),
                      radius: bracketRadius)
            br.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.minY + bracketLen))
            ctx.addPath(br)
            ctx.strokePath()
            
            ctx.restoreGState()
            
            // Central '文' typography character
            let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: "文", attributes: attrs)
            let strSize = str.size()
            let strRect = NSRect(
                x: bounds.midX - strSize.width / 2.0,
                y: bounds.midY - strSize.height / 2.0 - 0.25,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect)
            
            return true
        }
        return img
    }

    /// Toggles the menu bar icon between normal template mode and an active amber tint
    /// to signal that a capture or translation is actively running.
    func setBusy(_ busy: Bool) {
        guard let button = statusItem.button else { return }
        if busy {
            button.image = Self.makeBusyIcon()
            button.image?.isTemplate = false
        } else {
            button.image = Self.makeMenuBarIcon()
            button.image?.isTemplate = true
        }
    }

    private static func makeBusyIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            let pad: CGFloat = 1.0
            let vfRect = bounds.insetBy(dx: pad, dy: pad)
            let bracketLen: CGFloat = 4.0
            let bracketRadius: CGFloat = 2.0
            let lineWidth: CGFloat = 1.35
            
            let orange = NSColor.systemOrange.cgColor
            
            ctx.saveGState()
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(orange)
            
            let tl = CGMutablePath()
            tl.move(to: CGPoint(x: vfRect.minX, y: vfRect.maxY - bracketLen))
            tl.addArc(tangent1End: CGPoint(x: vfRect.minX, y: vfRect.maxY),
                      tangent2End: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.maxY),
                      radius: bracketRadius)
            tl.addLine(to: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.maxY))
            ctx.addPath(tl)
            ctx.strokePath()
            
            let tr = CGMutablePath()
            tr.move(to: CGPoint(x: vfRect.maxX - bracketLen, y: vfRect.maxY))
            tr.addArc(tangent1End: CGPoint(x: vfRect.maxX, y: vfRect.maxY),
                      tangent2End: CGPoint(x: vfRect.maxX, y: vfRect.maxY - bracketLen),
                      radius: bracketRadius)
            tr.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.maxY - bracketLen))
            ctx.addPath(tr)
            ctx.strokePath()
            
            let bl = CGMutablePath()
            bl.move(to: CGPoint(x: vfRect.minX, y: vfRect.minY + bracketLen))
            bl.addArc(tangent1End: CGPoint(x: vfRect.minX, y: vfRect.minY),
                      tangent2End: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.minY),
                      radius: bracketRadius)
            bl.addLine(to: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.minY))
            ctx.addPath(bl)
            ctx.strokePath()
            
            let br = CGMutablePath()
            br.move(to: CGPoint(x: vfRect.maxX - bracketLen, y: vfRect.minY))
            br.addArc(tangent1End: CGPoint(x: vfRect.maxX, y: vfRect.minY),
                      tangent2End: CGPoint(x: vfRect.maxX, y: vfRect.minY + bracketLen),
                      radius: bracketRadius)
            br.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.minY + bracketLen))
            ctx.addPath(br)
            ctx.strokePath()
            
            ctx.restoreGState()
            
            let font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemOrange
            ]
            let str = NSAttributedString(string: "文", attributes: attrs)
            let strSize = str.size()
            let strRect = NSRect(
                x: bounds.midX - strSize.width / 2.0,
                y: bounds.midY - strSize.height / 2.0 - 0.25,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect)
            return true
        }
        return img
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        rebuildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Reset so next click invokes statusItemClicked again
    }

    // MARK: - Menu Construction

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // 1. Primary Actions
        let captureItem = NSMenuItem(
            title: "Capture & Translate (\(settings.hotkey.displayString))",
            action: #selector(triggerCaptureAction),
            keyEquivalent: ""
        )
        captureItem.target = self
        captureItem.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        menu.addItem(captureItem)

        let repeatCaptureItem = NSMenuItem(
            title: "Re-translate Last Area (\(settings.repeatHotkey.displayString))",
            action: #selector(triggerRepeatCaptureAction),
            keyEquivalent: ""
        )
        repeatCaptureItem.target = self
        repeatCaptureItem.image = NSImage(systemSymbolName: "arrow.clockwise.viewfinder", accessibilityDescription: nil)
        menu.addItem(repeatCaptureItem)

        let openMainItem = NSMenuItem(
            title: "Open Glance Main Window",
            action: #selector(openMainWindowAction),
            keyEquivalent: "o"
        )
        openMainItem.target = self
        openMainItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openMainItem)

        menu.addItem(.separator())

        // 2. AI Service Selection Submenu
        let activeEndpoint = settings.activeEndpoint()
        let aiServiceMenu = NSMenu(title: "AI Service")
        for endpoint in settings.endpoints {
            let item = NSMenuItem(
                title: endpoint.label,
                action: #selector(selectEndpointAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = endpoint.id
            if endpoint.id == activeEndpoint?.id {
                item.state = .on
            }
            aiServiceMenu.addItem(item)
        }

        if !settings.endpoints.isEmpty {
            aiServiceMenu.addItem(.separator())
        }

        let manageEndpointsItem = NSMenuItem(
            title: "Manage AI Services…",
            action: #selector(openSettingsAction),
            keyEquivalent: ""
        )
        manageEndpointsItem.target = self
        aiServiceMenu.addItem(manageEndpointsItem)

        let aiServiceTopItem = NSMenuItem(
            title: "AI Service: \(activeEndpoint?.label ?? "None Configured")",
            action: nil,
            keyEquivalent: ""
        )
        aiServiceTopItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        aiServiceTopItem.submenu = aiServiceMenu
        menu.addItem(aiServiceTopItem)

        // 3. Target Language Selection Submenu
        let langMenu = NSMenu(title: "Target Language")
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(
                title: lang.displayName,
                action: #selector(selectLanguageAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang
            if lang == settings.targetLanguage {
                item.state = .on
            }
            langMenu.addItem(item)
        }

        let langTopItem = NSMenuItem(
            title: "Target Language: \(settings.targetLanguage.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        langTopItem.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
        langTopItem.submenu = langMenu
        menu.addItem(langTopItem)

        // 4. Tone & Style Selection Submenu
        let toneMenu = NSMenu(title: "Tone & Style")
        for tone in TranslationTone.allCases {
            let item = NSMenuItem(
                title: tone.displayName,
                action: #selector(selectToneAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = tone
            if tone == settings.translationTone {
                item.state = .on
            }
            toneMenu.addItem(item)
        }

        let toneTopItem = NSMenuItem(
            title: "Tone & Style: \(settings.translationTone.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        toneTopItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        toneTopItem.submenu = toneMenu
        menu.addItem(toneTopItem)

        menu.addItem(.separator())

        // 5. Settings, Updates & Quit
        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesAction),
            keyEquivalent: "u"
        )
        checkUpdatesItem.target = self
        checkUpdatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(checkUpdatesItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Glance",
            action: #selector(quitAppAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func checkForUpdatesAction() {
        Task { @MainActor in
            await UpdateManager.shared.checkForUpdates(silent: false)
        }
    }

    @objc private func triggerCaptureAction() {
        onTriggerCapture?()
    }

    @objc private func triggerRepeatCaptureAction() {
        onTriggerRepeatCapture?()
    }

    @objc private func openMainWindowAction() {
        onShowHistory?()
    }

    @objc private func openSettingsAction() {
        onShowSettings?()
    }

    @objc private func quitAppAction() {
        NSApp.terminate(nil)
    }

    @objc private func selectEndpointAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        settings.setActiveEndpoint(id: id)
    }

    @objc private func selectLanguageAction(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? AppLanguage else { return }
        settings.targetLanguage = lang
    }

    @objc private func selectToneAction(_ sender: NSMenuItem) {
        guard let tone = sender.representedObject as? TranslationTone else { return }
        settings.translationTone = tone
    }
}

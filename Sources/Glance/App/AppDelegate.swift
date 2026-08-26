import AppKit
import Combine

/// Top-level application delegate: owns the menu bar controller and the
/// lazily-created settings window; routes actions between them.
///
/// Also installs a minimal main menu. This is REQUIRED even for accessory apps:
/// ⌘C/⌘X/⌘V/⌘A are dispatched through Edit-menu items, so without an Edit menu
/// every text field silently rejects standard clipboard shortcuts.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var busyFlashTask: Task<Void, Never>?
    private var captureCoordinator: CaptureCoordinator?
    private var historyStore: HistoryStore?
    /// Strong ownership required — coordinator and hover bridge hold only weak refs
    /// (M3.1: local variable was deallocated immediately, panel never showed).
    private var resultPanel: ResultPanelController?
    private var historyWindowController: HistoryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        // Register with TCC immediately so Glance shows up in System Settings →
        // Screen Recording without needing a hotkey press first (M2.5).
        _ = CGRequestScreenCaptureAccess()

        // Initialize notification subsystem with actionable categories
        NotificationService.shared.setup()
        NotificationService.shared.onOpenSnapshot = { [weak self] id in
            self?.showHistory(selectedID: id)
        }

        setupHistoryStore()
        setupGlobalHotkey()

        // Launch directly with the Glance Main Window front and center
        showHistory()

        // Proactively open Settings on the AI Service tab if no endpoints are configured yet
        if settings.endpoints.isEmpty {
            showSettings(tab: .aiService)
        }

        // Automatically check for updates in the background if enabled
        if settings.automaticallyCheckForUpdates {
            Task {
                await UpdateManager.shared.checkForUpdates(silent: true)
            }
        }
    }

    // MARK: - Capture

    /// Opens the persistence store and wires the hotkey → capture → save pipeline.
    private func setupHistoryStore() {
        do {
            let store = try HistoryStore()
            historyStore = store
            NSLog("Glance: history store ready at \(store.rootDirectory.path), \(try store.count()) snapshots")

            let controller = MenuBarController(settings: settings, historyStore: store)
            controller.onShowSettings = { [weak self] in self?.showSettings() }
            controller.onShowHistory = { [weak self] in self?.showHistory() }
            controller.onTriggerCapture = { [weak self] in
                self?.captureCoordinator?.beginSelection()
            }
            controller.onTriggerRepeatCapture = { [weak self] in
                self?.captureCoordinator?.beginRepeatCapture()
            }
            menuBarController = controller

            let panel = ResultPanelController()
            panel.onOpenHistory = { [weak self] id in self?.showHistory(selectedID: id) }
            self.resultPanel = panel
            PanelHoverBridge.shared.controller = panel

            let coordinator = CaptureCoordinator(historyStore: store, settings: settings)
            coordinator.resultPanel = panel
            coordinator.onCaptureSaved = { [weak self] in
                self?.flashIcon(ms: 400)
            }
            coordinator.onSelectionCancelled = { [weak self] in
                self?.flashIcon(ms: 0)
            }
            coordinator.onTranslateStart = { [weak self] in
                self?.menuBarController?.setBusy(true)
            }
            coordinator.onTranslateEnd = { [weak self] in
                self?.menuBarController?.setBusy(false)
            }
            captureCoordinator = coordinator
        } catch {
            // Capture cannot work without persistence; keep the app alive but log loudly.
            NSLog("Glance: FATAL — could not open history store: \(error)")
        }
    }

    /// Registers the configured hotkeys now and re-registers whenever they change.
    private func setupGlobalHotkey() {
        HotkeyManager.shared.onKeyDown = { [weak self] in
            self?.captureCoordinator?.beginSelection()
        }
        HotkeyManager.shared.onRepeatKeyDown = { [weak self] in
            self?.captureCoordinator?.beginRepeatCapture()
        }

        Publishers.CombineLatest(settings.$hotkey, settings.$repeatHotkey)
            .removeDuplicates { prev, curr in
                prev.0 == curr.0 && prev.1 == curr.1
            }
            .receive(on: DispatchQueue.main)
            .sink { captureCombo, repeatCombo in
                HotkeyManager.shared.register(capture: captureCombo, repeatCapture: repeatCombo)
                NSLog("Glance: hotkeys registered → primary: \(captureCombo.displayString), repeat: \(repeatCombo.displayString)")
            }
            .store(in: &cancellables)
    }

    /// Brief amber flash of the menu bar icon so captures are visibly acknowledged.
    private func flashIcon(ms: Int) {
        guard let controller = menuBarController, ms > 0 else {
            busyFlashTask?.cancel()
            menuBarController?.setBusy(false)
            return
        }
        busyFlashTask?.cancel()
        busyFlashTask = Task { @MainActor in
            controller.setBusy(true)
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            if !Task.isCancelled {
                controller.setBusy(false)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Closing history or settings window must not terminate the background daemon
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showHistory()
        }
        return true
    }

    // MARK: - Windows

    private func showSettings(tab: SettingsTab = .translation) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings, initialTab: tab)
        } else {
            settingsWindowController?.select(tab: tab)
        }
        guard let window = settingsWindowController?.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showHistory(selectedID: UUID? = nil) {
        if historyWindowController == nil, let store = historyStore {
            let controller = HistoryWindowController(historyStore: store, settings: settings)
            controller.onShowSettings = { [weak self] in self?.showSettings() }
            historyWindowController = controller
        }
        if let selectedID {
            historyWindowController?.selectSnapshot(id: selectedID)
        }
        guard let window = historyWindowController?.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Main menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        // Application menu (required first slot).
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Glance")
        appMenu.addItem(NSMenuItem(title: "About Glance",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Glance",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu

        // Edit menu — restores clipboard + undo shortcuts for all text fields.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo",
                                    action: Selector(("undo:")),
                                    keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo",
                                    action: Selector(("redo:")),
                                    keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",
                                    action: #selector(NSText.cut(_:)),
                                    keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",
                                    action: #selector(NSText.copy(_:)),
                                    keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",
                                    action: #selector(NSText.paste(_:)),
                                    keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All",
                                    action: #selector(NSText.selectAll(_:)),
                                    keyEquivalent: "a"))
        editItem.submenu = editMenu

        // Window menu (minimize support while a window is open).
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize",
                                      action: #selector(NSWindow.performMiniaturize(_:)),
                                      keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close Window",
                                      action: #selector(NSWindow.performClose(_:)),
                                      keyEquivalent: "w"))
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}

import Foundation
import Carbon.HIToolbox

/// Registers the global hotkey via Carbon Event Manager (no Accessibility
/// permission required) and forwards presses to `onKeyDown`.
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Called on the main thread when the registered combo is pressed.
    var onKeyDown: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    /// Replaces any existing registration. Safe to call repeatedly.
    func register(_ combo: HotkeyCombo) {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C4E43), // 'GLNC'
                                     id: 1)
        let status = RegisterEventHotKey(combo.keyCode,
                                         combo.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("Glance: RegisterEventHotKey failed (status \(status)) for \(combo.displayString)")
        }
    }

    func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // C-function-pointer context: no captures allowed, so route through singleton.
        let callback: EventHandlerUPP = { _, _, _ in
            HotkeyManager.shared.onKeyDown?()
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &eventType,
                                         nil,
                                         nil)
        handlerInstalled = (status == noErr)
        if !handlerInstalled {
            NSLog("Glance: InstallEventHandler failed (status \(status))")
        }
    }
}

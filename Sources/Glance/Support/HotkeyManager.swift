import Foundation
import Carbon.HIToolbox

/// Registers global hotkeys via Carbon Event Manager (no Accessibility
/// permission required) and forwards presses to `onKeyDown` and `onRepeatKeyDown`.
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Called when the primary capture combo (e.g. ⌥G) is pressed.
    var onKeyDown: (() -> Void)?
    /// Called when the repeat capture combo (e.g. ⇧⌥G) is pressed.
    var onRepeatKeyDown: (() -> Void)?

    private var captureHotKeyRef: EventHotKeyRef?
    private var repeatHotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    private let signature = OSType(0x474C4E43) // 'GLNC'

    private init() {}

    /// Registers both the primary capture combo and repeat capture combo.
    func register(capture: HotkeyCombo, repeatCapture: HotkeyCombo) {
        unregister()
        installHandlerIfNeeded()

        // 1. Register Primary Capture Hotkey (ID 1)
        var capRef: EventHotKeyRef?
        let capID = EventHotKeyID(signature: signature, id: 1)
        let capStatus = RegisterEventHotKey(capture.keyCode,
                                            capture.carbonModifiers,
                                            capID,
                                            GetApplicationEventTarget(),
                                            0,
                                            &capRef)
        if capStatus == noErr {
            captureHotKeyRef = capRef
        } else {
            NSLog("Glance: RegisterEventHotKey primary failed (status \(capStatus)) for \(capture.displayString)")
        }

        // 2. Register Repeat Capture Hotkey (ID 2)
        var repRef: EventHotKeyRef?
        let repID = EventHotKeyID(signature: signature, id: 2)
        let repStatus = RegisterEventHotKey(repeatCapture.keyCode,
                                            repeatCapture.carbonModifiers,
                                            repID,
                                            GetApplicationEventTarget(),
                                            0,
                                            &repRef)
        if repStatus == noErr {
            repeatHotKeyRef = repRef
        } else {
            NSLog("Glance: RegisterEventHotKey repeat failed (status \(repStatus)) for \(repeatCapture.displayString)")
        }
    }

    func unregister() {
        if let ref = captureHotKeyRef {
            UnregisterEventHotKey(ref)
            captureHotKeyRef = nil
        }
        if let ref = repeatHotKeyRef {
            UnregisterEventHotKey(ref)
            repeatHotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // C-function-pointer context: no captures allowed, so route through singleton.
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            if status == noErr {
                if hotKeyID.id == 1 {
                    HotkeyManager.shared.onKeyDown?()
                } else if hotKeyID.id == 2 {
                    HotkeyManager.shared.onRepeatKeyDown?()
                }
            }
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

import AppKit
import Combine

/// Drives the "recording" state of the hotkey recorder: installs a local
/// NSEvent monitor while recording (app-active only), validates combos, and
/// reports either a committed combo or cancellation via Esc.
@MainActor
final class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var onCombo: ((HotkeyCombo) -> Void)?
    private var onCancel: (() -> Void)?

    func startRecording(onCombo: @escaping (HotkeyCombo) -> Void,
                        onCancel: @escaping () -> Void) {
        stopRecording()
        self.onCombo = onCombo
        self.onCancel = onCancel

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }

            // Esc always cancels recording.
            if event.keyCode == UInt16(HotkeyCombo.escapeKeyCode) {
                self.finish()
                self.onCancel?()
                return nil
            }

            // Require at least one of ⌘/⌥/⌃ — otherwise ignore and keep listening.
            guard let modifiers = HotkeyCombo.validatedCarbonModifiers(from: event.modifierFlags) else {
                return nil
            }

            let combo = HotkeyCombo(keyCode: UInt32(event.keyCode),
                                    carbonModifiers: modifiers)
            self.finish()
            self.onCombo?(combo)
            return nil
        }
        isRecording = monitor != nil
    }

    func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    private func finish() {
        stopRecording()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

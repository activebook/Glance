import SwiftUI

/// Hotkey settings: shows active shortcuts for Primary Capture and Re-translate Last Region,
/// supporting click-to-record and reset-to-default.
struct HotkeyTab: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder = HotkeyRecorderModel()
    @State private var activeTarget: RecordingTarget?

    enum RecordingTarget {
        case primary
        case repeatCapture
    }

    var body: some View {
        Form {
            // 1. Primary Selection & Capture Hotkey
            Section("Primary Capture & Translate") {
                HStack(spacing: 16) {
                    keyCap(
                        combo: settings.hotkey,
                        isTargetActive: activeTarget == .primary && recorder.isRecording,
                        target: .primary
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeTarget == .primary && recorder.isRecording
                             ? "Type a new shortcut… (Esc to cancel)"
                             : "Interactive selection overlay & window snapping.")
                            .font(.system(size: 12))
                            .foregroundStyle(activeTarget == .primary && recorder.isRecording ? Color.orange : Color.secondary)
                        Text("Default: ⌥G (Option + G). Opens crosshairs to drag a marquee or click a window.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button("Reset to Default") {
                        commit(HotkeyCombo.default, for: .primary)
                    }
                    .disabled((activeTarget == .primary && recorder.isRecording) || settings.hotkey == .default)
                }
                .padding(.vertical, 4)
            }

            // 2. Re-translate Last Region Hotkey
            Section("Re-translate Last Region (Lock Capture)") {
                HStack(spacing: 16) {
                    keyCap(
                        combo: settings.repeatHotkey,
                        isTargetActive: activeTarget == .repeatCapture && recorder.isRecording,
                        target: .repeatCapture
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeTarget == .repeatCapture && recorder.isRecording
                             ? "Type a new shortcut… (Esc to cancel)"
                             : "Instantly captures the previous region without overlay.")
                            .font(.system(size: 12))
                            .foregroundStyle(activeTarget == .repeatCapture && recorder.isRecording ? Color.orange : Color.secondary)
                        Text("Default: ⇧⌥G (Shift + Option + G). Ideal for streaming subtitles, visual novels, and manga.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button("Reset to Default") {
                        commit(HotkeyCombo.defaultRepeat, for: .repeatCapture)
                    }
                    .disabled((activeTarget == .repeatCapture && recorder.isRecording) || settings.repeatHotkey == .defaultRepeat)
                }
                .padding(.vertical, 4)
            }

            Section("Instructions & Tips") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• **Primary Capture (⌥G)**: Darkens the screen to drag a new selection rectangle or click an auto-detected window.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("• **Re-translate Last Region (⇧⌥G)**: Automatically remembers your last bounding box and instantly translates updated content in that exact area with zero screen darkening.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("• Valid shortcuts must include at least one modifier: ⌘ (Command), ⌥ (Option), or ⌃ (Control).")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Key cap

    private func keyCap(combo: HotkeyCombo, isTargetActive: Bool, target: RecordingTarget) -> some View {
        Button {
            if isTargetActive {
                recorder.stopRecording()
                activeTarget = nil
            } else {
                activeTarget = target
                recorder.startRecording(
                    onCombo: { newCombo in
                        commit(newCombo, for: target)
                    },
                    onCancel: {
                        activeTarget = nil
                    }
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isTargetActive ? "dot.radiowaves.left.and.right" : "command.square")
                    .font(.system(size: 13))
                Text(isTargetActive ? "…" : combo.displayString)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 56)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .stroke(isTargetActive ? Color.orange : Color(nsColor: .separatorColor),
                            lineWidth: isTargetActive ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func commit(_ combo: HotkeyCombo, for target: RecordingTarget) {
        recorder.stopRecording()
        activeTarget = nil
        switch target {
        case .primary:
            settings.hotkey = combo
        case .repeatCapture:
            settings.repeatHotkey = combo
        }
    }
}

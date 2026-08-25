import SwiftUI

/// Hotkey settings: shows the active combo in a key-cap, supports click-to-record,
/// and reset-to-default. Registration is handled by AppDelegate observing the store.
struct HotkeyTab: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder = HotkeyRecorderModel()

    var body: some View {
        Form {
            Section("Global Capture Hotkey") {
                HStack(spacing: 16) {
                    keyCap
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recorder.isRecording
                             ? "Type a new shortcut… (Esc to cancel)"
                             : "Press this combo anywhere to capture.")
                            .font(.system(size: 12))
                            .foregroundStyle(recorder.isRecording ? Color.orange : Color.secondary)
                        Text("Must include at least one of ⌘ / ⌥ / ⌃ (Shift alone is not allowed).")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Reset to Default") {
                        commit(HotkeyCombo.default)
                    }
                    .disabled(!recorder.isRecording && settings.hotkey == .default)
                    .disabled(recorder.isRecording) // finish recording first
                }
                .padding(.vertical, 4)

                LabeledContent("Behavior", content: {
                    Text("No region locked → opens crosshair selection. "
                       + "Region locked → instantly captures inside it. "
                       + "Capture pipeline arrives in M2; the press is currently acknowledged "
                       + "with a brief menu-bar icon flash.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                })
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Key cap

    private var keyCap: some View {
        Button {
            if recorder.isRecording {
                recorder.stopRecording()
            } else {
                recorder.startRecording(
                    onCombo: { combo in commit(combo) },
                    onCancel: { }
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: recorder.isRecording ? "dot.radiowaves.left.and.right" : "command.square")
                    .font(.system(size: 13))
                Text(recorder.isRecording ? "…" : settings.hotkey.displayString)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 56)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .stroke(recorder.isRecording ? Color.orange : Color(nsColor: .separatorColor),
                            lineWidth: recorder.isRecording ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func commit(_ combo: HotkeyCombo) {
        recorder.stopRecording()
        settings.hotkey = combo
    }
}

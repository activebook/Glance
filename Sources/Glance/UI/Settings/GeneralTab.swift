import SwiftUI
import ServiceManagement

/// General settings: target translation language, tone, auto-dismiss timeout,
/// delivery options, and launch-at-login.
struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Translation") {
                Picker("Target Language", selection: $settings.targetLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker("Tone & Style", selection: $settings.translationTone) {
                    ForEach(TranslationTone.allCases) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }

                LabeledContent("Result panel auto-dismiss") {
                    HStack(spacing: 8) {
                        Text("\(Int(settings.resultPanelTimeout)) s")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Stepper("", value: $settings.resultPanelTimeout, in: 5...30, step: 1)
                            .labelsHidden()
                    }
                }
            }

            Section("Delivery & Feedback") {
                Toggle("Show system notification on completion", isOn: $settings.enableNotifications)
                Toggle("Play sound on completion", isOn: $settings.playNotificationSound)
                    .disabled(!settings.enableNotifications)
                Toggle("Automatically copy translation to clipboard", isOn: $settings.autoCopyToClipboard)
            }

            Section("Startup") {
                Toggle("Launch Glance at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { enabled in setLoginItem(enabled: enabled) }
                ))
                Text("Requires the app bundle to stay at a stable path (e.g. /Applications/Glance.app).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Glance: failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }
}

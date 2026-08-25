import SwiftUI
import ServiceManagement

/// General settings: target translation language, tone, auto-dismiss timeout,
/// delivery options, and launch-at-login.
struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateManager = UpdateManager.shared

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

            Section("Software Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Glance for macOS")
                            .font(.system(size: 13, weight: .medium))

                        HStack(spacing: 6) {
                            Text("Version \(updateManager.currentVersion) (Build \(updateManager.currentBuild))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if case .upToDate = updateManager.state {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text("Latest version")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(.green)
                            } else if case .updateAvailable(let release) = updateManager.state {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.green).frame(width: 5, height: 5)
                                    Text("\(release.tag_name) Available")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(.indigo)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        if case .updateAvailable = updateManager.state {
                            updateManager.showUpdateModal = true
                        } else {
                            Task { await updateManager.checkForUpdates(silent: false) }
                        }
                    } label: {
                        if updateManager.state == .checking {
                            ProgressView()
                                .controlSize(.small)
                        } else if case .updateAvailable = updateManager.state {
                            Text("Update Now…")
                        } else {
                            Text("Check for Updates…")
                        }
                    }
                    .disabled(updateManager.state == .checking)
                }

                Toggle("Automatically check for updates on launch", isOn: $settings.automaticallyCheckForUpdates)
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
        .toggleStyle(.switch)
        .sheet(isPresented: $updateManager.showUpdateModal) {
            UpdateModalView()
        }
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

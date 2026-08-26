import SwiftUI

/// Settings for Translation shortcuts, target languages, style/tone personas,
/// result HUD auto-dismiss timing, and TTS speech synthesis.
struct TranslationTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ttsManager = TTSManager.shared
    @StateObject private var recorder = HotkeyRecorderModel()
    @State private var activeRecordingTarget: RecordingTarget?

    enum RecordingTarget {
        case primary
        case repeatCapture
    }

    var body: some View {
        Form {
            // 1. Global Shortcuts Section
            Section("Global Shortcuts") {
                // Primary capture
                HStack(spacing: 16) {
                    keyCap(
                        combo: settings.hotkey,
                        isTargetActive: activeRecordingTarget == .primary && recorder.isRecording,
                        target: .primary
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(activeRecordingTarget == .primary && recorder.isRecording
                             ? "Type a new shortcut… (Esc to cancel)"
                             : "Capture & Translate")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(activeRecordingTarget == .primary && recorder.isRecording ? Color.orange : Color.primary)
                        Text("Select any area or window on your screen to translate.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset") {
                        commit(HotkeyCombo.default, for: .primary)
                    }
                    .disabled((activeRecordingTarget == .primary && recorder.isRecording) || settings.hotkey == .default)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)

                // Repeat / Lock capture
                HStack(spacing: 16) {
                    keyCap(
                        combo: settings.repeatHotkey,
                        isTargetActive: activeRecordingTarget == .repeatCapture && recorder.isRecording,
                        target: .repeatCapture
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(activeRecordingTarget == .repeatCapture && recorder.isRecording
                             ? "Type a new shortcut… (Esc to cancel)"
                             : "Re-translate Last Area")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(activeRecordingTarget == .repeatCapture && recorder.isRecording ? Color.orange : Color.primary)
                        Text("Instantly translates the same area again — perfect for video subtitles, manga, and reading.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset") {
                        commit(HotkeyCombo.defaultRepeat, for: .repeatCapture)
                    }
                    .disabled((activeRecordingTarget == .repeatCapture && recorder.isRecording) || settings.repeatHotkey == .defaultRepeat)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }

            // 2. Translation & Style Section
            Section("Translation & Style") {
                Picker("Target Language", selection: $settings.targetLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Picker("Tone & Persona", selection: $settings.translationTone) {
                        ForEach(TranslationTone.allCases) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }

                    Text(settings.translationTone.useCase)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .animation(.easeInOut(duration: 0.15), value: settings.translationTone)
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

            // 3. Speech & Audio Section
            Section("Speech & Audio (Text-to-Speech)") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Engine", selection: $settings.ttsEngine) {
                        ForEach(TTSEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }

                    Text(settings.ttsEngine.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }

                LabeledContent("Speech Speed") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.ttsRate, in: 0.5...1.5, step: 0.05)
                            .frame(width: 140)

                        Text(String(format: "%.2fx", settings.ttsRate))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }

                HStack {
                    Text("Voice: \(TTSEngine.defaultVoice(for: settings.targetLanguage))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        if ttsManager.isPlaying {
                            ttsManager.stop()
                        } else {
                            ttsManager.preview(engine: settings.ttsEngine, rate: settings.ttsRate, language: settings.targetLanguage)
                        }
                    } label: {
                        if ttsManager.isPlaying {
                            Label("Stop", systemImage: "square.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red)
                        } else if ttsManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Preview Voice", systemImage: "speaker.wave.2.fill")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(ttsManager.isPlaying ? "Stop audio preview" : "Listen to sample pronunciation")
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    // MARK: - Key cap helper

    private func keyCap(combo: HotkeyCombo, isTargetActive: Bool, target: RecordingTarget) -> some View {
        Button {
            if isTargetActive {
                recorder.stopRecording()
                activeRecordingTarget = nil
            } else {
                activeRecordingTarget = target
                recorder.startRecording(
                    onCombo: { newCombo in
                        commit(newCombo, for: target)
                    },
                    onCancel: {
                        activeRecordingTarget = nil
                    }
                )
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isTargetActive ? "dot.radiowaves.left.and.right" : "command.square")
                    .font(.system(size: 12))
                Text(isTargetActive ? "…" : combo.displayString)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 48)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .stroke(isTargetActive ? Color.orange : Color(nsColor: .separatorColor),
                            lineWidth: isTargetActive ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Click to record shortcut")
    }

    private func commit(_ combo: HotkeyCombo, for target: RecordingTarget) {
        recorder.stopRecording()
        activeRecordingTarget = nil
        switch target {
        case .primary:
            settings.hotkey = combo
        case .repeatCapture:
            settings.repeatHotkey = combo
        }
    }
}

import SwiftUI

/// Settings for translation target language, style/tone personas, TTS speech synthesis,
/// and result HUD auto-dismiss timing.
struct TranslationTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ttsManager = TTSManager.shared

    var body: some View {
        Form {
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
}

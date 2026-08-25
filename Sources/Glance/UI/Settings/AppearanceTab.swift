import SwiftUI

/// Dedicated Appearance settings tab for customizing the floating translation popup theme,
/// typography font sizes, text color palettes, and previewing the live mockup.
struct AppearanceTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Section: Visual Themes
                VStack(alignment: .leading, spacing: 10) {
                    Text("Popup Window Theme")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(HUDAppearanceStyle.allCases) { style in
                            themeCard(style)
                        }
                    }

                    // Opacity control (0% to 100%)
                    HStack(spacing: 16) {
                        Text("Window Opacity")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Slider(value: $settings.hudOpacity, in: 0.0...1.0, step: 0.05)
                            .frame(maxWidth: 240)

                        Text("\(Int(settings.hudOpacity * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.top, 4)
                }

                Divider().opacity(0.5)

                // Section: Typography & Color Palettes
                VStack(alignment: .leading, spacing: 14) {
                    Text("Typography & Colors")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    // Original text styling
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Original Text")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Stepper("Size: \(Int(settings.sourceFontSize)) pt",
                                    value: $settings.sourceFontSize,
                                    in: 10...22,
                                    step: 1)
                        }

                        // Interactive Color Palette Swatches + macOS ColorPicker
                        HStack(spacing: 8) {
                            ForEach(ColorOption.allCases) { opt in
                                colorSwatchButton(option: opt, selection: $settings.sourceTextColor)
                            }

                            Divider().frame(height: 18).padding(.horizontal, 2)

                            ColorPicker("", selection: Binding(
                                get: { settings.sourceTextColor.color },
                                set: { settings.sourceTextColor = ColorOption(color: $0) }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .help("Custom color picker & screen eyedropper")
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )

                    // Translated text styling
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Translated Text")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Stepper("Size: \(Int(settings.translatedFontSize)) pt",
                                    value: $settings.translatedFontSize,
                                    in: 11...26,
                                    step: 1)
                        }

                        // Interactive Color Palette Swatches + macOS ColorPicker
                        HStack(spacing: 8) {
                            ForEach(ColorOption.allCases) { opt in
                                colorSwatchButton(option: opt, selection: $settings.translatedTextColor)
                            }

                            Divider().frame(height: 18).padding(.horizontal, 2)

                            ColorPicker("", selection: Binding(
                                get: { settings.translatedTextColor.color },
                                set: { settings.translatedTextColor = ColorOption(color: $0) }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .help("Custom color picker & screen eyedropper")
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                }

                Divider().opacity(0.5)

                // Section: Live Popup Window Preview
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Popup Window Preview")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Simulates desktop popup appearance")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    livePopupMockup
                }
            }
            .padding(24)
        }
    }

    // MARK: - Color Swatch Button

    private func colorSwatchButton(option: ColorOption, selection: Binding<ColorOption>) -> some View {
        let isSelected = selection.wrappedValue.hex == option.hex
        return Button {
            selection.wrappedValue = option
        } label: {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                    )

                if isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(option.displayName)
    }

    // MARK: - Theme Selection Card

    private func themeCard(_ style: HUDAppearanceStyle) -> some View {
        let isSelected = settings.hudAppearanceStyle == style

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                settings.hudAppearanceStyle = style
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style.borderStrokeColor, lineWidth: 1)
                        .background(style.previewBackgroundView(opacity: settings.hudOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(width: 44, height: 44)

                    Image(systemName: style.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(style.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(style.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                  lineWidth: isSelected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Popup Mockup

    private var livePopupMockup: some View {
        ZStack {
            // Elegant, clean, high-contrast ambient backdrop canvas
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.28, blue: 0.52), // deep cobalt
                    Color(red: 0.46, green: 0.22, blue: 0.48), // plum purple
                    Color(red: 0.14, green: 0.40, blue: 0.48)  // deep teal
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                // Subtle desktop window lines beneath the popup for realistic glassmorphism
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.24)).frame(width: 140, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.16)).frame(width: 220, height: 7)
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12)).frame(width: 180, height: 7)
                }
                .padding(20),
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Proportional Floating Popup Window Box
            VStack(spacing: 0) {
                // Top countdown line
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: 2)

                // Translation Content Body (Japanese -> English Example)
                VStack(alignment: .leading, spacing: 6) {
                    Text("シンプルで美しいデザインは、最高のユーザー体験を生み出します。")
                        .font(.system(size: settings.sourceFontSize, weight: .regular))
                        .foregroundStyle(settings.sourceTextColor.color)
                        .lineLimit(2)

                    Text("Simple and beautiful design creates the best user experience.")
                        .font(.system(size: settings.translatedFontSize, weight: .medium))
                        .foregroundStyle(settings.translatedTextColor.color)
                        .lineLimit(2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().opacity(0.25)

                // Footer status bar
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(.secondary)
                    Image(systemName: "speaker.wave.2").font(.system(size: 10)).foregroundStyle(.secondary)
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10)).foregroundStyle(.secondary)

                    Spacer()

                    let modelLabel = settings.activeEndpoint()?.model ?? "gemini-flash"
                    Text("\(modelLabel) · 180ms")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .frame(width: 370)
            .background(settings.hudAppearanceStyle.previewBackgroundView(opacity: settings.hudOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(settings.hudAppearanceStyle.borderStrokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.40), radius: 14, x: 0, y: 6)
        }
    }
}

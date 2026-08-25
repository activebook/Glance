import AppKit
import SwiftUI
import AVFoundation

/// What the floating panel displays for one finished or in-flight translation.
enum ResultPanelContent {
    case processing(targetLanguage: String)
    case items([TranslationItem])
    case empty
    case failure(String)

    struct Meta {
        let endpointLabel: String?
        let model: String?
        let latencyMs: Int?
    }
}

/// Non-activating floating panel that appears beside a capture with the
/// translation. Features configurable blur/translucency appearance, visual countdown,
/// text-to-speech, and rich quick actions.
final class ResultPanelController {
    private let panel: NSPanel
    private var dismissWorkItem: DispatchWorkItem?
    private var currentTimeout: TimeInterval = 10
    private var dismissStartTime: Date?
    private var remainingTime: TimeInterval = 10
    private var isHovered = false

    var onOpenHistory: ((UUID?) -> Void)?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
    }

    func show(content: ResultPanelContent,
              meta: ResultPanelContent.Meta,
              record: SnapshotRecord? = nil,
              near globalRect: CGRect,
              timeout: TimeInterval,
              style: HUDAppearanceStyle = .translucentDark,
              hudOpacity: Double = 0.85,
              sourceFontSize: Double = 12,
              sourceTextColor: ColorOption = .secondary,
              translatedFontSize: Double = 14,
              translatedTextColor: ColorOption = .primary,
              onRetry: (() -> Void)? = nil) {
        hide()
        isHovered = false
        currentTimeout = timeout
        remainingTime = timeout
        dismissStartTime = Date()

        // Size heuristics: minimum 320, max 480
        let width = min(480, max(320, globalRect.width + 80))
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.55

        let hosting = NSHostingView(
            rootView: ResultPanelView(
                content: content,
                meta: meta,
                record: record,
                timeout: timeout,
                style: style,
                hudOpacity: hudOpacity,
                sourceFontSize: sourceFontSize,
                sourceTextColor: sourceTextColor,
                translatedFontSize: translatedFontSize,
                translatedTextColor: translatedTextColor,
                onRetry: onRetry,
                onOpenHistory: { [weak self] id in
                    self?.hide()
                    self?.onOpenHistory?(id)
                }
            )
            .frame(width: width)
            .fixedSize(horizontal: true, vertical: false)
            .environment(\.dismissPanel, DismissPanelAction { [weak self] in self?.hide() })
        )

        panel.contentView = hosting
        let ideal = hosting.fittingSize
        let height = min(max(80, ideal.height), maxHeight)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.setContentSize(NSSize(width: width, height: height))

        // Position: right of capture rect; flip left if overflowing screen
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        var x = globalRect.maxX + 12
        if x + width > visibleFrame.maxX {
            x = globalRect.minX - width - 12
        }
        if x + width > visibleFrame.maxX { x = visibleFrame.maxX - width - 8 }
        if x < visibleFrame.minX { x = visibleFrame.minX + 8 }

        var y = globalRect.maxY - height
        y = max(visibleFrame.minY + 8, min(y, visibleFrame.maxY - height - 8))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()

        scheduleDismiss(after: timeout)
        installEscapeMonitor()
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitor = nil
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - Auto-dismiss

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWorkItem?.cancel()
        guard seconds > 0 else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovered else { return }
            self.hide()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Hover pauses the auto-dismiss timer; leaving resumes with grace period.
    func setHovering(_ hovering: Bool) {
        self.isHovered = hovering
        guard panel.isVisible else { return }
        if hovering {
            if let start = dismissStartTime {
                let elapsed = Date().timeIntervalSince(start)
                remainingTime = max(2, remainingTime - elapsed)
            }
            pauseDismiss()
        } else {
            resumeDismiss()
        }
    }

    private func pauseDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func resumeDismiss() {
        guard currentTimeout > 0 else { return }
        scheduleDismiss(after: max(2, remainingTime))
    }

    // MARK: - Keyboard monitors

    private var escapeMonitor: Any?

    private func installEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(HotkeyCombo.escapeKeyCode) {
                self?.hide()
                return nil
            }
            return event
        }
    }
}

// MARK: - SwiftUI Panel View

struct DismissPanelAction {
    let action: () -> Void
    func callAsFunction() { action() }
    func run() { action() }
}

private struct DismissPanelKey: EnvironmentKey {
    static let defaultValue = DismissPanelAction {}
}

extension EnvironmentValues {
    var dismissPanel: DismissPanelAction {
        get { self[DismissPanelKey.self] }
        set { self[DismissPanelKey.self] = newValue }
    }
}

struct ResultPanelView: View {
    let content: ResultPanelContent
    let meta: ResultPanelContent.Meta
    let record: SnapshotRecord?
    let timeout: TimeInterval
    let style: HUDAppearanceStyle
    let hudOpacity: Double
    let sourceFontSize: Double
    let sourceTextColor: ColorOption
    let translatedFontSize: Double
    let translatedTextColor: ColorOption
    let onRetry: (() -> Void)?
    let onOpenHistory: ((UUID?) -> Void)?

    @Environment(\.dismissPanel) private var dismiss
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var copiedText: String?
    @State private var copiedAll = false
    @State private var isHovered = false
    @State private var progress: CGFloat = 1.0

    private var isProcessing: Bool {
        if case .processing = content { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Countdown gauge bar (visible only when translation is finished)
            if !isProcessing {
                GeometryReader { geo in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * progress, height: 2.5)
                        .animation(.linear(duration: timeout), value: progress)
                }
                .frame(height: 2.5)
            }

            contentBody
                .frame(maxHeight: 280)

            Divider()
                .opacity(0.3)

            footer
        }
        .background(style.backgroundView(opacity: hudOpacity))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(style.borderStrokeColor, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 7)
        .onAppear {
            if !isProcessing {
                progress = 1.0
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: timeout)) {
                        progress = 0.0
                    }
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
            PanelHoverBridge.shared.controller?.setHovering(hovering)
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch content {
        case .processing(let targetLanguage):
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translating…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Target: \(targetLanguage)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)

        case .items(let items):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            // 1. Original Source Text (Always on top)
                            if !item.source.isEmpty {
                                Text(item.source)
                                    .font(.system(size: sourceFontSize, weight: .regular))
                                    .foregroundStyle(sourceTextColor.color)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                                    .lineSpacing(2)
                            }

                            // 2. Target Translated Text (Below original)
                            Text(item.translation.isEmpty ? " " : item.translation)
                                .font(.system(size: translatedFontSize, weight: .medium))
                                .foregroundStyle(translatedTextColor.color)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Copy Translation") { copy(item.translation) }
                            Button("Copy Original") { copy(item.source) }
                            Button(ttsManager.isPlaying && ttsManager.currentPlayingText == item.translation ? "Stop Audio" : "Pronounce Translation") {
                                if ttsManager.isPlaying && ttsManager.currentPlayingText == item.translation {
                                    ttsManager.stop()
                                } else {
                                    speak(item.translation)
                                }
                            }
                        }

                        if index < items.count - 1 {
                            Divider().opacity(0.18)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 280)

        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("No translatable text found")
                    .font(.system(size: 13, weight: .medium))
                if let onRetry {
                    Button("Try Again") { onRetry() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

        case .failure(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    Text("Translation failed")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let onRetry {
                        Button {
                            onRetry()
                        } label: {
                            Label("Retry", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(14)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case .items(let items) = content, !items.isEmpty {
                // Copy all
                Button {
                    copyAllItems(items)
                } label: {
                    Image(systemName: copiedAll ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copiedAll ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy all translations")

                // TTS Pronounce / Stop
                Button {
                    if ttsManager.isPlaying {
                        ttsManager.stop()
                    } else {
                        speakAllItems(items)
                    }
                } label: {
                    if ttsManager.isPlaying {
                        HStack(spacing: 3) {
                            Image(systemName: "square.fill")
                                .font(.system(size: 8))
                            Text("Stop")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.red)
                    } else if ttsManager.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(ttsManager.isPlaying ? "Stop pronunciation playback" : "Pronounce translation aloud (Text-to-Speech)")
            }

            if let id = record?.id {
                Button {
                    onOpenHistory?(id)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("View snapshot in Glance Main Window")
            }

            Spacer()

            if let endpoint = meta.endpointLabel {
                Text(endpoint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let latency = meta.latencyMs {
                Text("\(latency)ms")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Button {
                dismiss.run()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Actions

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedText == text { copiedText = nil }
        }
    }

    private func copyAllItems(_ items: [TranslationItem]) {
        let combined = items.map { item in
            if !item.source.isEmpty && !item.translation.isEmpty {
                return "\(item.source)\n\(item.translation)"
            } else if !item.translation.isEmpty {
                return item.translation
            } else {
                return item.source
            }
        }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedAll = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedAll = false
        }
    }

    private func speak(_ text: String) {
        let settings = SettingsStore()
        ttsManager.speak(text: text, language: settings.targetLanguage, engine: settings.ttsEngine, rate: settings.ttsRate)
    }

    private func speakAllItems(_ items: [TranslationItem]) {
        let combined = items.map(\.translation).joined(separator: ". ")
        speak(combined)
    }
}

/// Shared bridge so child views can signal hover without passing the controller down.
final class PanelHoverBridge {
    static let shared = PanelHoverBridge()
    weak var controller: ResultPanelController?
}

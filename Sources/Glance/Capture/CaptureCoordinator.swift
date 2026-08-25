import AppKit
import CoreGraphics

/// Owns the capture + translate state machine (design §5.1):
/// idle → permission preflight → selecting → capturing → saved → translating.
/// The coordinator returns to `idle` right after save so the next capture can
/// start while a translation is still in flight.
final class CaptureCoordinator {
    enum State: Equatable {
        case idle
        case selecting
        case capturing
    }

    private(set) var state: State = .idle

    private let overlay = SelectionOverlayController()
    /// Called after each completed save (used to flash the menu-bar icon).
    var onCaptureSaved: (() -> Void)?
    /// Called when the user cancels a selection (used to clear busy state).
    var onSelectionCancelled: (() -> Void)?
    /// Translation lifecycle (menu-bar busy tint).
    var onTranslateStart: (() -> Void)?
    var onTranslateEnd: (() -> Void)?

    private let historyStore: HistoryStore
    private let settings: SettingsStore
    weak var resultPanel: ResultPanelController?

    /// AppKit-global rect of the most recent capture — panel placement.
    private var lastCaptureRect: CGRect = .zero

    init(historyStore: HistoryStore, settings: SettingsStore) {
        self.historyStore = historyStore
        self.settings = settings

        overlay.onComplete = { [weak self] rect in
            self?.handleSelection(rect)
        }
        overlay.onCancel = { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.onSelectionCancelled?()
        }
    }

    // MARK: - Entry point

    func beginSelection() {
        guard state == .idle else { return }

        guard CGPreflightScreenCaptureAccess() else {
            presentPermissionAlert()
            return
        }

        state = .selecting
        let screen = screenContainingMouse()
        overlay.begin(on: screen)
    }

    // MARK: - Pipeline steps

    private func handleSelection(_ globalRect: CGRect) {
        guard state == .selecting else { return }
        state = .capturing

        // The overlay is already ordered out at this point (finished() → end()),
        // so a plain on-screen capture is correct and flicker-free.
        guard let captured = ScreenCaptureService.capture(globalRect: globalRect,
                                                          excludingWindowNumbers: []),
              let pngData = ScreenCaptureService.pngData(from: captured.image) else {
            NSLog("Glance: capture failed for rect \(globalRect)")
            state = .idle
            onSelectionCancelled?()
            return
        }

        var record = SnapshotRecord(
            imagePath: "",                       // filled in by the store on write
            pixelWidth: Int(captured.pixelSize.width),
            pixelHeight: Int(captured.pixelSize.height),
            status: .pending,
            targetLanguage: settings.targetLanguage.rawValue
        )
        do {
            try historyStore.insert(&record, imageData: pngData)
            NSLog("Glance: snapshot saved \(record.pixelWidth)×\(record.pixelHeight) → \(record.imagePath)")
        } catch {
            NSLog("Glance: failed to persist snapshot: \(error)")
            state = .idle
            onSelectionCancelled?()
            return
        }

        let savedRecord = record
        lastCaptureRect = globalRect
        state = .idle
        onCaptureSaved?()

        // Immediately present floating HUD in processing state near the selection area
        let targetDisplayName = settings.targetLanguage.displayName
        resultPanel?.show(
            content: .processing(targetLanguage: targetDisplayName),
            meta: ResultPanelContent.Meta(
                endpointLabel: settings.activeEndpoint()?.label,
                model: settings.activeEndpoint()?.model,
                latencyMs: nil
            ),
            record: savedRecord,
            near: globalRect,
            timeout: 60,
            style: settings.hudAppearanceStyle,
            hudOpacity: settings.hudOpacity,
            sourceFontSize: settings.sourceFontSize,
            sourceTextColor: settings.sourceTextColor,
            translatedFontSize: settings.translatedFontSize,
            translatedTextColor: settings.translatedTextColor
        )

        let image = captured.image
        Task { @MainActor in
            await self.translate(record: savedRecord, image: image)
        }
    }

    // MARK: - Translation

    @MainActor
    private func translate(record: SnapshotRecord, image: CGImage) async {
        guard let endpoint = settings.activeEndpoint() else {
            finish(record: record, status: .failed, items: [],
                   endpointID: nil, endpointLabel: nil, model: nil, latencyMs: nil,
                   error: "No translation endpoint configured — add one in Settings.")
            showFailurePanel("No translation endpoint configured.\nOpen Glance Settings to add an endpoint.")
            return
        }
        let apiKey = settings.key(for: endpoint.id) ?? ""

        onTranslateStart?()
        defer { onTranslateEnd?() }

        let downscaled = ImageDownscaler.downscaleIfOversized(image)
        guard let uploadPNG = ScreenCaptureService.pngData(from: downscaled) else {
            finish(record: record, status: .failed, items: [],
                   endpointID: endpoint.id, endpointLabel: endpoint.label, model: endpoint.model,
                   latencyMs: nil, error: "Could not encode image for upload.")
            showFailurePanel("Could not encode the screenshot for upload.")
            return
        }

        let outcome = await LLMClient.translate(pngData: uploadPNG,
                                                targetLanguage: settings.targetLanguage,
                                                tone: settings.translationTone,
                                                baseURL: endpoint.baseURL,
                                                apiKey: apiKey,
                                                model: endpoint.model)

        switch outcome {
        case .ok(let items, let latencyMs):
            finish(record: record, status: .ok, items: items,
                   endpointID: endpoint.id, endpointLabel: endpoint.label, model: endpoint.model,
                   latencyMs: latencyMs, error: nil)
            
            var completedRecord = record
            completedRecord.status = .ok
            completedRecord.itemsJSON = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            completedRecord.translatedText = items.map(\.translation).joined(separator: "\n\n")
            completedRecord.endpointLabel = endpoint.label
            completedRecord.latencyMs = latencyMs
            
            if settings.autoCopyToClipboard && !completedRecord.translatedText.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(completedRecord.translatedText, forType: .string)
            }
            
            if settings.enableNotifications {
                NotificationService.shared.postSuccess(record: completedRecord, playSound: settings.playNotificationSound)
            }
            
            showItemsPanel(items, meta: meta(endpoint, latencyMs), record: completedRecord)

        case .empty(let latencyMs):
            finish(record: record, status: .empty, items: [],
                   endpointID: endpoint.id, endpointLabel: endpoint.label, model: endpoint.model,
                   latencyMs: latencyMs, error: nil)
            
            var completedRecord = record
            completedRecord.status = .empty
            completedRecord.endpointLabel = endpoint.label
            completedRecord.latencyMs = latencyMs
            
            if settings.enableNotifications {
                NotificationService.shared.postSuccess(record: completedRecord, playSound: settings.playNotificationSound)
            }
            
            resultPanel?.show(content: .empty,
                              meta: meta(endpoint, latencyMs),
                              near: lastCaptureRect,
                              timeout: settings.resultPanelTimeout,
                              style: settings.hudAppearanceStyle,
                              hudOpacity: settings.hudOpacity,
                              sourceFontSize: settings.sourceFontSize,
                              sourceTextColor: settings.sourceTextColor,
                              translatedFontSize: settings.translatedFontSize,
                              translatedTextColor: settings.translatedTextColor,
                              onRetry: { [weak self] in
                                  Task { @MainActor in
                                      await self?.translate(record: record, image: image)
                                  }
                              })

        case .failure(let message, let latencyMs):
            finish(record: record, status: .failed, items: [],
                   endpointID: endpoint.id, endpointLabel: endpoint.label, model: endpoint.model,
                   latencyMs: latencyMs, error: message)
            
            if settings.enableNotifications {
                NotificationService.shared.postFailure(message: message, snapshotID: record.id, playSound: settings.playNotificationSound)
            }
            
            showFailurePanel(message, record: record, image: image)
        }
    }

    private func finish(record: SnapshotRecord,
                        status: SnapshotRecord.Status,
                        items: [TranslationItem],
                        endpointID: UUID?,
                        endpointLabel: String?,
                        model: String?,
                        latencyMs: Int?,
                        error: String?) {
        do {
            try historyStore.applyTranslation(id: record.id,
                                              status: status,
                                              items: items,
                                              endpointID: endpointID,
                                              endpointLabel: endpointLabel,
                                              model: model,
                                              latencyMs: latencyMs,
                                              errorMessage: error)
            NSLog("Glance: translation \(status.rawValue) for \(record.id)")
        } catch {
            NSLog("Glance: failed to persist translation for \(record.id): \(error)")
        }
    }

    private func meta(_ endpoint: EndpointConfig, _ latencyMs: Int?) -> ResultPanelContent.Meta {
        ResultPanelContent.Meta(endpointLabel: endpoint.label,
                                model: endpoint.model,
                                latencyMs: latencyMs)
    }

    private func showItemsPanel(_ items: [TranslationItem], meta: ResultPanelContent.Meta, record: SnapshotRecord) {
        resultPanel?.show(content: .items(items),
                          meta: meta,
                          record: record,
                          near: lastCaptureRect,
                          timeout: settings.resultPanelTimeout,
                          style: settings.hudAppearanceStyle,
                          hudOpacity: settings.hudOpacity,
                          sourceFontSize: settings.sourceFontSize,
                          sourceTextColor: settings.sourceTextColor,
                          translatedFontSize: settings.translatedFontSize,
                          translatedTextColor: settings.translatedTextColor)
    }

    private func showFailurePanel(_ message: String, record: SnapshotRecord? = nil, image: CGImage? = nil) {
        resultPanel?.show(content: .failure(message),
                          meta: ResultPanelContent.Meta(endpointLabel: nil, model: nil, latencyMs: nil),
                          record: record,
                          near: lastCaptureRect,
                          timeout: max(8, settings.resultPanelTimeout),
                          style: settings.hudAppearanceStyle,
                          hudOpacity: settings.hudOpacity,
                          sourceFontSize: settings.sourceFontSize,
                          sourceTextColor: settings.sourceTextColor,
                          translatedFontSize: settings.translatedFontSize,
                          translatedTextColor: settings.translatedTextColor,
                          onRetry: { [weak self] in
                              guard let self, let record, let image else { return }
                              Task { @MainActor in
                                  await self.translate(record: record, image: image)
                              }
                          })
    }

    private func screenContainingMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Permission preflight

    private func presentPermissionAlert() {
        // Registering the app in the TCC list requires an actual REQUEST —
        // preflight alone never makes Glance appear in System Settings (M2.1 fix).
        _ = CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = """
        Glance needs Screen Recording access to capture regions of your screen. \
        Your screenshots are sent only to the translation endpoint you configure.

        Grant it in System Settings → Privacy & Security → Screen Recording, \
        then restart Glance.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

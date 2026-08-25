import AppKit

/// Borderless non-activating panel that CAN become key (required for Esc and mouse handling)
/// without activating the host application or raising any background windows.
final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows crosshair selection overlays on the target screen and reports the
/// chosen rect in AppKit-global coordinates.
final class SelectionOverlayController {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var panels: [SelectionOverlayPanel] = []
    private(set) var isActive = false

    func begin(on screen: NSScreen) {
        guard !isActive else { return }
        isActive = true

        let panel = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrame(screen.frame, display: true)

        let view = SelectionOverlayView(frame: screen.frame, controller: self)
        panel.contentView = view

        panels = [panel]
        NSCursor.crosshair.push()
        panel.orderFrontRegardless()
        panel.makeKey()
        view.resetDrag()
    }

    /// Hides overlays without flicker (capture uses below-window exclusion,
    /// so this is called after pixels are already taken).
    func end() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        NSCursor.pop()
        isActive = false
    }

    fileprivate func finished(with rect: CGRect?) {
        end()
        if let rect {
            onComplete?(rect)
        } else {
            onCancel?()
        }
    }
}

// MARK: - Overlay view

final class SelectionOverlayView: NSView {
    private weak var controller: SelectionOverlayController?
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?

    static let minimumSelectionSize: CGFloat = 20

    init(frame: CGRect, controller: SelectionOverlayController) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Crucial for capture overlays: receives the very first mouseDown event
        // immediately upon invocation, even when Glance is not the active frontmost app.
        true
    }

    func resetDrag() {
        dragStart = nil
        dragCurrent = nil
        window?.makeFirstResponder(self)
    }

    // MARK: Selection rect (flipped local coords for natural top-left drag)

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(x: min(start.x, current.x),
                      y: min(start.y, current.y),
                      width: abs(start.x - current.x),
                      height: abs(start.y - current.y))
    }

    // MARK: Drawing

    // NOTE: This view is a standard NON-flipped NSView — event coordinates and
    // drawing coordinates share the same bottom-left origin. Draw `selectionRect`
    // directly; flipping it here double-flips and mirrors the rect (M2.2 bug).
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything...
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.fill(bounds)

        if let rect = selectionRect, rect.width > 1, rect.height > 1 {
            // ...then punch a clear hole so the live desktop shows through.
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(rect)
            context.restoreGState()

            // Accent stroke around the selection.
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2)
            context.stroke(rect.insetBy(dx: -1, dy: -1))

            // Size badge above-right of the rect (below when near the top edge).
            let label = "\(Int(rect.width)) × \(Int(rect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            var origin = CGPoint(x: rect.maxX - size.width - 8,
                                 y: rect.maxY + 6)
            if origin.y + size.height > bounds.maxY { // near top edge → draw inside/below
                origin.y = rect.minY - size.height - 6
                if origin.y < bounds.minY { origin.y = rect.maxY + 4 }
            }
            origin.x = max(4, min(origin.x, bounds.maxX - size.width - 4))
            (label as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    // MARK: Mouse & keyboard

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
        }
        guard let rect = selectionRect,
              rect.width >= Self.minimumSelectionSize,
              rect.height >= Self.minimumSelectionSize else {
            controller?.finished(with: nil)
            return
        }

        // Local (bottom-left origin) → AppKit global.
        let globalRect = convert(rect, to: nil)
        let clamped = globalRect.intersection(window?.convertToScreen(bounds) ?? globalRect)
        controller?.finished(with: clamped.isNull ? nil : clamped)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(HotkeyCombo.escapeKeyCode) {
            controller?.finished(with: nil)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.finished(with: nil)
    }
}

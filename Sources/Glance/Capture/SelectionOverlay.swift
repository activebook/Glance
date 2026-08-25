import AppKit
import CoreGraphics

/// Borderless non-activating panel that CAN become key (required for Esc and mouse handling)
/// without activating the host application or raising any background windows.
final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows crosshair and smart window snapping selection overlays across screens
/// and reports the chosen rect in AppKit-global coordinates.
final class SelectionOverlayController {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var panels: [SelectionOverlayPanel] = []
    private(set) var isActive = false
    private(set) var detectedWindows: [DetectedWindow] = []

    func begin(on primaryScreen: NSScreen) {
        guard !isActive else { return }
        isActive = true

        let allScreens = NSScreen.screens
        panels = []

        // 1. Create overlay panels across all connected screens for seamless multi-monitor capture
        for screen in allScreens {
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

            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: self, screenFrame: screen.frame)
            panel.contentView = view
            panels.append(panel)
        }

        // 2. Query visible on-screen windows (excluding our new overlay panels)
        let overlayIDs = Set(panels.map { CGWindowID($0.windowNumber) })
        detectedWindows = WindowDetector.shared.detectWindows(excludingWindowNumbers: overlayIDs)

        // Pass window list to all views
        for panel in panels {
            if let view = panel.contentView as? SelectionOverlayView {
                view.updateWindows(detectedWindows)
                view.resetState()
            }
        }

        NSCursor.crosshair.push()

        // 3. Display panels and make the panel containing the cursor key
        for panel in panels {
            panel.orderFrontRegardless()
        }

        let mouseLoc = NSEvent.mouseLocation
        let keyPanel = panels.first { NSPointInRect(mouseLoc, $0.frame) } ?? panels.first
        keyPanel?.makeKey()
    }

    /// Hides overlays without flicker.
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
    private let screenFrame: CGRect

    private var windows: [DetectedWindow] = []
    private var hoveredWindow: DetectedWindow?
    private var hasUserMovedMouse = false
    private var initialMouseLocation: NSPoint?

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var isDragging = false

    private var trackingArea: NSTrackingArea?

    static let minimumSelectionSize: CGFloat = 16
    static let dragThreshold: CGFloat = 4.0

    init(frame: CGRect, controller: SelectionOverlayController, screenFrame: CGRect) {
        self.controller = controller
        self.screenFrame = screenFrame
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func updateWindows(_ windows: [DetectedWindow]) {
        self.windows = windows
    }

    func resetState() {
        dragStart = nil
        dragCurrent = nil
        isDragging = false
        hoveredWindow = nil
        hasUserMovedMouse = false
        initialMouseLocation = NSEvent.mouseLocation
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    // MARK: - Hit Testing & Hover Snapping

    private func checkHover(at globalPoint: NSPoint) {
        guard !isDragging else { return }
        let newHovered = WindowDetector.shared.findWindow(at: globalPoint, in: windows)
        if newHovered != hoveredWindow {
            hoveredWindow = newHovered
            needsDisplay = true
        }
    }

    // MARK: - Coordinate Conversions

    /// Converts an AppKit-global rect to local view coordinates.
    private func localRect(forGlobalRect globalRect: CGRect) -> CGRect {
        CGRect(
            x: globalRect.origin.x - screenFrame.origin.x,
            y: globalRect.origin.y - screenFrame.origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// Converts a local view rect to AppKit-global coordinates.
    private func globalRect(forLocalRect localRect: CGRect) -> CGRect {
        CGRect(
            x: localRect.origin.x + screenFrame.origin.x,
            y: localRect.origin.y + screenFrame.origin.y,
            width: localRect.width,
            height: localRect.height
        )
    }

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Semi-transparent backdrop darkening the screen
        context.setFillColor(NSColor.black.withAlphaComponent(0.40).cgColor)
        context.fill(bounds)

        if isDragging, let rect = selectionRect, rect.width > 1, rect.height > 1 {
            // MARK: - Freeform Drag Marquee
            drawHoleAndBorder(rect: rect, in: context)
            drawSizeBadge(for: rect, text: "\(Int(rect.width)) × \(Int(rect.height))")
        } else if hasUserMovedMouse, let win = hoveredWindow {
            // MARK: - Smart Window Snapping
            let localWinRect = localRect(forGlobalRect: win.bounds).intersection(bounds)
            if !localWinRect.isEmpty {
                drawHoleAndBorder(rect: localWinRect, in: context, cornerRadius: 8)
                let labelText = "\(win.displayTag)  •  \(Int(win.bounds.width)) × \(Int(win.bounds.height))"
                drawWindowBadge(for: localWinRect, text: labelText)
            }
        }
    }

    private func drawHoleAndBorder(rect: CGRect, in context: CGContext, cornerRadius: CGFloat = 0) {
        context.saveGState()
        context.setBlendMode(.clear)
        if cornerRadius > 0 {
            let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(path)
            context.fillPath()
        } else {
            context.fill(rect)
        }
        context.restoreGState()

        // Vibrant accent stroke
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(2.5)
        if cornerRadius > 0 {
            let path = CGPath(roundedRect: rect.insetBy(dx: -1, dy: -1),
                              cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(path)
            context.strokePath()
        } else {
            context.stroke(rect.insetBy(dx: -1, dy: -1))
        }
        context.restoreGState()
    }

    private func drawSizeBadge(for rect: CGRect, text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pillPaddingH: CGFloat = 8
        let pillPaddingV: CGFloat = 4
        let pillSize = CGSize(width: textSize.width + (pillPaddingH * 2), height: textSize.height + (pillPaddingV * 2))

        var origin = CGPoint(x: rect.maxX - pillSize.width - 6, y: rect.maxY + 6)
        if origin.y + pillSize.height > bounds.maxY {
            origin.y = rect.minY - pillSize.height - 6
            if origin.y < bounds.minY { origin.y = rect.maxY + 4 }
        }
        origin.x = max(6, min(origin.x, bounds.maxX - pillSize.width - 6))

        let pillRect = CGRect(origin: origin, size: pillSize)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.85).setFill()
        pillPath.fill()

        let textOrigin = CGPoint(x: origin.x + pillPaddingH, y: origin.y + pillPaddingV)
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
    }

    private func drawWindowBadge(for rect: CGRect, text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pillPaddingH: CGFloat = 10
        let pillPaddingV: CGFloat = 5
        let pillSize = CGSize(width: textSize.width + (pillPaddingH * 2), height: textSize.height + (pillPaddingV * 2))

        // Position pill comfortably at top-left of the snapped window
        var origin = CGPoint(x: rect.minX + 8, y: rect.maxY - pillSize.height - 8)
        if origin.y < rect.minY {
            origin.y = rect.minY + 8
        }
        origin.x = max(6, min(origin.x, bounds.maxX - pillSize.width - 6))
        origin.y = max(6, min(origin.y, bounds.maxY - pillSize.height - 6))

        let pillRect = CGRect(origin: origin, size: pillSize)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.85).setFill()
        pillPath.fill()

        // Subtle border on badge
        NSColor.white.withAlphaComponent(0.18).setStroke()
        pillPath.lineWidth = 1
        pillPath.stroke()

        let textOrigin = CGPoint(x: origin.x + pillPaddingH, y: origin.y + pillPaddingV)
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
    }

    // MARK: - Mouse & Keyboard Events

    override func mouseMoved(with event: NSEvent) {
        let currentMouse = NSEvent.mouseLocation
        if !hasUserMovedMouse {
            if let initial = initialMouseLocation {
                let dist = hypot(currentMouse.x - initial.x, currentMouse.y - initial.y)
                if dist >= 3.0 {
                    hasUserMovedMouse = true
                }
            } else {
                hasUserMovedMouse = true
            }
        }
        if hasUserMovedMouse {
            checkHover(at: currentMouse)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        dragStart = loc
        dragCurrent = loc
        isDragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        hasUserMovedMouse = true
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        dragCurrent = current

        let distance = hypot(current.x - start.x, current.y - start.y)
        if distance > Self.dragThreshold {
            isDragging = true
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            isDragging = false
            hoveredWindow = nil
        }

        if isDragging {
            // MARK: Complete Manual Drag Selection
            guard let localRect = selectionRect,
                  localRect.width >= Self.minimumSelectionSize,
                  localRect.height >= Self.minimumSelectionSize else {
                controller?.finished(with: nil)
                return
            }
            let targetGlobalRect = globalRect(forLocalRect: localRect)
            controller?.finished(with: targetGlobalRect)
        } else if hasUserMovedMouse, let win = hoveredWindow {
            // MARK: Complete Smart Window Snapping (Single Click)
            controller?.finished(with: win.bounds)
        } else {
            // Clicked bare desktop or unmapped area → cancel
            controller?.finished(with: nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.finished(with: nil)
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

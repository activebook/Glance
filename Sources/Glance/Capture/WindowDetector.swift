import AppKit
import CoreGraphics

/// Represents a detected on-screen window with AppKit-global coordinates and metadata.
struct DetectedWindow: Identifiable, Equatable {
    let id: CGWindowID
    let ownerName: String
    let windowName: String?
    let bounds: CGRect        // In AppKit-global coordinate space (origin bottom-left)
    let layer: Int
    let alpha: Double
    let ownerPID: pid_t

    /// Formatted display title for the window badge tag (e.g. "Safari" or "Xcode — Glance").
    var displayTag: String {
        if let name = windowName, !name.isEmpty, name != ownerName {
            return "\(ownerName) — \(name)"
        }
        return ownerName
    }
}

/// Service responsible for scanning visible on-screen windows in Z-order (front to back)
/// and hit-testing points under the cursor for smart window snapping.
final class WindowDetector {
    static let shared = WindowDetector()

    /// Scans the window server for currently visible application windows.
    ///
    /// - Parameter excludingWindowNumbers: Window IDs to explicitly ignore (e.g., overlay panels).
    /// - Returns: An array of `DetectedWindow` sorted in front-to-back Z-order.
    func detectWindows(excludingWindowNumbers: Set<CGWindowID> = []) -> [DetectedWindow] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = CaptureGeometry.primaryScreenHeight
        var detected: [DetectedWindow] = []

        for info in windowInfoList {
            guard let windowIDNum = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let windowID = CGWindowID(windowIDNum.uint32Value)

            // Skip Glance's own windows and overlay panels
            if excludingWindowNumbers.contains(windowID) { continue }
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == myPID { continue }

            // Filter by window layer: normal application windows are layer 0
            guard let layerNum = info[kCGWindowLayer as String] as? NSNumber else { continue }
            let layer = layerNum.intValue
            // Only consider standard document/app window layers (0 to 3)
            guard layer >= 0 && layer <= 3 else { continue }

            // Filter out alpha/transparency
            if let alphaNum = info[kCGWindowAlpha as String] as? NSNumber, alphaNum.doubleValue < 0.05 {
                continue
            }

            // Extract bounds dictionary in CoreGraphics coordinates
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            // Filter out tiny artifacts, zero-sized windows, or off-screen bounds
            guard cgBounds.width >= 30, cgBounds.height >= 30 else { continue }

            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? "Window"
            let windowName = info[kCGWindowName as String] as? String

            // Filter out common system UI owners that are not user content
            if isSystemExcludedOwner(ownerName) { continue }

            // Convert CG coordinates (top-left) to AppKit global coordinates (bottom-left)
            let appKitBounds = CaptureGeometry.appKitRect(fromCGRect: cgBounds, primaryScreenHeight: primaryHeight)

            let window = DetectedWindow(
                id: windowID,
                ownerName: ownerName,
                windowName: windowName,
                bounds: appKitBounds,
                layer: layer,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0,
                ownerPID: (info[kCGWindowOwnerPID as String] as? pid_t) ?? 0
            )

            detected.append(window)
        }

        return detected
    }

    /// Finds the topmost visible window under the given AppKit-global coordinate.
    ///
    /// - Parameters:
    ///   - point: The point in AppKit-global coordinates (origin bottom-left of primary screen).
    ///   - windows: The candidate windows in front-to-back Z-order.
    /// - Returns: The topmost `DetectedWindow` containing the point, or nil.
    func findWindow(at point: NSPoint, in windows: [DetectedWindow]) -> DetectedWindow? {
        windows.first { $0.bounds.contains(point) }
    }

    // MARK: - Private Filters

    private func isSystemExcludedOwner(_ name: String) -> Bool {
        let excluded: Set<String> = [
            "Window Server",
            "Dock",
            "Control Center",
            "Notification Center",
            "SystemUIServer",
            "Spotlight",
            "Wallpaper",
            "WindowManager"
        ]
        return excluded.contains(name)
    }
}

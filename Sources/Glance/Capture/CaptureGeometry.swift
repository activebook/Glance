import Foundation
import AppKit

/// Pure coordinate conversions between AppKit global space (origin bottom-left)
/// and CoreGraphics screen space (origin top-left of the primary display).
enum CaptureGeometry {
    /// Converts an AppKit-global rect to a CG rect for capture APIs.
    static func cgRect(fromAppKitRect rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryScreenHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Primary display height in points (the flip reference).
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
}

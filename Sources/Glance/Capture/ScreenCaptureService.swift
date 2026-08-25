import AppKit
import CoreGraphics

/// Pixel capture of an AppKit-global rect, excluding Glance's own overlay
/// windows via the below-window trick (no hide-then-capture flicker).
///
/// TODO: CGWindowListCreateImage is soft-deprecated on recent macOS; migrate to
/// ScreenCaptureKit's SCScreenshotManager when we bump the minimum OS.
enum ScreenCaptureService {
    static func capture(globalRect: CGRect,
                        excludingWindowNumbers: [CGWindowID]) -> (image: CGImage, pixelSize: CGSize)? {
        let cgRect = CaptureGeometry.cgRect(
            fromAppKitRect: globalRect,
            primaryScreenHeight: CaptureGeometry.primaryScreenHeight
        )

        let image: CGImage?
        if let baseWindow = excludingWindowNumbers.first {
            // Below-window exclusion: capture everything under our overlay.
            image = CGWindowListCreateImage(cgRect,
                                            [.optionOnScreenBelowWindow],
                                            baseWindow,
                                            [.bestResolution])
        } else {
            // No exclusions: plain on-screen capture.
            image = CGWindowListCreateImage(cgRect,
                                            [.optionOnScreenOnly],
                                            kCGNullWindowID,
                                            [.bestResolution])
        }
        guard let image else {
            return nil
        }
        return (image, CGSize(width: image.width, height: image.height))
    }

    /// PNG-encoded data for a captured image.
    static func pngData(from image: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: image.width, height: image.height)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Decodes a PNG file back to a CGImage (used by re-translate).
    static func cgImage(fromPNGData data: Data) -> CGImage? {
        NSBitmapImageRep(data: data)?.cgImage
    }
}

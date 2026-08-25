import CoreGraphics
import Foundation

/// Downscales screenshots before upload when the longest side exceeds a budget
/// (token economy). Disk keeps the full-resolution original; only the uploaded
/// copy is shrunk.
enum ImageDownscaler {
    static let defaultMaxDimension = 2000

    static func downscaleIfOversized(_ image: CGImage,
                                     maxDimension: Int = ImageDownscaler.defaultMaxDimension) -> CGImage {
        let longSide = max(image.width, image.height)
        guard longSide > maxDimension else { return image }

        let scale = CGFloat(maxDimension) / CGFloat(longSide)
        let newWidth = max(1, Int(CGFloat(image.width) * scale))
        let newHeight = max(1, Int(CGFloat(image.height) * scale))

        guard let context = CGContext(data: nil,
                                      width: newWidth,
                                      height: newHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image // keep original on failure — better to overspend tokens than lose data
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}

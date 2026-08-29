import AppKit
import CoreGraphics

func renderIcon(size: CGFloat) -> NSImage {
    let targetSize = NSSize(width: size, height: size)
    let image = NSImage(size: targetSize)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    if let masterImage = NSImage(contentsOfFile: "images/AppIcon.png"),
       let cgImage = masterImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let margin = size * 0.092
    let iconRect = rect.insetBy(dx: margin, dy: margin)
    let cornerRadius = iconRect.width * 0.2237

    // 1. Drop Shadow under Squircle (macOS Big Sur+ elevation)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.035),
        blur: size * 0.070,
        color: NSColor.black.withAlphaComponent(0.48).cgColor
    )

    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Background Gradient: Deep rich indigo to electric violet (#312E81 -> #6366F1)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    // Exact hex specifications:
    // #6366F1: (99, 102, 241)
    // #4F46E5: (79, 70, 229)
    // #312E81: (49, 46, 129)
    let cTop = CGColor(srgbRed: 99.0 / 255.0, green: 102.0 / 255.0, blue: 241.0 / 255.0, alpha: 1.0)
    let cMid = CGColor(srgbRed: 79.0 / 255.0, green: 70.0 / 255.0, blue: 229.0 / 255.0, alpha: 1.0)
    let cBottom = CGColor(srgbRed: 49.0 / 255.0, green: 46.0 / 255.0, blue: 129.0 / 255.0, alpha: 1.0)

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [cTop, cMid, cBottom] as CFArray,
        locations: [0.0, 0.40, 1.0]
    )!

    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.minY),
        options: []
    )

    // Ambient top soft highlight glow
    let ambientColors = [
        NSColor(srgbRed: 165.0 / 255.0, green: 180.0 / 255.0, blue: 252.0 / 255.0, alpha: 0.22).cgColor,
        NSColor(srgbRed: 165.0 / 255.0, green: 180.0 / 255.0, blue: 252.0 / 255.0, alpha: 0.0).cgColor
    ] as CFArray
    if let ambientGrad = CGGradient(colorsSpace: colorSpace, colors: ambientColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            ambientGrad,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.midY),
            options: []
        )
    }

    // High precision inner rim lighting
    let strokePath = CGPath(
        roundedRect: iconRect.insetBy(dx: size * 0.005, dy: size * 0.005),
        cornerWidth: cornerRadius - size * 0.005,
        cornerHeight: cornerRadius - size * 0.005,
        transform: nil
    )
    ctx.addPath(strokePath)
    ctx.setLineWidth(size * 0.010)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
    ctx.strokePath()

    ctx.restoreGState()

    // 3. Central Viewfinder Frame (Shifted outward for generous breathing room)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let vfSize = iconRect.width * 0.75
    let vfRect = CGRect(x: center.x - vfSize / 2, y: center.y - vfSize / 2, width: vfSize, height: vfSize)

    let bracketRadius = vfSize * 0.165
    let bracketStroke = vfSize * 0.080
    let bracketLen = vfSize * 0.26

    // Foreground drop shadow for tactile depth
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.025,
        color: NSColor.black.withAlphaComponent(0.32).cgColor
    )

    // 3A. Viewfinder Brackets
    ctx.saveGState()
    ctx.setLineWidth(bracketStroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(NSColor.white.cgColor)

    // Top-Left Bracket
    let tlPath = CGMutablePath()
    tlPath.move(to: CGPoint(x: vfRect.minX, y: vfRect.maxY - bracketLen))
    tlPath.addLine(to: CGPoint(x: vfRect.minX, y: vfRect.maxY - bracketRadius))
    tlPath.addQuadCurve(to: CGPoint(x: vfRect.minX + bracketRadius, y: vfRect.maxY), control: CGPoint(x: vfRect.minX, y: vfRect.maxY))
    tlPath.addLine(to: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.maxY))
    ctx.addPath(tlPath)
    ctx.strokePath()

    // Top-Right Bracket
    let trPath = CGMutablePath()
    trPath.move(to: CGPoint(x: vfRect.maxX - bracketLen, y: vfRect.maxY))
    trPath.addLine(to: CGPoint(x: vfRect.maxX - bracketRadius, y: vfRect.maxY))
    trPath.addQuadCurve(to: CGPoint(x: vfRect.maxX, y: vfRect.maxY - bracketRadius), control: CGPoint(x: vfRect.maxX, y: vfRect.maxY))
    trPath.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.maxY - bracketLen))
    ctx.addPath(trPath)
    ctx.strokePath()

    // Bottom-Left Bracket
    let blPath = CGMutablePath()
    blPath.move(to: CGPoint(x: vfRect.minX, y: vfRect.minY + bracketLen))
    blPath.addLine(to: CGPoint(x: vfRect.minX, y: vfRect.minY + bracketRadius))
    blPath.addQuadCurve(to: CGPoint(x: vfRect.minX + bracketRadius, y: vfRect.minY), control: CGPoint(x: vfRect.minX, y: vfRect.minY))
    blPath.addLine(to: CGPoint(x: vfRect.minX + bracketLen, y: vfRect.minY))
    ctx.addPath(blPath)
    ctx.strokePath()

    // Bottom-Right Bracket
    let brPath = CGMutablePath()
    brPath.move(to: CGPoint(x: vfRect.maxX - bracketLen, y: vfRect.minY))
    brPath.addLine(to: CGPoint(x: vfRect.maxX - bracketRadius, y: vfRect.minY))
    brPath.addQuadCurve(to: CGPoint(x: vfRect.maxX, y: vfRect.minY + bracketRadius), control: CGPoint(x: vfRect.maxX, y: vfRect.minY))
    brPath.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.minY + bracketLen))
    ctx.addPath(brPath)
    ctx.strokePath()
    ctx.restoreGState()

    // 3B. Center Character "文"
    let font = NSFont(name: "PingFangSC-Semibold", size: iconRect.width * 0.45)
        ?? NSFont.systemFont(ofSize: iconRect.width * 0.45, weight: .semibold)
    let text = "文" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = text.size(withAttributes: attrs)
    let textRect = CGRect(
        x: center.x - textSize.width / 2,
        y: center.y - textSize.height / 2 + iconRect.width * 0.022,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attrs)

    ctx.restoreGState() // Restores shadow gstate

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let img = renderIcon(size: size)
    savePNG(img, to: iconsetDir.appendingPathComponent(name))
}

print("Iconset generated in AppIcon.iconset")

import SwiftUI
import AppKit

/// Vector-rendered brand iconography for AI service providers.
struct ProviderBrandIcon: View {
    let providerID: String
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            switch providerID {
            case "openai":
                OpenAILogo(size: size)
            case "google":
                GeminiLogo(size: size)
            case "deepseek":
                DeepSeekWhaleLogo(size: size)
            case "openrouter":
                OpenRouterLogo(size: size)
            case "ollama":
                OllamaLlamaLogo(size: size)
            default:
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: size * 0.75, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    /// Generates a high-DPI rasterized NSImage for use in macOS NSMenus and SwiftUI Menus.
    @MainActor
    static func nsImage(for providerID: String, size: CGFloat = 16) -> NSImage {
        let view = ProviderBrandIcon(providerID: providerID, size: size)
            .frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        if let img = renderer.nsImage {
            img.size = NSSize(width: size, height: size)
            return img
        }
        return NSImage(systemSymbolName: "cpu", accessibilityDescription: nil) ?? NSImage()
    }

    @MainActor
    static func image(for providerID: String, size: CGFloat = 16) -> Image {
        Image(nsImage: nsImage(for: providerID, size: size))
    }
}

// MARK: - OpenAI Logo (6-petal rounded spiral knot)

private struct OpenAILogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) * 0.42
            let lineWidth = size * 0.11

            for i in 0..<6 {
                let angle = Double(i) * (.pi / 3.0)
                var path = Path()
                let p1 = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius * 0.35,
                    y: center.y + CGFloat(sin(angle)) * radius * 0.35
                )
                let p2 = CGPoint(
                    x: center.x + CGFloat(cos(angle + .pi / 6.0)) * radius,
                    y: center.y + CGFloat(sin(angle + .pi / 6.0)) * radius
                )
                let p3 = CGPoint(
                    x: center.x + CGFloat(cos(angle + .pi / 2.5)) * radius * 0.85,
                    y: center.y + CGFloat(sin(angle + .pi / 2.5)) * radius * 0.85
                )
                path.move(to: p1)
                path.addQuadCurve(to: p3, control: p2)
                context.stroke(
                    path,
                    with: .color(Color(red: 0.06, green: 0.65, blue: 0.50)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Google Gemini 4-Point Sparkle Star

private struct GeminiLogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2

            var path = Path()
            path.move(to: CGPoint(x: cx, y: 0))
            path.addQuadCurve(to: CGPoint(x: w, y: cy), control: CGPoint(x: cx * 1.28, y: cy * 0.72))
            path.addQuadCurve(to: CGPoint(x: cx, y: h), control: CGPoint(x: cx * 1.28, y: cy * 1.28))
            path.addQuadCurve(to: CGPoint(x: 0, y: cy), control: CGPoint(x: cx * 0.72, y: cy * 1.28))
            path.addQuadCurve(to: CGPoint(x: cx, y: 0), control: CGPoint(x: cx * 0.72, y: cy * 0.72))

            let gradient = Gradient(colors: [
                Color(red: 0.11, green: 0.53, blue: 0.98),
                Color(red: 0.56, green: 0.27, blue: 0.96),
                Color(red: 0.93, green: 0.31, blue: 0.50)
            ])
            context.fill(
                path,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: w, y: h))
            )
        }
    }
}

// MARK: - DeepSeek Whale Logo

private struct DeepSeekWhaleLogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Whale body
            var bodyPath = Path()
            bodyPath.move(to: CGPoint(x: w * 0.12, y: h * 0.58))
            // Head curve
            bodyPath.addCurve(
                to: CGPoint(x: w * 0.65, y: h * 0.35),
                control1: CGPoint(x: w * 0.10, y: h * 0.25),
                control2: CGPoint(x: w * 0.40, y: h * 0.22)
            )
            // Back & tail
            bodyPath.addCurve(
                to: CGPoint(x: w * 0.92, y: h * 0.28),
                control1: CGPoint(x: w * 0.78, y: h * 0.40),
                control2: CGPoint(x: w * 0.85, y: h * 0.35)
            )
            // Tail fluke top
            bodyPath.addLine(to: CGPoint(x: w * 0.98, y: h * 0.18))
            bodyPath.addLine(to: CGPoint(x: w * 0.92, y: h * 0.38))
            // Tail fluke bottom
            bodyPath.addLine(to: CGPoint(x: w * 0.98, y: h * 0.48))
            bodyPath.addLine(to: CGPoint(x: w * 0.82, y: h * 0.42))
            // Belly curve
            bodyPath.addCurve(
                to: CGPoint(x: w * 0.12, y: h * 0.58),
                control1: CGPoint(x: w * 0.65, y: h * 0.78),
                control2: CGPoint(x: w * 0.25, y: h * 0.78)
            )

            // Whale fin
            var finPath = Path()
            finPath.move(to: CGPoint(x: w * 0.38, y: h * 0.56))
            finPath.addQuadCurve(to: CGPoint(x: w * 0.48, y: h * 0.75), control: CGPoint(x: w * 0.42, y: h * 0.68))
            finPath.addQuadCurve(to: CGPoint(x: w * 0.46, y: h * 0.56), control: CGPoint(x: w * 0.46, y: h * 0.66))

            let blueColor = Color(red: 0.08, green: 0.47, blue: 0.98)
            context.fill(bodyPath, with: .color(blueColor))
            context.fill(finPath, with: .color(blueColor.opacity(0.85)))

            // Little eye
            let eyeRect = CGRect(x: w * 0.22, y: h * 0.42, width: w * 0.07, height: h * 0.07)
            context.fill(Path(ellipseIn: eyeRect), with: .color(.white))
        }
    }
}

// MARK: - Ollama Llama Logo

private struct OllamaLlamaLogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            var path = Path()
            // Neck & body
            path.move(to: CGPoint(x: w * 0.35, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.48))
            // Left ear
            path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.15))
            path.addQuadCurve(to: CGPoint(x: w * 0.44, y: h * 0.36), control: CGPoint(x: w * 0.40, y: h * 0.15))
            // Right ear
            path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.15))
            path.addQuadCurve(to: CGPoint(x: w * 0.60, y: h * 0.36), control: CGPoint(x: w * 0.58, y: h * 0.15))
            // Head & snout
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.42))
            path.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.60), control: CGPoint(x: w * 0.88, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.62))
            // Front neck
            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.92))
            path.closeSubpath()

            context.fill(path, with: .color(.primary))

            // Snout dot / eye
            let eye = CGRect(x: w * 0.56, y: h * 0.44, width: w * 0.07, height: h * 0.07)
            context.fill(Path(ellipseIn: eye), with: .color(Color(nsColor: .windowBackgroundColor)))
        }
    }
}

// MARK: - OpenRouter Logo (Authentic 'OR' Neon Lime Ligature)

private struct OpenRouterLogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Signature neon electric lime green
            let limeColor = Color(red: 0.78, green: 0.97, blue: 0.0)

            // Outer OR outline
            var outerPath = Path()
            
            // Start at top of left 'O' loop
            outerPath.move(to: CGPoint(x: w * 0.38, y: h * 0.10))
            // Top horizontal bridge to top of 'R'
            outerPath.addLine(to: CGPoint(x: w * 0.62, y: h * 0.10))
            // Top-right curve of 'R' loop
            outerPath.addCurve(
                to: CGPoint(x: w * 0.88, y: h * 0.38),
                control1: CGPoint(x: w * 0.80, y: h * 0.10),
                control2: CGPoint(x: w * 0.88, y: h * 0.22)
            )
            // Lower-right curve of 'R' loop inward to notch
            outerPath.addCurve(
                to: CGPoint(x: w * 0.70, y: h * 0.58),
                control1: CGPoint(x: w * 0.88, y: h * 0.50),
                control2: CGPoint(x: w * 0.80, y: h * 0.58)
            )
            // Diagonal leg of 'R' shooting down-right
            outerPath.addLine(to: CGPoint(x: w * 0.85, y: h * 0.83))
            // Rounded tip of 'R' leg
            outerPath.addQuadCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.90),
                control: CGPoint(x: w * 0.88, y: h * 0.90)
            )
            // Bottom horizontal line across to 'O'
            outerPath.addLine(to: CGPoint(x: w * 0.38, y: h * 0.90))
            // Left circular curve of 'O'
            outerPath.addCurve(
                to: CGPoint(x: w * 0.12, y: h * 0.50),
                control1: CGPoint(x: w * 0.22, y: h * 0.90),
                control2: CGPoint(x: w * 0.12, y: h * 0.72)
            )
            outerPath.addCurve(
                to: CGPoint(x: w * 0.38, y: h * 0.10),
                control1: CGPoint(x: w * 0.12, y: h * 0.28),
                control2: CGPoint(x: w * 0.22, y: h * 0.10)
            )
            outerPath.closeSubpath()

            // Inner circle knockout for 'O' counter
            let holeRect = CGRect(x: w * 0.24, y: h * 0.32, width: w * 0.28, height: h * 0.36)
            var holePath = Path()
            holePath.addEllipse(in: holeRect)

            var compoundPath = Path()
            compoundPath.addPath(outerPath)
            compoundPath.addPath(holePath)

            context.fill(compoundPath, with: .color(limeColor), style: FillStyle(eoFill: true))
        }
    }
}

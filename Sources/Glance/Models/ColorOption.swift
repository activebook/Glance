import Foundation
import SwiftUI
import AppKit

/// Flexible color model supporting custom hex colors, native ColorPicker integration,
/// and curated quick-selection palette swatches.
struct ColorOption: Codable, Equatable, Hashable, Identifiable {
    var hex: String

    var id: String { hex }

    init(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.hex = clean.hasPrefix("#") ? clean : "#" + clean
    }

    init(color: Color) {
        let nsColor = NSColor(color)
        if let rgb = nsColor.usingColorSpace(.sRGB) {
            let r = Int(round(rgb.redComponent * 255))
            let g = Int(round(rgb.greenComponent * 255))
            let b = Int(round(rgb.blueComponent * 255))
            let a = Int(round(rgb.alphaComponent * 255))
            if a < 255 {
                self.hex = String(format: "#%02X%02X%02X%02X", r, g, b, a)
            } else {
                self.hex = String(format: "#%02X%02X%02X", r, g, b)
            }
        } else {
            self.hex = "#FFFFFF"
        }
    }

    var color: Color {
        Color(hexString: hex) ?? .primary
    }

    var displayName: String {
        switch hex.uppercased() {
        case "#FFFFFF": return "Crisp White"
        case "#A1A1AA", "#A0A0A0": return "Muted Gray"
        case "#71717A", "#707070": return "Subtle Slate"
        case "#38BDF8": return "Sky Blue"
        case "#22D3EE": return "Electric Cyan"
        case "#34D399": return "Emerald Green"
        case "#FBBF24": return "Warm Amber"
        case "#FB923C": return "Vibrant Orange"
        case "#F43F5E": return "Rose Coral"
        case "#C084FC": return "Soft Violet"
        default: return hex
        }
    }

    // Preset Swatches
    static let white = ColorOption(hex: "#FFFFFF")
    static let primary = ColorOption(hex: "#FFFFFF")
    static let secondary = ColorOption(hex: "#A1A1AA")
    static let tertiary = ColorOption(hex: "#71717A")
    static let accent = ColorOption(hex: "#38BDF8")
    static let cyan = ColorOption(hex: "#22D3EE")
    static let emerald = ColorOption(hex: "#34D399")
    static let amber = ColorOption(hex: "#FBBF24")
    static let orange = ColorOption(hex: "#FB923C")
    static let rose = ColorOption(hex: "#F43F5E")
    static let purple = ColorOption(hex: "#C084FC")

    /// Curated palette presented in Appearance settings
    static let allCases: [ColorOption] = [
        .white,
        .secondary,
        .tertiary,
        .accent,
        .cyan,
        .emerald,
        .amber,
        .orange,
        .rose,
        .purple
    ]

    // Backward-compatible decode
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        switch str.lowercased() {
        case "primary", "white": self = .white
        case "secondary": self = .secondary
        case "tertiary": self = .tertiary
        case "accent": self = .accent
        case "cyan": self = .cyan
        case "emerald": self = .emerald
        case "amber": self = .amber
        case "purple": self = .purple
        case "orange": self = .orange
        case "rose": self = .rose
        default:
            self.init(hex: str)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

extension Color {
    init?(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard let hexVal = UInt64(clean, radix: 16) else { return nil }
        if clean.count == 6 {
            let r = Double((hexVal >> 16) & 0xFF) / 255.0
            let g = Double((hexVal >> 8) & 0xFF) / 255.0
            let b = Double(hexVal & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        } else if clean.count == 8 {
            let r = Double((hexVal >> 24) & 0xFF) / 255.0
            let g = Double((hexVal >> 16) & 0xFF) / 255.0
            let b = Double((hexVal >> 8) & 0xFF) / 255.0
            let a = Double(hexVal & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        } else {
            return nil
        }
    }
}

import Foundation
import SwiftUI
import AppKit

/// Visual theme and blur intensity for the floating translation HUD.
enum HUDAppearanceStyle: String, CaseIterable, Codable, Identifiable {
    case translucentDark = "translucentDark"
    case frostedGlass = "frostedGlass"
    case solidDark = "solidDark"
    case acrylicVibrant = "acrylicVibrant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translucentDark: return "Translucent Dark"
        case .frostedGlass: return "Frosted Glass"
        case .solidDark: return "Deep Obsidian"
        case .acrylicVibrant: return "Vibrant Acrylic"
        }
    }

    var subtitle: String {
        switch self {
        case .translucentDark: return "Deep acrylic blur with subtle hairline glow"
        case .frostedGlass: return "High translucency with crystal glass dispersion"
        case .solidDark: return "Matte opaque dark surface with high contrast"
        case .acrylicVibrant: return "Adaptive native macOS dynamic material blur"
        }
    }

    var icon: String {
        switch self {
        case .translucentDark: return "moon.stars.fill"
        case .frostedGlass: return "sparkles"
        case .solidDark: return "circle.fill"
        case .acrylicVibrant: return "macwindow"
        }
    }

    var displayName: String {
        "\(title) — \(subtitle)"
    }

    @ViewBuilder
    func backgroundView(opacity: Double) -> some View {
        switch self {
        case .translucentDark:
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.48)
            }
            .opacity(opacity)
        case .frostedGlass:
            ZStack {
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                Color.white.opacity(0.06)
            }
            .opacity(opacity)
        case .solidDark:
            Color(red: 0.12, green: 0.13, blue: 0.16)
                .opacity(opacity)
        case .acrylicVibrant:
            VisualEffectBackground(material: .headerView, blendingMode: .behindWindow)
                .opacity(opacity)
        }
    }

    @ViewBuilder
    func previewBackgroundView(opacity: Double) -> some View {
        switch self {
        case .translucentDark:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .opacity(opacity)
        case .frostedGlass:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.white.opacity(0.14)
            }
            .opacity(opacity)
        case .solidDark:
            Color(red: 0.12, green: 0.13, blue: 0.16)
                .opacity(opacity)
        case .acrylicVibrant:
            Rectangle().fill(.regularMaterial)
                .opacity(opacity)
        }
    }

    @ViewBuilder
    var backgroundView: some View {
        backgroundView(opacity: 0.85)
    }

    var borderStrokeColor: Color {
        switch self {
        case .translucentDark:
            return Color.white.opacity(0.20)
        case .frostedGlass:
            return Color.white.opacity(0.30)
        case .solidDark:
            return Color.white.opacity(0.14)
        case .acrylicVibrant:
            return Color.primary.opacity(0.18)
        }
    }
}

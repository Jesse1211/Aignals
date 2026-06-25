// App/Aignals/Sources/ThemeStyle.swift
import SwiftUI
import AppKit
import AignalsCore

/// Concrete SwiftUI style values for a `Theme` (ADR-0808). The pure `Theme`
/// enum lives in AignalsCore; this maps each case to colors/fonts/materials the
/// views actually render. Verified by build + manual smoke (no UI-test harness).
struct ThemeStyle {
    var panelMaterial: NSVisualEffectView.Material?   // non-nil → glass; nil → fixed color
    var panelAppearance: NSAppearance.Name?           // glass appearance (aqua / darkAqua)
    var panelColor: Color                             // fixed fill for non-glass (Terminal/Vibrant)
    var textPrimary: Color
    var textSecondary: Color
    var hairline: Color
    var rowCorner: CGFloat
    var usesMonospaced: Bool
    var dotGlow: Bool
    var rowPrefix: String?                            // e.g. "›" for terminal
    var rowTint: (SessionState) -> Color?             // non-nil only for vibrant

    static func tokens(for theme: Theme) -> ThemeStyle {
        switch theme {
        case .glassLight:
            return ThemeStyle(
                panelMaterial: .popover, panelAppearance: .aqua,
                panelColor: Color(hex: "#FAFAFC"),
                textPrimary: .primary, textSecondary: .secondary,
                hairline: Color.black.opacity(0.08), rowCorner: 10,
                usesMonospaced: false, dotGlow: true, rowPrefix: nil,
                rowTint: { _ in nil })
        case .glassDark:
            return ThemeStyle(
                panelMaterial: .popover, panelAppearance: .darkAqua,
                panelColor: Color(hex: "#1C1C24"),
                textPrimary: .primary, textSecondary: .secondary,
                hairline: Color.white.opacity(0.10), rowCorner: 10,
                usesMonospaced: false, dotGlow: true, rowPrefix: nil,
                rowTint: { _ in nil })
        case .terminal:
            return ThemeStyle(
                panelMaterial: nil, panelAppearance: .darkAqua,
                panelColor: Color(hex: "#0C0F0A"),
                textPrimary: Color(hex: "#D8FFE0"), textSecondary: Color(hex: "#5AA86A"),
                hairline: Color(hex: "#1D3B22"), rowCorner: 6,
                usesMonospaced: true, dotGlow: false, rowPrefix: "›",
                rowTint: { _ in nil })
        case .vibrant:
            return ThemeStyle(
                panelMaterial: nil, panelAppearance: .darkAqua,
                panelColor: Color(hex: "#16121F"),
                textPrimary: .white, textSecondary: Color.white.opacity(0.6),
                hairline: Color.white.opacity(0.08), rowCorner: 10,
                usesMonospaced: false, dotGlow: true, rowPrefix: nil,
                rowTint: { state in
                    switch state {
                    case .working:           return Color(hex: "#FF453A")
                    case .waitingPermission: return Color(hex: "#FFD60A")
                    case .waitingInput:      return Color(hex: "#32D74B")
                    case .disconnected:      return nil
                    }
                })
        }
    }
}

/// `NSVisualEffectView` wrapper for the glass themes. Applies the theme's
/// material + appearance so the panel blurs the desktop behind it.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearance: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        if let appearance { v.appearance = NSAppearance(named: appearance) }
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        if let appearance { v.appearance = NSAppearance(named: appearance) }
    }
}

extension Color {
    /// `#RRGGBB` → Color. Falls back to clear on a malformed string.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&rgb) else {
            self = .clear; return
        }
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Inject the current `ThemeStyle` down the view tree.
private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.tokens(for: .glassDark)
}
extension EnvironmentValues {
    var themeStyle: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}

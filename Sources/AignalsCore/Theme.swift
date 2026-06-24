import Foundation

/// The four user-selectable visual themes for the dropdown + About window
/// (ADR-0808). Glass Light/Dark use a live system material; Terminal and
/// Vibrant are fixed palettes that deliberately do NOT follow the system
/// appearance. The enum is pure (no SwiftUI/AppKit) so it lives in
/// `AignalsCore` and is unit-tested; the App target maps each case to concrete
/// SwiftUI style values in `ThemeStyle.swift`.
public enum Theme: String, Codable, CaseIterable, Sendable {
    case glassLight
    case glassDark
    case terminal
    case vibrant

    /// Human-readable name shown in the picker.
    public var displayName: String {
        switch self {
        case .glassLight: return "Glass Light"
        case .glassDark:  return "Glass Dark"
        case .terminal:   return "Terminal"
        case .vibrant:    return "Vibrant"
        }
    }

    /// 1–3 hex colors previewing the theme in the picker's swatch. Pure data so
    /// it can be unit-tested and reused by the SwiftUI swatch view.
    public var swatchHexes: [String] {
        switch self {
        case .glassLight: return ["#F4F4F7", "#DCDCE4"]
        case .glassDark:  return ["#3A3A48", "#1E1E28"]
        case .terminal:   return ["#0C0F0A", "#143D1C"]
        case .vibrant:    return ["#FF453A", "#FFD60A", "#32D74B"]
        }
    }
}

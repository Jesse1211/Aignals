import Foundation

/// The three pages of the standalone Settings window, used both as the sidebar
/// model and as the "land on this page" selector when the window is opened from
/// the menu (Settings… → .general) or the brand header (ⓘ → .about).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case customization
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .customization: return "Customization"
        case .about: return "About"
        }
    }

    /// SF Symbol shown beside the title in the sidebar.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .customization: return "paintpalette"
        case .about: return "info.circle"
        }
    }
}

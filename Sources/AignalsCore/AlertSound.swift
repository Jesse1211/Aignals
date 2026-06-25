import Foundation

/// A user-selectable alert sound for a waiting state (ADR-28/29). Pure data so
/// it lives in `AignalsCore` and is unit-tested; the App target maps the cases
/// to playback. `.none` is silent (`systemSoundName == nil`). Every other case
/// names a stock macOS system sound resolvable by `NSSound(named:)` and present
/// at `/System/Library/Sounds/<Name>.aiff`.
public enum AlertSound: String, Codable, CaseIterable, Sendable {
    case none
    case ping
    case glass
    case funk
    case tink
    case pop
    case hero
    case submarine
    case blow

    /// Human-readable label shown in the picker.
    public var displayName: String {
        switch self {
        case .none:      return "None"
        case .ping:      return "Ping"
        case .glass:     return "Glass"
        case .funk:      return "Funk"
        case .tink:      return "Tink"
        case .pop:       return "Pop"
        case .hero:      return "Hero"
        case .submarine: return "Submarine"
        case .blow:      return "Blow"
        }
    }

    /// The macOS system-sound name to play, or `nil` for `.none` (silent).
    public var systemSoundName: String? {
        switch self {
        case .none:      return nil
        case .ping:      return "Ping"
        case .glass:     return "Glass"
        case .funk:      return "Funk"
        case .tink:      return "Tink"
        case .pop:       return "Pop"
        case .hero:      return "Hero"
        case .submarine: return "Submarine"
        case .blow:      return "Blow"
        }
    }
}

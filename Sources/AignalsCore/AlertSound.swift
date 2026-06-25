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

    /// Human-readable label shown in the picker. Every sound case is a single
    /// lowercase word, so its label is just the capitalized raw value (Ping,
    /// Glass, …); `.none` reads "None".
    public var displayName: String {
        switch self {
        case .none: return "None"
        default:    return rawValue.capitalized
        }
    }

    /// The macOS system-sound name to play, or `nil` for `.none` (silent). The
    /// non-silent names match `displayName` exactly and resolve via
    /// `NSSound(named:)` (e.g. /System/Library/Sounds/Ping.aiff).
    public var systemSoundName: String? {
        switch self {
        case .none: return nil
        default:    return displayName
        }
    }
}

import Foundation

/// The multi-status lifecycle state of a single agent session.
///
/// Backed by a snake_case JSON string on the session file's `state` key
/// (ADR-2: value object lives in `AignalsCore`; ADR-10: required field with
/// strict round-trip). Unknown / missing strings return `nil` so the caller
/// decides how to treat them (here: a decode failure for the required field).
public enum SessionState: String, Equatable, Sendable, CaseIterable {
    case working = "working"
    case waitingPermission = "waiting_permission"
    case waitingInput = "waiting_input"

    /// Passive-death state (gray). Set ONLY by the app's `PIDSweeper` when a
    /// session's `pid` is found dead (ADR-13/ADR-14). It is NEVER written by
    /// `aignals-hook`: passive death fires no hook (INV-12). Parses/serializes
    /// the JSON string `"disconnected"` for round-trip symmetry.
    case disconnected = "disconnected"

    /// Parse from the JSON snake_case string. Unknown values -> `nil`.
    public init?(jsonValue: String) {
        self.init(rawValue: jsonValue)
    }

    /// The snake_case JSON string for this state (round-trips with `init?`).
    public var jsonValue: String { rawValue }
}

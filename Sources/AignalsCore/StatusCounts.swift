import Foundation

/// Immutable, derived tally of active sessions grouped by their `SessionState`
/// (ADR-3: multi-status replaces the old tri-state `AggregateStatus`; ADR-9:
/// the store derives counts rather than carrying a single aggregate enum).
///
/// INV-4: `working + waitingPermission + waitingInput == sessions.count`.
public struct StatusCounts: Equatable, Sendable {
    public let working: Int
    public let waitingPermission: Int
    public let waitingInput: Int

    public init(working: Int, waitingPermission: Int, waitingInput: Int) {
        self.working = working
        self.waitingPermission = waitingPermission
        self.waitingInput = waitingInput
    }

    /// All-zero counts (no active sessions). The "idle" equivalent.
    public static let zero = StatusCounts(working: 0, waitingPermission: 0, waitingInput: 0)

    /// Total number of sessions represented (INV-4).
    public var total: Int { working + waitingPermission + waitingInput }

    /// `true` when no sessions are present in any state.
    public var isEmpty: Bool { total == 0 }

    /// Derive counts by grouping sessions by their `state` and counting each.
    public init(sessions: [Session]) {
        var w = 0, wp = 0, wi = 0
        for s in sessions {
            switch s.state {
            case .working: w += 1
            case .waitingPermission: wp += 1
            case .waitingInput: wi += 1
            }
        }
        self.init(working: w, waitingPermission: wp, waitingInput: wi)
    }
}

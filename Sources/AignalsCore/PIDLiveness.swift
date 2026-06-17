import Foundation
import Darwin

public enum PIDState: Equatable, Sendable {
    case alive
    case dead
    case unknown
}

public protocol PIDLiveness: Sendable {
    func state(of pid: pid_t) -> PIDState
}

public struct SystemPIDLiveness: PIDLiveness {
    public init() {}
    public func state(of pid: pid_t) -> PIDState {
        guard pid > 0 else { return .unknown }
        let r = kill(pid, 0)
        if r == 0 { return .alive }
        switch errno {
        case ESRCH: return .dead
        case EPERM: return .alive   // exists but not ours
        default:    return .unknown
        }
    }
}

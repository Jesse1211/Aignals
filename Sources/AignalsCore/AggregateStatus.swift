import Foundation

public enum AggregateStatus: Equatable, Sendable {
    case idle
    case running
    case error
}

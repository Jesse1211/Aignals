import Foundation
import Observation

@MainActor
@Observable
public final class SessionStore {
    public private(set) var sessions: [Session] = []
    public private(set) var hasFSAccessError: Bool = false

    public var aggregateStatus: AggregateStatus {
        if hasFSAccessError { return .error }
        return sessions.isEmpty ? .idle : .running
    }

    // Async sequence for tests / FSEventsWatcher integration tests.
    public let changes: AsyncStream<AggregateStatus>
    private let continuation: AsyncStream<AggregateStatus>.Continuation

    public init() {
        var cont: AsyncStream<AggregateStatus>.Continuation!
        self.changes = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func upsert(_ session: Session) {
        if let idx = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.startedAt < $1.startedAt }
        publish()
    }

    public func remove(id: String) {
        sessions.removeAll { $0.sessionID == id }
        publish()
    }

    public func setFSAccessError(_ flag: Bool) {
        guard hasFSAccessError != flag else { return }
        hasFSAccessError = flag
        publish()
    }

    public func reset() {
        sessions.removeAll()
        hasFSAccessError = false
        publish()
    }

    private func publish() {
        continuation.yield(aggregateStatus)
    }
}

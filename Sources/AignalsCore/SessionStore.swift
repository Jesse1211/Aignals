import Foundation
import Observation
import os

@MainActor
@Observable
public final class SessionStore {
    public private(set) var sessions: [Session] = []
    public private(set) var hasFSAccessError: Bool = false

    /// FS-access health re-homed from the old `AggregateStatus.error` case
    /// (ADR-9): `true` when the store cannot read the sessions directory.
    public var hasError: Bool { hasFSAccessError }

    /// Derived per-state tally of active sessions (ADR-3/ADR-9). Replaces the
    /// old running/idle aggregate: nonzero total ≈ "running", all-zero ≈ "idle".
    /// INV-4: `working + waitingPermission + waitingInput == sessions.count`.
    public var statusCounts: StatusCounts {
        StatusCounts(sessions: sessions)
    }

    // Async sequence for tests / FSEventsWatcher integration tests.
    public let changes: AsyncStream<StatusCounts>
    private let continuation: AsyncStream<StatusCounts>.Continuation

    public init() {
        var cont: AsyncStream<StatusCounts>.Continuation!
        self.changes = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func upsert(_ session: Session) {
        if let idx = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
            // INV-8 defense at the store layer: drop a stale update if the
            // existing session was updated more recently (ADR-3).
            if sessions[idx].updatedAt > session.updatedAt { return }
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
        continuation.yield(statusCounts)
    }
}

extension SessionStore {
    private static let log = Logger(subsystem: "com.aignals.Aignals", category: "SessionStore")

    public func loadFromDisk(path: URL) {
        guard let data = try? Data(contentsOf: path) else { return }
        do {
            let s = try Session.decode(from: data)
            upsert(s)
        } catch {
            Self.log.debug("skip \(path.lastPathComponent): \(String(describing: error))")
        }
    }

    public func removeBy(filename: String) {
        let id = (filename as NSString).deletingPathExtension
        remove(id: id)
    }
}

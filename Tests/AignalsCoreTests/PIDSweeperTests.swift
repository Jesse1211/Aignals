import XCTest
@testable import AignalsCore

@MainActor
final class PIDSweeperTests: XCTestCase {
    private struct FakeLiveness: PIDLiveness {
        let aliveSet: Set<pid_t>
        func state(of pid: pid_t) -> PIDState { aliveSet.contains(pid) ? .alive : .dead }
    }

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-sweeper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeSession(id: String, pid: Int32?, in dir: URL, mtime: Date? = nil) throws {
        let pidJSON = pid.map { "\"pid\": \($0)," } ?? ""
        let json = """
        {
          "schema_version": 2, "session_id": "\(id)", "tool": "t",
          \(pidJSON)
          "project_name": "p", "state": "working",
          "started_at": "2026-06-16T14:00:00Z", "updated_at": "2026-06-16T14:00:00Z"
        }
        """
        let url = dir.appendingPathComponent("\(id).json")
        try Data(json.utf8).write(to: url)
        if let m = mtime {
            try FileManager.default.setAttributes([.modificationDate: m], ofItemAtPath: url.path)
        }
    }

    /// Helper: load a session JSON file into the store via public APIs that
    /// exist on this branch (Phase 4 will introduce `SessionStore.loadFromDisk`).
    private func loadIntoStore(_ store: SessionStore, from url: URL) throws {
        let data = try Data(contentsOf: url)
        let session = try Session.decode(from: data)
        store.upsert(session)
    }

    func testDeadPIDRemovesFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(id: "a", pid: 1234, in: dir)

        let store = SessionStore()
        try loadIntoStore(store, from: dir.appendingPathComponent("a.json"))
        XCTAssertEqual(store.aggregateStatus, .running)

        let sweeper = PIDSweeper(
            sessionsDirectory: dir,
            store: store,
            liveness: FakeLiveness(aliveSet: [])
        )
        sweeper.sweepOnce()

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.json").path))
        XCTAssertEqual(store.aggregateStatus, .idle)
    }

    func testAlivePIDPreservesFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(id: "a", pid: 1234, in: dir)
        let store = SessionStore()
        try loadIntoStore(store, from: dir.appendingPathComponent("a.json"))

        let sweeper = PIDSweeper(
            sessionsDirectory: dir,
            store: store,
            liveness: FakeLiveness(aliveSet: [1234])
        )
        sweeper.sweepOnce()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.json").path))
        XCTAssertEqual(store.aggregateStatus, .running)
    }

    func testMissingPIDFallsBackToMtimeOnlyForStaleFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // No pid; fresh mtime → keep
        try writeSession(id: "fresh", pid: nil, in: dir, mtime: Date())
        // No pid; mtime 25h ago → delete
        try writeSession(id: "stale", pid: nil, in: dir, mtime: Date().addingTimeInterval(-25 * 3600))

        let store = SessionStore()
        try loadIntoStore(store, from: dir.appendingPathComponent("fresh.json"))
        try loadIntoStore(store, from: dir.appendingPathComponent("stale.json"))

        let sweeper = PIDSweeper(
            sessionsDirectory: dir,
            store: store,
            liveness: FakeLiveness(aliveSet: [])
        )
        sweeper.sweepOnce()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("fresh.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("stale.json").path))
    }

    func testUnreadableSessionsDirSetsErrorState() throws {
        let dir = try makeTempDir()
        defer {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let store = SessionStore()
        let sweeper = PIDSweeper(
            sessionsDirectory: dir,
            store: store,
            liveness: FakeLiveness(aliveSet: [])
        )

        // chmod 000 → unreadable
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        sweeper.sweepOnce()
        XCTAssertEqual(store.aggregateStatus, .error)

        // restore → recover
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        sweeper.sweepOnce()
        XCTAssertEqual(store.aggregateStatus, .idle)
    }
}

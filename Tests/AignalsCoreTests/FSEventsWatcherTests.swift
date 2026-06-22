import XCTest
@testable import AignalsCore

@MainActor
final class FSEventsWatcherTests: XCTestCase {
    func testEmitsOnCreate() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = SessionStore()
        let watcher = FSEventsWatcher(directory: dir, store: store)
        watcher.start()
        defer { watcher.stop() }

        try writeSession(id: "a", to: dir)
        await waitForNonEmpty(store, timeout: 2.0)
        XCTAssertEqual(store.sessions.map(\.sessionID), ["a"])
    }

    func testEmitsOnDelete() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = SessionStore()
        let watcher = FSEventsWatcher(directory: dir, store: store)
        watcher.start()
        defer { watcher.stop() }

        try writeSession(id: "a", to: dir)
        await waitForNonEmpty(store, timeout: 2.0)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.json"))
        await waitForEmpty(store, timeout: 2.0)
    }

    func testIgnoresNonJSONFiles() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = SessionStore()
        let watcher = FSEventsWatcher(directory: dir, store: store)
        watcher.start()
        defer { watcher.stop() }

        // unrelated file → ignored
        try Data("noise".utf8).write(to: dir.appendingPathComponent("README.txt"))
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // helpers
    private func makeTempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-fsewt-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeSession(id: String, to dir: URL) throws {
        let json = """
        {
          "schema_version": 2, "session_id": "\(id)", "tool": "t",
          "project_name": "p", "state": "working",
          "started_at": "2026-06-16T14:00:00Z", "updated_at": "2026-06-16T14:00:00Z"
        }
        """
        let final = dir.appendingPathComponent("\(id).json")
        let tmp = dir.appendingPathComponent("\(id).json.tmp")
        try Data(json.utf8).write(to: tmp)
        try FileManager.default.moveItem(at: tmp, to: final)
    }

    /// Await a `StatusCounts` emission satisfying `predicate`, consuming the
    /// store's `changes` AsyncStream (now typed as `StatusCounts`).
    private func waitFor(
        _ store: SessionStore,
        timeout: TimeInterval,
        where predicate: @escaping (StatusCounts) -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        for await counts in store.changes {
            if predicate(counts) { return }
            if Date() > deadline { break }
        }
        XCTFail("Timed out; current counts = \(store.statusCounts)")
    }

    /// old `.running` (sessions present) → nonzero total.
    private func waitForNonEmpty(_ store: SessionStore, timeout: TimeInterval) async {
        await waitFor(store, timeout: timeout) { $0.total > 0 }
    }

    /// old `.idle` (no sessions) → all-zero counts.
    private func waitForEmpty(_ store: SessionStore, timeout: TimeInterval) async {
        await waitFor(store, timeout: timeout) { $0.isEmpty }
    }
}

import XCTest
@testable import AignalsCore

@MainActor
final class SessionStoreTests: XCTestCase {
    private func makeSession(id: String, startedAt: Date = Date()) -> Session {
        Session(
            sessionID: id,
            tool: "claude-code",
            pid: 1,
            projectName: id,
            cwd: nil,
            startedAt: startedAt,
            updatedAt: startedAt,
            state: .working,
            currentAction: nil
        )
    }

    func testEmptyStoreIsIdle() {
        let store = SessionStore()
        XCTAssertEqual(store.aggregateStatus, .idle)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testUpsertAddsSession() {
        let store = SessionStore()
        store.upsert(makeSession(id: "a"))
        XCTAssertEqual(store.aggregateStatus, .running)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testUpsertReplacesExistingByID() {
        let store = SessionStore()
        let s1 = makeSession(id: "a")
        store.upsert(s1)
        let s2 = Session(
            sessionID: "a",
            tool: "claude-code",
            pid: 2,
            projectName: "renamed",
            cwd: nil,
            startedAt: s1.startedAt,
            updatedAt: s1.startedAt,
            state: .working,
            currentAction: nil
        )
        store.upsert(s2)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.projectName, "renamed")
    }

    func testRemoveByID() {
        let store = SessionStore()
        store.upsert(makeSession(id: "a"))
        store.upsert(makeSession(id: "b"))
        store.remove(id: "a")
        XCTAssertEqual(store.sessions.map(\.sessionID), ["b"])
    }

    func testSessionsSortedByStartedAtAscending() {
        let store = SessionStore()
        let now = Date()
        store.upsert(makeSession(id: "newer", startedAt: now))
        store.upsert(makeSession(id: "older", startedAt: now.addingTimeInterval(-60)))
        XCTAssertEqual(store.sessions.map(\.sessionID), ["older", "newer"])
    }

    func testErrorStateOverridesIdleAndRunning() {
        let store = SessionStore()
        store.setFSAccessError(true)
        XCTAssertEqual(store.aggregateStatus, .error)
        store.upsert(makeSession(id: "a"))
        XCTAssertEqual(store.aggregateStatus, .error)  // error wins
        store.setFSAccessError(false)
        XCTAssertEqual(store.aggregateStatus, .running)
    }

    func testStateChangesPublishedAsAsyncSequence() async {
        let store = SessionStore()
        var iter = store.changes.makeAsyncIterator()
        Task { store.upsert(self.makeSession(id: "a")) }
        let next = await iter.next()
        XCTAssertEqual(next, .running)
    }
}

extension SessionStoreTests {
    func testLoadFromDiskUpsertsValidFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let json = """
        {
          "schema_version": 2, "session_id": "a", "tool": "t",
          "project_name": "p", "state": "working",
          "started_at": "2026-06-16T14:00:00Z", "updated_at": "2026-06-16T14:00:00Z"
        }
        """
        try Data(json.utf8).write(to: tmp)

        let store = SessionStore()
        store.loadFromDisk(path: tmp)
        XCTAssertEqual(store.sessions.map(\.sessionID), ["a"])
    }

    func testLoadFromDiskIgnoresMalformed() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("not json".utf8).write(to: tmp)

        let store = SessionStore()
        store.loadFromDisk(path: tmp)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testLoadFromDiskIgnoresMissingFile() {
        let store = SessionStore()
        store.loadFromDisk(path: URL(fileURLWithPath: "/no/such/file.json"))
        XCTAssertTrue(store.sessions.isEmpty)
    }
}

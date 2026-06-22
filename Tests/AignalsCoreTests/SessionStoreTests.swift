import XCTest
@testable import AignalsCore

@MainActor
final class SessionStoreTests: XCTestCase {
    private func makeSession(
        id: String, startedAt: Date = Date(), state: SessionState = .working
    ) -> Session {
        Session(
            sessionID: id,
            tool: "claude-code",
            pid: 1,
            projectName: id,
            cwd: nil,
            startedAt: startedAt,
            updatedAt: startedAt,
            state: state,
            currentAction: nil
        )
    }

    func testEmptyStoreIsIdle() {
        let store = SessionStore()
        XCTAssertEqual(store.statusCounts, .zero)
        XCTAssertFalse(store.hasError)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testUpsertAddsSession() {
        let store = SessionStore()
        store.upsert(makeSession(id: "a"))
        XCTAssertEqual(store.statusCounts.total, 1)
        XCTAssertEqual(store.statusCounts.working, 1)
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

    func testHasErrorFlagIsIndependentOfCounts() {
        let store = SessionStore()
        store.setFSAccessError(true)
        XCTAssertTrue(store.hasError)
        XCTAssertEqual(store.statusCounts, .zero)  // no sessions yet
        store.upsert(makeSession(id: "a"))
        XCTAssertTrue(store.hasError)              // error flag still set
        XCTAssertEqual(store.statusCounts.total, 1)
        store.setFSAccessError(false)
        XCTAssertFalse(store.hasError)
        XCTAssertEqual(store.statusCounts.total, 1)
    }

    func testStatusCountsGroupByState() {
        let store = SessionStore()
        store.upsert(makeSession(id: "w1", state: .working))
        store.upsert(makeSession(id: "w2", state: .working))
        store.upsert(makeSession(id: "p1", state: .waitingPermission))
        store.upsert(makeSession(id: "i1", state: .waitingInput))
        let counts = store.statusCounts
        XCTAssertEqual(counts.working, 2)
        XCTAssertEqual(counts.waitingPermission, 1)
        XCTAssertEqual(counts.waitingInput, 1)
        // INV-4: the three buckets sum to the session count.
        XCTAssertEqual(counts.total, store.sessions.count)
    }

    func testUpsertDropsStaleUpdateByUpdatedAt() {
        let store = SessionStore()
        let started = Date()
        let newer = Session(
            sessionID: "a", tool: "claude-code", pid: 1, projectName: "newer",
            cwd: nil, startedAt: started, updatedAt: started.addingTimeInterval(10),
            state: .waitingInput, currentAction: nil
        )
        let older = Session(
            sessionID: "a", tool: "claude-code", pid: 1, projectName: "older",
            cwd: nil, startedAt: started, updatedAt: started,
            state: .working, currentAction: nil
        )
        store.upsert(newer)
        store.upsert(older)  // INV-8: stale → dropped
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.projectName, "newer")
        XCTAssertEqual(store.sessions.first?.state, .waitingInput)
    }

    func testStateChangesPublishedAsAsyncSequence() async {
        let store = SessionStore()
        var iter = store.changes.makeAsyncIterator()
        Task { store.upsert(self.makeSession(id: "a")) }
        let next = await iter.next()
        XCTAssertEqual(next, StatusCounts(working: 1, waitingPermission: 0, waitingInput: 0))
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

    /// H1 / INV-8 end-to-end: two same-second updates that differ only in
    /// milliseconds must order correctly through loadFromDisk → decode → upsert's
    /// `updatedAt >` guard. The store compares Dates, so this proves millisecond
    /// precision flows all the way through. Loading the EARLIER-ms file after the
    /// later one must be dropped as stale; loading the later one over the earlier
    /// one must apply.
    func testMillisecondPrecisionFlowsThroughStaleGuard() throws {
        func writeFile(_ ts: String, state: String) throws -> URL {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("aignals-ms-\(UUID().uuidString).json")
            let json = """
            {"schema_version":2,"session_id":"a","tool":"t","project_name":"p",
             "state":"\(state)","started_at":"\(ts)","updated_at":"\(ts)"}
            """
            try Data(json.utf8).write(to: tmp)
            return tmp
        }
        let early = try writeFile("2026-06-22T13:51:33.100Z", state: "working")
        let late  = try writeFile("2026-06-22T13:51:33.900Z", state: "waiting_input")
        defer { try? FileManager.default.removeItem(at: early); try? FileManager.default.removeItem(at: late) }

        let store = SessionStore()
        store.loadFromDisk(path: late)          // newer ms wins
        store.loadFromDisk(path: early)         // same second, earlier ms → dropped
        XCTAssertEqual(store.sessions.first?.state, .waitingInput,
                       "earlier-millisecond same-second update must be dropped as stale")

        let store2 = SessionStore()
        store2.loadFromDisk(path: early)        // older first
        store2.loadFromDisk(path: late)         // later ms applies
        XCTAssertEqual(store2.sessions.first?.state, .waitingInput,
                       "later-millisecond same-second update must apply")
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

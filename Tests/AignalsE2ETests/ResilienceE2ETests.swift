import XCTest
@testable import AignalsCore

@MainActor
final class ResilienceE2ETests: XCTestCase {
    private struct ScriptedLiveness: PIDLiveness {
        let aliveSet: Set<pid_t>
        func state(of pid: pid_t) -> PIDState { aliveSet.contains(pid) ? .alive : .dead }
    }

    private var harnesses: [Harness] = []

    override func tearDown() async throws {
        for h in harnesses { h.cleanup() }
        harnesses.removeAll()
    }

    private func makeHarness(liveness: PIDLiveness = SystemPIDLiveness()) throws -> Harness {
        let h = try Harness(liveness: liveness)
        harnesses.append(h)
        return h
    }

    private func waitUntilGone(_ file: URL, store: SessionStore, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !FileManager.default.fileExists(atPath: file.path), store.sessions.isEmpty { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func test_case07_deadPidRemovedBySweep() async throws {
        let h = try makeHarness(liveness: ScriptedLiveness(aliveSet: []))
        let file = h.paths.sessionFile(id: "orph")
        let json = """
        {"schema_version":1,"session_id":"orph","tool":"t","pid":99999,"project_name":"p","started_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        h.store.loadFromDisk(path: file)
        XCTAssertEqual(h.store.aggregateStatus, .running)

        await waitUntilGone(file, store: h.store)
        XCTAssertEqual(h.store.aggregateStatus, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_case08_mtimeBackstopForPidlessFile() async throws {
        let h = try makeHarness(liveness: ScriptedLiveness(aliveSet: []))
        let file = h.paths.sessionFile(id: "noPid")
        let json = """
        {"schema_version":1,"session_id":"noPid","tool":"t","project_name":"p","started_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        // sweeper.staleAfter = 1s, so a 5s-old mtime is stale.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
        h.store.loadFromDisk(path: file)

        await waitUntilGone(file, store: h.store)
        XCTAssertEqual(h.store.aggregateStatus, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_case09_malformedJsonIgnored() async throws {
        let h = try makeHarness()
        let file = h.paths.sessionFile(id: "bad")
        try Data("not json".utf8).write(to: file)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(h.store.sessions.isEmpty)
        XCTAssertEqual(h.store.aggregateStatus, .idle)
    }

    func test_case10_unknownSchemaVersionIgnored() async throws {
        let h = try makeHarness()
        let file = h.paths.sessionFile(id: "v2")
        let json = """
        {"schema_version":2,"session_id":"v2","tool":"t","project_name":"p","started_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(h.store.sessions.isEmpty)
        XCTAssertEqual(h.store.aggregateStatus, .idle)
    }

    func test_case11_atomicRenameProducesOneEvent() async throws {
        let h = try makeHarness()
        // Producer writes via tmp+mv (this is what aignals-hook does):
        try h.runHook("on-sessionstart", payload: "{\"session_id\":\"atom\",\"cwd\":\"/p\"}")
        XCTAssertTrue(await h.waitForStatus(.running))
        // After running, no .tmp files should remain in the dir.
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: h.paths.sessionsDirectory.path)
        XCTAssertFalse(entries.contains(where: { $0.contains(".tmp") }))
        XCTAssertEqual(h.store.sessions.map(\.sessionID), ["atom"])
    }

    func test_case12_unreadableDirEntersAndRecoversFromError() async throws {
        let h = try makeHarness()
        // chmod 000 the sessions dir → sweeper's FS-access probe flips to .error.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: h.paths.sessionsDirectory.path)
        XCTAssertTrue(await h.waitForStatus(.error))

        // restore
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: h.paths.sessionsDirectory.path)
        XCTAssertTrue(await h.waitForStatus(.idle))
    }
}

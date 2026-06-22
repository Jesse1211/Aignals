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

    /// Wait until the session with `id` reaches `state` (or timeout).
    private func waitUntilState(
        _ id: String, _ state: SessionState, store: SessionStore, timeout: TimeInterval = 3
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if store.sessions.first(where: { $0.sessionID == id })?.state == state { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// ADR-13/ADR-14, INV-12: a dead pid is no longer removed by the sweep — it
    /// is marked `.disconnected` (gray) and KEPT, with its file left in place.
    func test_case07_deadPidMarkedDisconnectedBySweep() async throws {
        let h = try makeHarness(liveness: ScriptedLiveness(aliveSet: []))
        let file = h.paths.sessionFile(id: "orph")
        let json = """
        {"schema_version":2,"session_id":"orph","tool":"t","pid":99999,"project_name":"p","state":"working","started_at":"2026-06-16T14:00:00Z","updated_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        h.store.loadFromDisk(path: file)
        XCTAssertTrue(h.store.statusCounts.total > 0)

        await waitUntilState("orph", .disconnected, store: h.store)
        XCTAssertEqual(h.store.sessions.first(where: { $0.sessionID == "orph" })?.state, .disconnected)
        XCTAssertEqual(h.store.statusCounts.disconnected, 1)
        XCTAssertEqual(h.store.statusCounts.activeTotal, 0)
        // File is preserved; the session stays visible (gray light).
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_case08_mtimeBackstopForPidlessFile() async throws {
        let h = try makeHarness(liveness: ScriptedLiveness(aliveSet: []))
        // This test exercises the mtime backstop specifically, so opt into a
        // short stale window (the harness default is large to protect live
        // lifecycle sessions from being swept mid-test).
        h.sweeper.staleAfter = 1.0
        let file = h.paths.sessionFile(id: "noPid")
        let json = """
        {"schema_version":2,"session_id":"noPid","tool":"t","project_name":"p","state":"working","started_at":"2026-06-16T14:00:00Z","updated_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        // staleAfter = 1s, so a 5s-old mtime is stale.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
        h.store.loadFromDisk(path: file)

        await waitUntilGone(file, store: h.store)
        XCTAssertTrue(h.store.statusCounts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_case09_malformedJsonIgnored() async throws {
        let h = try makeHarness()
        let file = h.paths.sessionFile(id: "bad")
        try Data("not json".utf8).write(to: file)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(h.store.sessions.isEmpty)
        XCTAssertTrue(h.store.statusCounts.isEmpty)
    }

    func test_case10_unknownSchemaVersionIgnored() async throws {
        let h = try makeHarness()
        let file = h.paths.sessionFile(id: "v3")
        // v2 is now the supported schema (T1); use a genuinely unknown version
        // with otherwise-complete fields so this tests schema rejection, not a
        // missing required field.
        let json = """
        {"schema_version":3,"session_id":"v3","tool":"t","project_name":"p","state":"working","started_at":"2026-06-16T14:00:00Z","updated_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(h.store.sessions.isEmpty)
        XCTAssertTrue(h.store.statusCounts.isEmpty)
    }

    func test_case11_atomicRenameProducesOneEvent() async throws {
        let h = try makeHarness()
        // Producer writes via tmp+mv (this is what aignals-hook does):
        try h.runHook("on-sessionstart", payload: "{\"session_id\":\"atom\",\"cwd\":\"/p\"}")
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)
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
        let reachedError = await h.waitForError()
        XCTAssertTrue(reachedError)

        // restore
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: h.paths.sessionsDirectory.path)
        let reachedIdle = await h.waitForIdle()
        XCTAssertTrue(reachedIdle)
    }
}

import XCTest
@testable import AignalsCore

@MainActor
final class LifecycleE2ETests: XCTestCase {
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

    private func payload(_ kvs: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: kvs)
        return String(decoding: data, as: UTF8.self)
    }

    /// Poll until the first session's current_action matches, or time out.
    private func waitForAction(
        _ h: Harness, tool: String, target: String, timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let action = h.store.sessions.first?.currentAction
            if action?.tool == tool, action?.target == target { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func test_case01_sessionstartFlipsToRunning() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s1", "cwd": "/proj"]))
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)
        XCTAssertEqual(h.store.sessions.map(\.sessionID), ["s1"])
    }

    func test_case02_stopReturnsToIdle() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s1", "cwd": "/proj"]))
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)
        try h.runHook("on-stop", payload: payload(["session_id": "s1"]))
        let reachedIdle = await h.waitForIdle()
        XCTAssertTrue(reachedIdle)
    }

    func test_case03_sessionEndReturnsToIdle() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s1", "cwd": "/proj"]))
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)
        try h.runHook("on-sessionend", payload: payload(["session_id": "s1"]))
        let reachedIdle = await h.waitForIdle()
        XCTAssertTrue(reachedIdle)
    }

    func test_case04_twoSessionsStopFirstStaysRunning() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "a", "cwd": "/A"]))
        try h.runHook("on-sessionstart", payload: payload(["session_id": "b", "cwd": "/B"]))
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)
        // Wait for both files to land in the store.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, h.store.sessions.count < 2 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(Set(h.store.sessions.map(\.sessionID)), ["a", "b"])

        try h.runHook("on-stop", payload: payload(["session_id": "a"]))
        let d2 = Date().addingTimeInterval(2)
        while Date() < d2, h.store.sessions.count > 1 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(h.store.statusCounts.total > 0)
        XCTAssertEqual(h.store.sessions.map(\.sessionID), ["b"])
    }

    func test_case05_pretoolMapsKnownTools() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s", "cwd": "/p"]))
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)

        let cases: [(tool: String, input: [String: Any], expectedTarget: String)] = [
            ("Bash", ["command": "npm test"], "npm test"),
            ("Edit", ["file_path": "main.swift"], "main.swift"),
            ("Read", ["file_path": "README.md"], "README.md"),
            ("Grep", ["pattern": "TODO"], "TODO"),
            ("WebFetch", ["url": "https://example.com"], "https://example.com"),
        ]

        for c in cases {
            try h.runHook("on-pretool", payload: payload([
                "session_id": "s",
                "tool_name": c.tool,
                "tool_input": c.input,
            ]))
            await waitForAction(h, tool: c.tool, target: c.expectedTarget)
            XCTAssertEqual(h.store.sessions.first?.currentAction?.tool, c.tool)
            XCTAssertEqual(h.store.sessions.first?.currentAction?.target, c.expectedTarget)
        }
    }

    func test_case06_pretoolUnknownToolKeepsNameAndEmptyTarget() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s", "cwd": "/p"]))
        let reachedRunning = await h.waitForRunning()
        XCTAssertTrue(reachedRunning)
        try h.runHook("on-pretool", payload: payload([
            "session_id": "s", "tool_name": "Mystery", "tool_input": [:],
        ]))
        await waitForAction(h, tool: "Mystery", target: "")
        XCTAssertEqual(h.store.sessions.first?.currentAction?.tool, "Mystery")
        XCTAssertEqual(h.store.sessions.first?.currentAction?.target, "")
    }
}

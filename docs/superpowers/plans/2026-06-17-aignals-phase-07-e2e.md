# Phase 07 — End-to-End Integration

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Implement the 14-case E2E suite from spec §9.4. This is the protocol-level acceptance gate.

**Depends on:** Phases 1–6.

**Spec sections:** §9.4 (the 14 cases), §9.2 (InstallHooks integration tests).

---

### Task 7.1: Test harness

**Files:**
- Create: `Tests/AignalsE2ETests/Helpers/Harness.swift`

- [ ] **Step 1: Write**

```swift
import Foundation
@testable import AignalsCore

@MainActor
final class Harness {
    let paths: Paths
    let store: SessionStore
    let watcher: FSEventsWatcher
    let sweeper: PIDSweeper
    let hookBinary: URL

    init(liveness: PIDLiveness = SystemPIDLiveness()) throws {
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-e2e-\(UUID().uuidString)", isDirectory: true)
        self.paths = Paths(environment: ["AIGNALS_HOME": tempBase.path])
        try paths.ensureDirectories()

        self.store = SessionStore()
        self.watcher = FSEventsWatcher(directory: paths.sessionsDirectory, store: store)
        self.sweeper = PIDSweeper(
            sessionsDirectory: paths.sessionsDirectory,
            store: store,
            liveness: liveness
        )
        self.sweeper.interval = 0.5    // fast for tests
        self.sweeper.staleAfter = 1.0  // tests can simulate "stale"

        // Locate the bundled CLI relative to repo root.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Helpers
            .deletingLastPathComponent() // AignalsE2ETests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo
        self.hookBinary = repoRoot.appendingPathComponent("CLI/aignals-hook/aignals-hook")

        watcher.start()
        sweeper.start()
    }

    /// Call from test tearDown — avoids `deinit` racing with @MainActor cleanup.
    func cleanup() {
        watcher.stop()
        sweeper.stop()
        try? FileManager.default.removeItem(at: paths.home)
    }

    @discardableResult
    func runHook(_ subcommand: String, payload: String) throws -> Int32 {
        let p = Process()
        // Invoke the binary directly so paths with spaces don't need shell quoting.
        p.executableURL = hookBinary
        p.arguments = [subcommand]
        var env = ProcessInfo.processInfo.environment
        env["AIGNALS_HOME"] = paths.home.path
        p.environment = env

        let pipe = Pipe()
        p.standardInput = pipe
        try p.run()
        pipe.fileHandleForWriting.write(Data(payload.utf8))
        try pipe.fileHandleForWriting.close()
        p.waitUntilExit()
        return p.terminationStatus
    }

    func waitForStatus(_ status: AggregateStatus, timeout: TimeInterval = 3.0) async -> Bool {
        if store.aggregateStatus == status { return true }
        let deadline = Date().addingTimeInterval(timeout)
        for await s in store.changes {
            if s == status { return true }
            if Date() > deadline { return false }
        }
        return false
    }
}
```

- [ ] **Step 2: Commit (no tests yet)**

```bash
git add Tests/AignalsE2ETests/Helpers
git commit -m "phase-07: add E2E test harness"
```

---

### Task 7.2: Cases 1–6 (happy-path lifecycle + tool mappings)

**Files:**
- Create: `Tests/AignalsE2ETests/LifecycleE2ETests.swift`

- [ ] **Step 1: Write**

```swift
import XCTest
@testable import AignalsCore

@MainActor
final class LifecycleE2ETests: XCTestCase {
    private var harnesses: [Harness] = []

    override func tearDown() async throws {
        await MainActor.run {
            for h in harnesses { h.cleanup() }
            harnesses.removeAll()
        }
    }

    private func makeHarness(liveness: PIDLiveness = SystemPIDLiveness()) throws -> Harness {
        let h = try makeHarness(liveness: liveness)
        harnesses.append(h)
        return h
    }

    private func payload(_ kvs: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: kvs)
        return String(decoding: data, as: UTF8.self)
    }

    func test_case01_sessionstartFlipsToRunning() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s1", "cwd": "/proj"]))
        XCTAssertTrue(await h.waitForStatus(.running))
        XCTAssertEqual(h.store.sessions.map(\.sessionID), ["s1"])
    }

    func test_case02_stopReturnsToIdle() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s1", "cwd": "/proj"]))
        _ = await h.waitForStatus(.running)
        try h.runHook("on-stop", payload: payload(["session_id": "s1"]))
        XCTAssertTrue(await h.waitForStatus(.idle))
    }

    func test_case03_sessionEndReturnsToIdle() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s1", "cwd": "/proj"]))
        _ = await h.waitForStatus(.running)
        try h.runHook("on-sessionend", payload: payload(["session_id": "s1"]))
        XCTAssertTrue(await h.waitForStatus(.idle))
    }

    func test_case04_twoSessionsStopFirstStaysRunning() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "a", "cwd": "/A"]))
        try h.runHook("on-sessionstart", payload: payload(["session_id": "b", "cwd": "/B"]))
        _ = await h.waitForStatus(.running)
        XCTAssertEqual(Set(h.store.sessions.map(\.sessionID)), ["a", "b"])

        try h.runHook("on-stop", payload: payload(["session_id": "a"]))
        // wait for store to reflect the removal
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(h.store.aggregateStatus, .running)
        XCTAssertEqual(h.store.sessions.map(\.sessionID), ["b"])
    }

    func test_case05_pretoolMapsKnownTools() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s", "cwd": "/p"]))
        _ = await h.waitForStatus(.running)

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
            // poll for current_action change
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if h.store.sessions.first?.currentAction?.tool == c.tool,
                   h.store.sessions.first?.currentAction?.target == c.expectedTarget {
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertEqual(h.store.sessions.first?.currentAction?.tool, c.tool)
            XCTAssertEqual(h.store.sessions.first?.currentAction?.target, c.expectedTarget)
        }
    }

    func test_case06_pretoolUnknownToolKeepsNameAndEmptyTarget() async throws {
        let h = try makeHarness()
        try h.runHook("on-sessionstart", payload: payload(["session_id": "s", "cwd": "/p"]))
        _ = await h.waitForStatus(.running)
        try h.runHook("on-pretool", payload: payload([
            "session_id": "s", "tool_name": "Mystery", "tool_input": [:],
        ]))
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if h.store.sessions.first?.currentAction?.tool == "Mystery" { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(h.store.sessions.first?.currentAction?.tool, "Mystery")
        XCTAssertEqual(h.store.sessions.first?.currentAction?.target, "")
    }
}
```

- [ ] **Step 2: Run**

```bash
swift test --filter LifecycleE2ETests
```

Expected: all 6 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/AignalsE2ETests/LifecycleE2ETests.swift
git commit -m "phase-07: E2E cases 1-6 (lifecycle + tool mapping)"
```

---

### Task 7.3: Cases 7–12 (orphans, schema rejection, atomicity, FS errors)

**Files:**
- Create: `Tests/AignalsE2ETests/ResilienceE2ETests.swift`

- [ ] **Step 1: Write**

```swift
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
        await MainActor.run {
            for h in harnesses { h.cleanup() }
            harnesses.removeAll()
        }
    }

    private func makeHarness(liveness: PIDLiveness = SystemPIDLiveness()) throws -> Harness {
        let h = try Harness(liveness: liveness)
        harnesses.append(h)
        return h
    }

    func test_case07_deadPidRemovedBySweep() async throws {
        let h = try makeHarness(liveness: ScriptedLiveness(aliveSet: []))
        // Write a file directly with a pid that won't match (since liveness is empty, all "dead")
        let file = h.paths.sessionFile(id: "orph")
        let json = """
        {"schema_version":1,"session_id":"orph","tool":"t","pid":99999,"project_name":"p","started_at":"2026-06-16T14:00:00Z"}
        """
        try Data(json.utf8).write(to: file)
        h.store.loadFromDisk(path: file)
        XCTAssertEqual(h.store.aggregateStatus, .running)

        try await Task.sleep(nanoseconds: 800_000_000) // > one sweep tick (0.5s)
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
        // Force mtime way in the past (sweeper.staleAfter = 1s, so 5s old = stale).
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
        h.store.loadFromDisk(path: file)

        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(h.store.aggregateStatus, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_case09_malformedJsonIgnored() async throws {
        let h = try makeHarness()
        let file = h.paths.sessionFile(id: "bad")
        try Data("not json".utf8).write(to: file)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(h.store.sessions.isEmpty)
    }

    func test_case10_unknownSchemaVersionIgnored() async throws {
        let h = try makeHarness()
        let file = h.paths.sessionFile(id: "v2")
        try Data("{\"schema_version\":2,\"session_id\":\"v2\",\"tool\":\"t\",\"project_name\":\"p\",\"started_at\":\"2026-06-16T14:00:00Z\"}".utf8).write(to: file)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(h.store.sessions.isEmpty)
    }

    func test_case11_atomicRenameProducesOneEvent() async throws {
        let h = try makeHarness()
        // Producer writes via tmp+mv (this is what aignals-hook does):
        try h.runHook("on-sessionstart", payload: "{\"session_id\":\"atom\",\"cwd\":\"/p\"}")
        XCTAssertTrue(await h.waitForStatus(.running))
        // After running, no .tmp files should remain in the dir.
        let entries = try FileManager.default.contentsOfDirectory(atPath: h.paths.sessionsDirectory.path)
        XCTAssertFalse(entries.contains(where: { $0.hasSuffix(".tmp") }))
    }

    func test_case12_unreadableDirEntersAndRecoversFromError() async throws {
        let h = try makeHarness()
        // chmod 000 the dir
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: h.paths.sessionsDirectory.path)
        XCTAssertTrue(await h.waitForStatus(.error))

        // restore
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: h.paths.sessionsDirectory.path)
        XCTAssertTrue(await h.waitForStatus(.idle))
    }
}
```

- [ ] **Step 2: Run**

```bash
swift test --filter ResilienceE2ETests
```

Expected: all 6 pass. Case 12 may be slightly flaky if sweep ticks land exactly on the chmod; if so, bump `staleAfter` / sweep interval slightly.

- [ ] **Step 3: Commit**

```bash
git add Tests/AignalsE2ETests/ResilienceE2ETests.swift
git commit -m "phase-07: E2E cases 7-12 (orphans, schema, atomicity, FS errors)"
```

---

### Task 7.4: Cases 13–14 (install merge, jq missing)

**Files:**
- Create: `Tests/AignalsE2ETests/InstallHooksE2ETests.swift`
- Note: `InstallHooksCommand` itself lands in Phase 9. These two cases will fail (or be skipped) until then. Stub them now so the test list is complete and tag them with `XCTSkipUnless` keyed off an env var.

- [ ] **Step 1: Write skipping-by-default**

```swift
import XCTest
@testable import AignalsCore

@MainActor
final class InstallHooksE2ETests: XCTestCase {
    override func setUpWithError() throws {
        // Phase 9 will flip this on. Skip until then so CI stays green during partial builds.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AIGNALS_PHASE9_DONE"] == "1",
                          "InstallHooks tests are gated until phase-09 ships")
    }

    func test_case13_installHooksMergeIdempotent() throws {
        // The real implementation lands in phase-09 and unskips this test by setting
        // AIGNALS_PHASE9_DONE=1 in the CI workflow once that phase is complete.
        XCTFail("phase-09 must implement InstallHooksCommand and flip the gate env var")
    }

    func test_case14_hookExitsZeroWhenJqMissing() throws {
        // Run aignals-hook with a stripped PATH so jq is unavailable.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-jq-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let hookBinary = repoRoot.appendingPathComponent("CLI/aignals-hook/aignals-hook")

        let emptyPathDir = tmp.appendingPathComponent("nojq")
        try FileManager.default.createDirectory(at: emptyPathDir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "echo '{\"session_id\":\"x\"}' | \"\(hookBinary.path)\" on-sessionstart"]
        // Truly empty PATH (only the dummy dir, contains nothing) so jq is unfindable
        // even if the runner has it in /opt/homebrew/bin or /usr/local/bin.
        p.environment = ["PATH": emptyPathDir.path, "AIGNALS_HOME": tmp.path, "HOME": NSHomeDirectory()]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }
}
```

Case 14 may pass even today if `jq` is installed at `/usr/bin/jq` on the runner. Adjust: if the test machine has system-jq, replace `/usr/bin:/bin` with a temp empty PATH (`p.environment = ["PATH": ""]`), which still allows `bash` because we exec it absolutely.

- [ ] **Step 2: Run (expect skip for case 13, pass for case 14)**

```bash
swift test --filter InstallHooksE2ETests
```

- [ ] **Step 3: Commit**

```bash
git add Tests/AignalsE2ETests/InstallHooksE2ETests.swift
git commit -m "phase-07: E2E cases 13-14 (install gate + jq-missing)"
```

---

### Acceptance for Phase 7

- All 12 ready-to-run E2E tests (cases 1–12 + case 14) pass.
- Case 13 is intentionally `XCTSkip`'d, flipped on by Phase 9.

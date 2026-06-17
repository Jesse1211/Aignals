# Phase 05 — `PIDSweeper`

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Every 5 seconds, walk `sessions/` and remove any file whose pid is dead or whose mtime is > 24 h. Also flag FS-access errors back to the store.

**Depends on:** Phase 1 (`Paths`), Phase 3 (`SessionStore`).

**Spec sections:** §4 orphan handling, §6 PIDSweeper responsibility (incl. FS access check), §8 error handling.

---

### Task 5.1: PID liveness abstraction

**Files:**
- Create: `Sources/AignalsCore/PIDLiveness.swift`
- Create: `Tests/AignalsCoreTests/PIDLivenessTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import AignalsCore

final class PIDLivenessTests: XCTestCase {
    func testCurrentProcessIsAlive() {
        let liveness = SystemPIDLiveness()
        XCTAssertEqual(liveness.state(of: pid_t(getpid())), .alive)
    }

    func testHighlyUnlikelyPIDIsDead() {
        // pid 1 (launchd) is alive on macOS, so use a synthetic huge value
        let liveness = SystemPIDLiveness()
        XCTAssertEqual(liveness.state(of: 999_999), .dead)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import Darwin

public enum PIDState: Equatable, Sendable {
    case alive
    case dead
    case unknown
}

public protocol PIDLiveness: Sendable {
    func state(of pid: pid_t) -> PIDState
}

public struct SystemPIDLiveness: PIDLiveness {
    public init() {}
    public func state(of pid: pid_t) -> PIDState {
        guard pid > 0 else { return .unknown }
        let r = kill(pid, 0)
        if r == 0 { return .alive }
        switch errno {
        case ESRCH: return .dead
        case EPERM: return .alive   // exists but not ours
        default:    return .unknown
        }
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter PIDLivenessTests
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/AignalsCore/PIDLiveness.swift Tests/AignalsCoreTests/PIDLivenessTests.swift
git commit -m "phase-05: add PIDLiveness protocol + SystemPIDLiveness"
```

---

### Task 5.2: Failing tests for `PIDSweeper`

**Files:**
- Create: `Tests/AignalsCoreTests/PIDSweeperTests.swift`

- [ ] **Step 1: Write**

```swift
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
          "schema_version": 1, "session_id": "\(id)", "tool": "t",
          \(pidJSON)
          "project_name": "p", "started_at": "2026-06-16T14:00:00Z"
        }
        """
        let url = dir.appendingPathComponent("\(id).json")
        try Data(json.utf8).write(to: url)
        if let m = mtime {
            try FileManager.default.setAttributes([.modificationDate: m], ofItemAtPath: url.path)
        }
    }

    func testDeadPIDRemovesFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(id: "a", pid: 1234, in: dir)

        let store = SessionStore()
        store.loadFromDisk(path: dir.appendingPathComponent("a.json"))
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
        store.loadFromDisk(path: dir.appendingPathComponent("a.json"))

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
        store.loadFromDisk(path: dir.appendingPathComponent("fresh.json"))
        store.loadFromDisk(path: dir.appendingPathComponent("stale.json"))

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
```

- [ ] **Step 2: Verify fail**

```bash
swift test --filter PIDSweeperTests
```

Expected: PIDSweeper undefined.

---

### Task 5.3: Implement `PIDSweeper`

**Files:**
- Create: `Sources/AignalsCore/PIDSweeper.swift`

- [ ] **Step 1: Write**

```swift
import Foundation

@MainActor
public final class PIDSweeper {
    public let sessionsDirectory: URL
    public let store: SessionStore
    public let liveness: PIDLiveness
    public var staleAfter: TimeInterval = 24 * 3600
    public var interval: TimeInterval = 5

    private var timer: Timer?

    public init(sessionsDirectory: URL, store: SessionStore, liveness: PIDLiveness = SystemPIDLiveness()) {
        self.sessionsDirectory = sessionsDirectory
        self.store = store
        self.liveness = liveness
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepOnce() }
        }
        sweepOnce()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func sweepOnce() {
        let fm = FileManager.default

        // FS access check
        guard let entries = try? fm.contentsOfDirectory(atPath: sessionsDirectory.path) else {
            store.setFSAccessError(true)
            return
        }
        store.setFSAccessError(false)

        let now = Date()
        for name in entries where name.hasSuffix(".json") && !name.hasSuffix(".json.tmp") {
            let path = sessionsDirectory.appendingPathComponent(name)
            sweepFile(at: path, now: now)
        }
    }

    private func sweepFile(at path: URL, now: Date) {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: path) else { return }

        let mtime = (try? fm.attributesOfItem(atPath: path.path)[.modificationDate] as? Date) ?? now
        let staleByMtime = now.timeIntervalSince(mtime) > staleAfter

        let session = try? Session.decode(from: data)
        let pid = session?.pid

        let shouldDelete: Bool
        switch (pid, staleByMtime) {
        case (let p?, _):
            switch liveness.state(of: p) {
            case .dead: shouldDelete = true
            case .alive, .unknown: shouldDelete = staleByMtime
            }
        case (nil, let stale):
            shouldDelete = stale
        }

        if shouldDelete {
            try? fm.removeItem(at: path)
            let id = (path.lastPathComponent as NSString).deletingPathExtension
            store.remove(id: id)
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter PIDSweeperTests
```

Expected: all 4 pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/AignalsCore/PIDSweeper.swift Tests/AignalsCoreTests/PIDSweeperTests.swift
git commit -m "phase-05: add PIDSweeper (pid liveness + mtime backstop + FS-access check)"
```

---

### Acceptance for Phase 5

- All `PIDSweeperTests` pass.
- Sweeper uses pid first, mtime second.
- Unreadable directory → store error state; recovery restores idle/running.
- `sweepOnce()` directly callable from tests; `start()` schedules a 5 s timer.

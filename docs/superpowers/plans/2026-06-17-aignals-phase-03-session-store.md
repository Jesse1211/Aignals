# Phase 03 — `SessionStore`

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** A `@MainActor` `@Observable` source of truth holding `[Session]` and exposing `aggregateStatus`, plus async state-change notifications for tests.

**Depends on:** Phase 2 (`Session`).

**Spec sections:** §6 (responsibilities, threading), §7 (aggregate-status rule).

---

### Task 3.1: Failing tests

**Files:**
- Create: `Tests/AignalsCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Write tests**

```swift
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
```

- [ ] **Step 2: Verify failure**

```bash
swift test --filter SessionStoreTests
```

Expected: SessionStore doesn't exist → fail.

---

### Task 3.2: Implement `AggregateStatus`

**Files:**
- Create: `Sources/AignalsCore/AggregateStatus.swift`

- [ ] **Step 1: Write**

```swift
import Foundation

public enum AggregateStatus: Equatable, Sendable {
    case idle
    case running
    case error
}
```

- [ ] **Step 2: Commit (no test changes yet, type only)**

```bash
git add Sources/AignalsCore/AggregateStatus.swift
git commit -m "phase-03: add AggregateStatus enum"
```

---

### Task 3.3: Implement `SessionStore`

**Files:**
- Create: `Sources/AignalsCore/SessionStore.swift`

- [ ] **Step 1: Write**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class SessionStore {
    public private(set) var sessions: [Session] = []
    public private(set) var hasFSAccessError: Bool = false

    public var aggregateStatus: AggregateStatus {
        if hasFSAccessError { return .error }
        return sessions.isEmpty ? .idle : .running
    }

    // Async sequence for tests / FSEventsWatcher integration tests.
    public let changes: AsyncStream<AggregateStatus>
    private let continuation: AsyncStream<AggregateStatus>.Continuation

    public init() {
        var cont: AsyncStream<AggregateStatus>.Continuation!
        self.changes = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func upsert(_ session: Session) {
        if let idx = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
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
        continuation.yield(aggregateStatus)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SessionStoreTests
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/AignalsCore/SessionStore.swift Tests/AignalsCoreTests/SessionStoreTests.swift
git commit -m "phase-03: add SessionStore (@MainActor @Observable, async changes stream)"
```

---

### Acceptance for Phase 3

- All `SessionStoreTests` green.
- `aggregateStatus` follows: `.error > .running > .idle`.
- `sessions` always sorted by `startedAt` ascending.
- `changes` async stream yields after every mutation.

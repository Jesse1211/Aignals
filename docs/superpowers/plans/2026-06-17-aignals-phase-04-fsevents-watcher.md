# Phase 04 — `FSEventsWatcher`

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Watch `~/.aignals/sessions/` and translate create/modify/delete events into `SessionStore.upsert(path:)` / `.remove(id:)` calls.

**Depends on:** Phase 1 (`Paths`), Phase 2 (`Session`), Phase 3 (`SessionStore`).

**Spec sections:** §6 (FSEventsWatcher responsibilities), §9.2 (integration tests).

---

### Task 4.1: Extend `SessionStore` with file-aware helpers

**Files:**
- Modify: `Sources/AignalsCore/SessionStore.swift`
- Modify: `Tests/AignalsCoreTests/SessionStoreTests.swift`

The watcher gets paths; the store does the decode. Keeps decode + state in one place.

- [ ] **Step 1: Failing test for `loadFromDisk(path:)`**

Append to `SessionStoreTests`:

```swift
extension SessionStoreTests {
    func testLoadFromDiskUpsertsValidFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let json = """
        {
          "schema_version": 1, "session_id": "a", "tool": "t",
          "project_name": "p", "started_at": "2026-06-16T14:00:00Z"
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
```

- [ ] **Step 2: Add `loadFromDisk` to `SessionStore`**

```swift
import os

extension SessionStore {
    private static let log = Logger(subsystem: "com.aignals.Aignals", category: "SessionStore")

    public func loadFromDisk(path: URL) {
        guard let data = try? Data(contentsOf: path) else { return }
        do {
            let s = try Session.decode(from: data)
            upsert(s)
        } catch {
            Self.log.debug("skip \(path.lastPathComponent): \(String(describing: error))")
        }
    }

    public func removeBy(filename: String) {
        let id = (filename as NSString).deletingPathExtension
        remove(id: id)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter SessionStoreTests
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/AignalsCore/SessionStore.swift Tests/AignalsCoreTests/SessionStoreTests.swift
git commit -m "phase-04: add SessionStore.loadFromDisk + removeBy(filename:)"
```

---

### Task 4.2: Failing integration test for `FSEventsWatcher`

**Files:**
- Create: `Tests/AignalsCoreTests/FSEventsWatcherTests.swift`

- [ ] **Step 1: Write**

```swift
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
        await waitFor(store, status: .running, timeout: 2.0)
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
        await waitFor(store, status: .running, timeout: 2.0)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.json"))
        await waitFor(store, status: .idle, timeout: 2.0)
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
          "schema_version": 1, "session_id": "\(id)", "tool": "t",
          "project_name": "p", "started_at": "2026-06-16T14:00:00Z"
        }
        """
        let final = dir.appendingPathComponent("\(id).json")
        let tmp = dir.appendingPathComponent("\(id).json.tmp")
        try Data(json.utf8).write(to: tmp)
        try FileManager.default.moveItem(at: tmp, to: final)
    }

    private func waitFor(_ store: SessionStore, status: AggregateStatus, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        for await s in store.changes {
            if s == status { return }
            if Date() > deadline { break }
        }
        XCTFail("Timed out waiting for status \(status); current = \(store.aggregateStatus)")
    }
}
```

- [ ] **Step 2: Verify fail**

```bash
swift test --filter FSEventsWatcherTests
```

Expected: type doesn't exist.

---

### Task 4.3: Implement `FSEventsWatcher`

**Files:**
- Create: `Sources/AignalsCore/FSEventsWatcher.swift`

- [ ] **Step 1: Write**

```swift
import Foundation
import CoreServices

public final class FSEventsWatcher {
    private let directory: URL
    private let store: SessionStore
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.aignals.fsevents", qos: .utility)

    public init(directory: URL, store: SessionStore) {
        self.directory = directory
        self.store = store
    }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let paths = [directory.path] as CFArray
        let callback: FSEventStreamCallback = { _, ctx, numEvents, eventPaths, _, _ in
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            for i in 0..<numEvents {
                watcher.handle(path: paths[i])
            }
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        self.stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        self.stream = nil
    }

    deinit { stop() }

    private func handle(path: String) {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard name.hasSuffix(".json"), !name.hasSuffix(".json.tmp") else { return }

        let exists = FileManager.default.fileExists(atPath: path)
        Task { @MainActor in
            if exists {
                store.loadFromDisk(path: url)
            } else {
                store.removeBy(filename: name)
            }
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter FSEventsWatcherTests
```

Expected: all 3 pass. If flaky, bump timeouts to 3.0s — FSEvents can lag on a busy machine.

- [ ] **Step 3: Commit**

```bash
git add Sources/AignalsCore/FSEventsWatcher.swift Tests/AignalsCoreTests/FSEventsWatcherTests.swift
git commit -m "phase-04: add FSEventsWatcher with create/delete handling"
```

---

### Acceptance for Phase 4

- All `FSEventsWatcherTests` green.
- Watcher ignores `.tmp` files and non-JSON files.
- Create → `upsert`, delete → `removeBy(filename:)`.

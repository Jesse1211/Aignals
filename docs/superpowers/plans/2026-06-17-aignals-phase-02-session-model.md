# Phase 02 — `Session` Model

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Codable struct mirroring the spec §4 schema, with safe decoding that ignores unknown versions and missing optional fields.

**Spec sections:** §4 (schema fields), §8 (error handling — skip malformed / unknown version).

---

### Task 2.1: Failing tests for `Session` decode

**Files:**
- Create: `Tests/AignalsCoreTests/SessionTests.swift`
- Create: `Tests/AignalsCoreTests/Fixtures/`

- [ ] **Step 1: Add fixtures directory and test file**

Create `Tests/AignalsCoreTests/Fixtures/session_good.json`:

```json
{
  "schema_version": 1,
  "session_id": "abc-123",
  "tool": "claude-code",
  "pid": 48217,
  "project_name": "Aignals",
  "cwd": "/Users/jesseliu/Desktop/Chore/Aignals",
  "started_at": "2026-06-16T14:52:08Z",
  "current_action": {
    "tool": "Edit",
    "target": "main.swift",
    "updated_at": "2026-06-16T14:54:31Z"
  }
}
```

Create `Tests/AignalsCoreTests/Fixtures/session_no_action.json`:

```json
{
  "schema_version": 1,
  "session_id": "abc-456",
  "tool": "claude-code",
  "project_name": "dotfiles",
  "started_at": "2026-06-16T14:00:00Z"
}
```

Create `Tests/AignalsCoreTests/Fixtures/session_v2.json`:

```json
{ "schema_version": 2, "session_id": "x", "tool": "x", "project_name": "x", "started_at": "2026-06-16T14:00:00Z" }
```

Create `Tests/AignalsCoreTests/Fixtures/session_missing_required.json`:

```json
{ "schema_version": 1, "tool": "x", "project_name": "x", "started_at": "2026-06-16T14:00:00Z" }
```

Add fixtures to the test target. Edit `Package.swift`, change the `AignalsCoreTests` target to:

```swift
.testTarget(
    name: "AignalsCoreTests",
    dependencies: ["AignalsCore"],
    path: "Tests/AignalsCoreTests",
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 2: Write the tests**

Create `Tests/AignalsCoreTests/SessionTests.swift`:

```swift
import XCTest
@testable import AignalsCore

final class SessionTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }

    func testDecodeGoodSession() throws {
        let data = try loadFixture("session_good")
        let session = try Session.decode(from: data)
        XCTAssertEqual(session.sessionID, "abc-123")
        XCTAssertEqual(session.tool, "claude-code")
        XCTAssertEqual(session.pid, 48217)
        XCTAssertEqual(session.projectName, "Aignals")
        XCTAssertEqual(session.cwd, "/Users/jesseliu/Desktop/Chore/Aignals")
        XCTAssertEqual(session.currentAction?.tool, "Edit")
        XCTAssertEqual(session.currentAction?.target, "main.swift")
    }

    func testDecodeSessionWithoutAction() throws {
        let data = try loadFixture("session_no_action")
        let session = try Session.decode(from: data)
        XCTAssertEqual(session.sessionID, "abc-456")
        XCTAssertNil(session.currentAction)
        XCTAssertNil(session.pid)
        XCTAssertNil(session.cwd)
    }

    func testDecodeUnknownVersionReturnsNil() throws {
        let data = try loadFixture("session_v2")
        XCTAssertNil(try? Session.decode(from: data))
    }

    func testDecodeMissingRequiredFieldThrows() throws {
        let data = try loadFixture("session_missing_required")
        XCTAssertThrowsError(try Session.decode(from: data))
    }

    func testDecodeIgnoresUnknownExtraFields() throws {
        let raw = """
        {
          "schema_version": 1,
          "session_id": "a", "tool": "t", "project_name": "p",
          "started_at": "2026-06-16T14:00:00Z",
          "unknown_field": "ignored"
        }
        """
        let session = try Session.decode(from: Data(raw.utf8))
        XCTAssertEqual(session.sessionID, "a")
    }
}
```

- [ ] **Step 3: Run, confirm fail**

```bash
swift test --filter SessionTests
```

Expected: compilation fails — `Session` does not exist.

---

### Task 2.2: Implement `Session`

**Files:**
- Create: `Sources/AignalsCore/Session.swift`

- [ ] **Step 1: Write `Session.swift`**

```swift
import Foundation

public struct Session: Equatable, Sendable {
    public let sessionID: String
    public let tool: String
    public let pid: Int32?
    public let projectName: String
    public let cwd: String?
    public let startedAt: Date
    public let currentAction: CurrentAction?

    public struct CurrentAction: Equatable, Sendable {
        public let tool: String
        public let target: String
        public let updatedAt: Date
    }

    public enum DecodeError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
        case missingField(String)
        case invalidDate(String)
    }

    public init(
        sessionID: String,
        tool: String,
        pid: Int32?,
        projectName: String,
        cwd: String?,
        startedAt: Date,
        currentAction: CurrentAction?
    ) {
        self.sessionID = sessionID
        self.tool = tool
        self.pid = pid
        self.projectName = projectName
        self.cwd = cwd
        self.startedAt = startedAt
        self.currentAction = currentAction
    }

    public static func decode(from data: Data) throws -> Session {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw DecodeError.missingField("root")
        }

        let version = dict["schema_version"] as? Int ?? 0
        guard version == 1 else { throw DecodeError.unsupportedSchemaVersion(version) }

        func required<T>(_ key: String) throws -> T {
            guard let v = dict[key] as? T else { throw DecodeError.missingField(key) }
            return v
        }

        let sessionID: String = try required("session_id")
        let tool: String = try required("tool")
        let projectName: String = try required("project_name")
        let startedAtStr: String = try required("started_at")
        guard let startedAt = isoDate(startedAtStr) else {
            throw DecodeError.invalidDate(startedAtStr)
        }

        let pid = (dict["pid"] as? Int).map(Int32.init) ?? (dict["pid"] as? Int32)
        let cwd = dict["cwd"] as? String

        let currentAction: CurrentAction?
        if let actionDict = dict["current_action"] as? [String: Any] {
            guard
                let aTool = actionDict["tool"] as? String,
                let aTarget = actionDict["target"] as? String,
                let aUpdatedStr = actionDict["updated_at"] as? String,
                let aUpdated = isoDate(aUpdatedStr)
            else { throw DecodeError.missingField("current_action") }
            currentAction = CurrentAction(tool: aTool, target: aTarget, updatedAt: aUpdated)
        } else {
            currentAction = nil
        }

        return Session(
            sessionID: sessionID,
            tool: tool,
            pid: pid,
            projectName: projectName,
            cwd: cwd,
            startedAt: startedAt,
            currentAction: currentAction
        )
    }
}

private let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func isoDate(_ s: String) -> Date? {
    iso.date(from: s)
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SessionTests
```

Expected: all 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/AignalsCore/Session.swift Tests/AignalsCoreTests/SessionTests.swift Tests/AignalsCoreTests/Fixtures Package.swift
git commit -m "phase-02: add Session model with safe decode (version + required fields)"
```

---

### Acceptance for Phase 2

- `SessionTests` all green.
- `Session.decode(from:)` throws on missing required, throws on `schema_version != 1`, ignores extra fields.
- `currentAction` is optional and decodes correctly when present.

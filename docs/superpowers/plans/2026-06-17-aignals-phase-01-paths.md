# Phase 01 — `Paths` Service

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** A single typed source of truth for every filesystem path Aignals uses, with `AIGNALS_HOME` override for tests.

**Why:** Every later phase reads/writes under `~/.aignals/`. Centralising lets the E2E suite point everything at a temp dir.

**Spec sections:** §4 (directory layout), §6 (Paths module), §9.4 (test override via `AIGNALS_HOME`).

---

### Task 1.1: Write failing test

**Files:**
- Create: `Tests/AignalsCoreTests/PathsTests.swift`

- [ ] **Step 1: Test the four behaviours**

```swift
import XCTest
@testable import AignalsCore

final class PathsTests: XCTestCase {
    func testDefaultHomeIsDotAignalsInUserHome() {
        let paths = Paths(environment: [:])
        XCTAssertEqual(paths.home.path, NSHomeDirectory() + "/.aignals")
    }

    func testHomeOverrideViaEnvironment() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(paths.home.path, "/tmp/test-aignals")
    }

    func testSessionsDirectoryIsHomePlusSessions() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(paths.sessionsDirectory.path, "/tmp/test-aignals/sessions")
    }

    func testConfigFileIsHomePlusConfigJSON() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(paths.configFile.path, "/tmp/test-aignals/config.json")
    }

    func testSessionFilePath() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(
            paths.sessionFile(id: "abc-123").path,
            "/tmp/test-aignals/sessions/abc-123.json"
        )
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
swift test --filter PathsTests
```

Expected: fail with "no type named 'Paths'".

---

### Task 1.2: Implement `Paths`

**Files:**
- Create: `Sources/AignalsCore/Paths.swift`
- Delete: `Sources/AignalsCore/Placeholder.swift`

- [ ] **Step 1: Write `Paths.swift`**

```swift
import Foundation

public struct Paths: Sendable {
    public let home: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let override = environment["AIGNALS_HOME"], !override.isEmpty {
            self.home = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".aignals", isDirectory: true)
        }
    }

    public var sessionsDirectory: URL {
        home.appendingPathComponent("sessions", isDirectory: true)
    }

    public var configFile: URL {
        home.appendingPathComponent("config.json")
    }

    public func sessionFile(id: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(id).json")
    }

    /// Ensure home and sessions dir exist with mode 0700. Idempotent.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [home, sessionsDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }
}
```

- [ ] **Step 2: Remove placeholder**

```bash
rm Sources/AignalsCore/Placeholder.swift
# Also drop the placeholder test reference if it referenced _AignalsCorePlaceholder:
```

Edit `Tests/AignalsCoreTests/PlaceholderTests.swift` → delete the file:

```bash
rm Tests/AignalsCoreTests/PlaceholderTests.swift
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter PathsTests
```

Expected: all 5 PathsTests pass.

- [ ] **Step 4: Run full suite to verify no regressions**

```bash
swift test
```

Expected: PathsTests pass; E2E placeholder still passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/Paths.swift Tests/AignalsCoreTests/PathsTests.swift
git rm Sources/AignalsCore/Placeholder.swift Tests/AignalsCoreTests/PlaceholderTests.swift
git commit -m "phase-01: add Paths service with AIGNALS_HOME override"
```

---

### Task 1.3: Test `ensureDirectories` against a temp dir

**Files:**
- Modify: `Tests/AignalsCoreTests/PathsTests.swift`

- [ ] **Step 1: Append failing test**

```swift
extension PathsTests {
    func testEnsureDirectoriesCreatesMissingPathsWithMode0700() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-paths-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let paths = Paths(environment: ["AIGNALS_HOME": temp.path])
        try paths.ensureDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.home.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.sessionsDirectory.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: paths.home.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(perms & 0o777, 0o700)
    }

    func testEnsureDirectoriesIsIdempotent() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-paths-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let paths = Paths(environment: ["AIGNALS_HOME": temp.path])
        try paths.ensureDirectories()
        try paths.ensureDirectories()  // should not throw
    }
}
```

- [ ] **Step 2: Run**

```bash
swift test --filter PathsTests
```

Expected: all PathsTests pass (implementation already covers this).

- [ ] **Step 3: Commit**

```bash
git add Tests/AignalsCoreTests/PathsTests.swift
git commit -m "phase-01: test Paths.ensureDirectories (0700 perms, idempotent)"
```

---

### Acceptance for Phase 1

- All `PathsTests` pass.
- `Sources/AignalsCore/Paths.swift` exposes `home`, `sessionsDirectory`, `configFile`, `sessionFile(id:)`, `ensureDirectories()`.
- `AIGNALS_HOME` env var redirects all paths.

# Work Stopwatch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track actual daily work time — Start/Stop/Resume/End with wall-clock recovery, a local-midnight cut, per-day segment logging, a Stat window, and a Feishu post on the day's first Start.

**Architecture:** A pure, injected-clock `StopwatchEngine` (state machine + wall-clock math + midnight cut) is the testable core. `StopwatchStateStore` persists the volatile running state; `WorklogStore` persists sealed history by local day; `WorktimeFormatter` renders durations. App-layer wiring in `AppViewModel` + a menubar region + a dedicated Stat `Window` drives them, reusing the existing 1-second tick and the Quote feature's `sendCurrentQuoteToFeishu()`.

**Tech Stack:** Swift 5.9, macOS 14+, SwiftUI (`MenuBarExtra` `.window`, dedicated `Window`), `XCTest`. Core via `swift test`; UI via the Xcode `App/Aignals` project.

## Global Constraints

- **Decoupling (hard):** stopwatch code MUST NOT reference session state/types. Only the 1-second UI *tick signal* is shared.
- **Depends on the Quote feature:** `AppViewModel.sendCurrentQuoteToFeishu()` (Quote plan Task 9.5) must already exist. Implement the Quote plan first.
- All error-prone time logic lives in `StopwatchEngine` behind an **injected `Date` + `Calendar`** — no bare `Date()` inside the engine.
- Data dir is `~/.aignals/`; persistence is atomic temp-file + `FileManager.replaceItemAt` (match `OverrideStore`). Corrupt/missing → safe default.
- Local date basis `YYYY-MM-DD` for the midnight rule and worklog keys (via the injected `Calendar`).
- `@Observable AppViewModel`: non-`@Observable` stores need a bumped `…Version` int so SwiftUI re-derives (match `overridesVersion`).
- New `Codable` types live in `Sources/AignalsCore`.
- JSON files carry a `version` field; new fields decode via `decodeIfPresent ?? default`.

---

### Task 1: `WorktimeFormatter`

**Files:**
- Create: `Sources/AignalsCore/WorktimeFormatter.swift`
- Test: `Tests/AignalsCoreTests/WorktimeFormatterTests.swift`

**Interfaces:**
- Produces: `public enum WorktimeFormatter { public static func clock(_ seconds: Int) -> String; public static func human(_ seconds: Int) -> String }`
  - `clock` → `HH:MM:SS` zero-padded (`0 → "00:00:00"`, `9900 → "02:45:00"`).
  - `human` → `"7h 30m"` / `"45m"` / `"0m"` (drops the hour part when 0h; minutes always shown).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class WorktimeFormatterTests: XCTestCase {
    func test_clock_pads_hms() {
        XCTAssertEqual(WorktimeFormatter.clock(0), "00:00:00")
        XCTAssertEqual(WorktimeFormatter.clock(9900), "02:45:00")   // 2h45m
        XCTAssertEqual(WorktimeFormatter.clock(59), "00:00:59")
        XCTAssertEqual(WorktimeFormatter.clock(3661), "01:01:01")
    }
    func test_human_drops_zero_hours() {
        XCTAssertEqual(WorktimeFormatter.human(0), "0m")
        XCTAssertEqual(WorktimeFormatter.human(2700), "45m")        // 45m
        XCTAssertEqual(WorktimeFormatter.human(9900), "2h 45m")     // 2h45m
        XCTAssertEqual(WorktimeFormatter.human(3600), "1h 0m")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter WorktimeFormatterTests`
Expected: FAIL — `cannot find 'WorktimeFormatter' in scope`.

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

/// Renders work durations. `clock` for the live HH:MM:SS display, `human` for
/// the Stat list ("2h 45m").
public enum WorktimeFormatter {
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    public static func human(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter WorktimeFormatterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/WorktimeFormatter.swift Tests/AignalsCoreTests/WorktimeFormatterTests.swift
git commit -m "feat(core): WorktimeFormatter (clock + human durations)"
```

---

### Task 2: `Paths` — stopwatch + worklog files

**Files:**
- Modify: `Sources/AignalsCore/Paths.swift`
- Test: `Tests/AignalsCoreTests/PathsTests.swift`

**Interfaces:**
- Produces: `public var stopwatchStateFile: URL` (→ `home/stopwatch-state.json`), `public var worklogFile: URL` (→ `home/worklog.json`).

- [ ] **Step 1: Write the failing test** (append to `PathsTests.swift`)

```swift
func test_stopwatch_and_worklog_paths() {
    let p = Paths(environment: ["AIGNALS_HOME": "/tmp/aignals-sw"])
    XCTAssertEqual(p.stopwatchStateFile.path, "/tmp/aignals-sw/stopwatch-state.json")
    XCTAssertEqual(p.worklogFile.path, "/tmp/aignals-sw/worklog.json")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PathsTests/test_stopwatch_and_worklog_paths`
Expected: FAIL — no member `stopwatchStateFile`.

- [ ] **Step 3: Minimal implementation** — add to `Paths.swift` after `quotesFile`:

```swift
    public var stopwatchStateFile: URL {
        home.appendingPathComponent("stopwatch-state.json")
    }

    public var worklogFile: URL {
        home.appendingPathComponent("worklog.json")
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PathsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/Paths.swift Tests/AignalsCoreTests/PathsTests.swift
git commit -m "feat(core): Paths.stopwatchStateFile + worklogFile"
```

---

### Task 3: Model types — `StopwatchState`, `WorkSegment`, `WorkDay`, `StopwatchSnapshot`

**Files:**
- Create: `Sources/AignalsCore/StopwatchModels.swift`
- Test: `Tests/AignalsCoreTests/StopwatchModelsTests.swift`

**Interfaces:**
- Produces:
```swift
public enum StopwatchPhase: String, Codable, Sendable { case idle, running, stopped }

/// Persisted volatile running state (stopwatch-state.json payload).
public struct StopwatchSnapshot: Codable, Equatable, Sendable {
    public var version: Int          // = 1
    public var phase: StopwatchPhase
    public var day: String?          // local YYYY-MM-DD the accumulation belongs to; nil when idle
    public var accumulatedSeconds: Int
    public var currentSegmentStart: Date?   // non-nil only when running
    public init(version: Int = 1, phase: StopwatchPhase = .idle, day: String? = nil,
                accumulatedSeconds: Int = 0, currentSegmentStart: Date? = nil)
    public static let idle = StopwatchSnapshot()
}

/// One sealed work span.
public struct WorkSegment: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let seconds: Int
    public init(start: Date, end: Date, seconds: Int)
}

/// A day's sealed segments + redundant total.
public struct WorkDay: Codable, Equatable, Sendable {
    public var totalSeconds: Int
    public var segments: [WorkSegment]
    public init(totalSeconds: Int = 0, segments: [WorkSegment] = [])
}
```

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AignalsCore

final class StopwatchModelsTests: XCTestCase {
    func test_snapshot_roundtrips_iso8601() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let snap = StopwatchSnapshot(phase: .running, day: "2026-07-01",
                                     accumulatedSeconds: 5400,
                                     currentSegmentStart: Date(timeIntervalSince1970: 0))
        let back = try dec.decode(StopwatchSnapshot.self, from: try enc.encode(snap))
        XCTAssertEqual(back, snap)
    }
    func test_idle_default() {
        XCTAssertEqual(StopwatchSnapshot.idle.phase, .idle)
        XCTAssertEqual(StopwatchSnapshot.idle.accumulatedSeconds, 0)
        XCTAssertNil(StopwatchSnapshot.idle.currentSegmentStart)
    }
    func test_workday_default_empty() {
        XCTAssertEqual(WorkDay().segments.count, 0)
        XCTAssertEqual(WorkDay().totalSeconds, 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter StopwatchModelsTests`
Expected: FAIL — `cannot find 'StopwatchSnapshot' in scope`.

- [ ] **Step 3: Minimal implementation** — write the four types exactly as in Interfaces above into `StopwatchModels.swift` (with `import Foundation`, full member initializers, and `public static let idle = StopwatchSnapshot()`).

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter StopwatchModelsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/StopwatchModels.swift Tests/AignalsCoreTests/StopwatchModelsTests.swift
git commit -m "feat(core): stopwatch model types (snapshot/segment/day)"
```

---

### Task 4: `StopwatchEngine` — pure state machine + midnight cut

**Files:**
- Create: `Sources/AignalsCore/StopwatchEngine.swift`
- Test: `Tests/AignalsCoreTests/StopwatchEngineTests.swift`

This is the heart. It is a pure value type: no I/O, no bare `Date()`. Every function takes `now: Date` and `calendar: Calendar`. It returns the next `StopwatchSnapshot` plus any `WorkSegment`s that must be sealed (each carries its own local-day key so the caller knows which worklog day to append to).

**Interfaces:**
- Produces:
```swift
/// A segment to seal, tagged with the local day it belongs to.
public struct SealedSegment: Equatable, Sendable {
    public let day: String            // local YYYY-MM-DD
    public let segment: WorkSegment
}

public struct StopwatchEngine {
    public init()

    /// Local day string for a date under the given calendar.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String

    /// Elapsed work seconds to DISPLAY for `snap` at `now` (accumulated + live
    /// segment when running; frozen accumulated otherwise).
    public func displaySeconds(_ snap: StopwatchSnapshot, now: Date) -> Int

    // Transitions. Each returns (next snapshot, sealed segments to persist).
    public func start(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment])
    public func stop(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment])
    public func resume(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment])
    public func end(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment])

    /// Called on launch + on the tick. If a running segment spans past local
    /// midnight, cut it at 23:59:59 of its start day (sealing only the start
    /// day; fully-spanned days produce nothing), and reset to stopped/0 for the
    /// current day. No-op otherwise.
    public func evaluate(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment])

    /// Whether this action is legal from the given phase (drives which buttons show).
    public static func canStart(_ p: StopwatchPhase) -> Bool   // idle
    public static func canStop(_ p: StopwatchPhase) -> Bool    // running
    public static func canResume(_ p: StopwatchPhase) -> Bool  // stopped
    public static func canEnd(_ p: StopwatchPhase) -> Bool     // running || stopped
}
```

Semantics to implement:
- `start`: only from idle → running; `day = dayKey(now)`, `accumulatedSeconds = 0`, `currentSegmentStart = now`. No sealed segments.
- `stop`: only from running → stopped; seal `WorkSegment(start: currentSegmentStart, end: now, seconds: now - start)` under `snap.day`; `accumulatedSeconds += seconds`; `currentSegmentStart = nil`.
- `resume`: only from stopped → running; `currentSegmentStart = now`. No seal.
- `end`: from running → seal current segment (like stop) then idle; from stopped → just idle. Result phase idle, `accumulatedSeconds = 0`, `day = nil`, `currentSegmentStart = nil`.
- `evaluate`: if `phase == running` and `dayKey(currentSegmentStart) != dayKey(now)` → cut: `cutEnd` = 23:59:59 local of the start day; seal `WorkSegment(start, cutEnd, cutEnd - start)` under `dayKey(currentSegmentStart)`; next = stopped **with accumulatedSeconds reset to 0** and `day = dayKey(now)`, `currentSegmentStart = nil`. Only the start day is sealed; spanned days get nothing. If not running or same day → return snap unchanged, no seals.
- Illegal transitions (e.g. `stop` from idle) → return snap unchanged, no seals (defensive; UI won't offer them).
- `displaySeconds`: running → `accumulatedSeconds + max(0, Int(now - currentSegmentStart))`; else `accumulatedSeconds`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class StopwatchEngineTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private let eng = StopwatchEngine()

    func test_start_from_idle() {
        let (s, sealed) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(s.day, "2026-07-01")
        XCTAssertEqual(s.accumulatedSeconds, 0)
        XCTAssertEqual(s.currentSegmentStart, d("2026-07-01T09:00:00-04:00"))
        XCTAssertTrue(sealed.isEmpty)
    }

    func test_stop_seals_segment_and_accumulates() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.stop(r, now: d("2026-07-01T10:30:00-04:00"), calendar: cal)
        XCTAssertEqual(s.phase, .stopped)
        XCTAssertEqual(s.accumulatedSeconds, 5400)
        XCTAssertNil(s.currentSegmentStart)
        XCTAssertEqual(sealed.count, 1)
        XCTAssertEqual(sealed[0].day, "2026-07-01")
        XCTAssertEqual(sealed[0].segment.seconds, 5400)
    }

    func test_resume_starts_new_segment_no_seal() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (st, _) = eng.stop(r, now: d("2026-07-01T10:00:00-04:00"), calendar: cal)
        let (rs, sealed) = eng.resume(st, now: d("2026-07-01T10:15:00-04:00"), calendar: cal)
        XCTAssertEqual(rs.phase, .running)
        XCTAssertEqual(rs.accumulatedSeconds, 3600)               // break not counted
        XCTAssertEqual(rs.currentSegmentStart, d("2026-07-01T10:15:00-04:00"))
        XCTAssertTrue(sealed.isEmpty)
    }

    func test_end_from_running_seals_then_idle() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (e, sealed) = eng.end(r, now: d("2026-07-01T17:00:00-04:00"), calendar: cal)
        XCTAssertEqual(e.phase, .idle)
        XCTAssertEqual(e.accumulatedSeconds, 0)
        XCTAssertNil(e.day)
        XCTAssertEqual(sealed.count, 1)
        XCTAssertEqual(sealed[0].segment.seconds, 8 * 3600)
    }

    func test_end_from_stopped_no_new_seal() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (st, _) = eng.stop(r, now: d("2026-07-01T10:00:00-04:00"), calendar: cal)
        let (e, sealed) = eng.end(st, now: d("2026-07-01T10:30:00-04:00"), calendar: cal)
        XCTAssertEqual(e.phase, .idle)
        XCTAssertTrue(sealed.isEmpty)
    }

    func test_display_seconds_running_and_stopped() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        XCTAssertEqual(eng.displaySeconds(r, now: d("2026-07-01T09:00:30-04:00")), 30)
        let (st, _) = eng.stop(r, now: d("2026-07-01T09:01:00-04:00"), calendar: cal)
        XCTAssertEqual(eng.displaySeconds(st, now: d("2026-07-01T12:00:00-04:00")), 60)
    }

    func test_evaluate_cuts_at_midnight_and_resets_today() {
        // Start Fri 23:00, evaluate Sat 00:15 → seal Fri 23:00–23:59:59, today stopped/0.
        let (r, _) = eng.start(.idle, now: d("2026-07-01T23:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(r, now: d("2026-07-02T00:15:00-04:00"), calendar: cal)
        XCTAssertEqual(sealed.count, 1)
        XCTAssertEqual(sealed[0].day, "2026-07-01")
        XCTAssertEqual(sealed[0].segment.seconds, 3599)           // 23:00:00 → 23:59:59
        XCTAssertEqual(s.phase, .stopped)
        XCTAssertEqual(s.accumulatedSeconds, 0)
        XCTAssertEqual(s.day, "2026-07-02")
        XCTAssertNil(s.currentSegmentStart)
    }

    func test_evaluate_multiday_span_seals_only_start_day() {
        // Fri 23:00 start, reopened Mon 10:00 → only Fri sealed; Sat/Sun nothing.
        let (r, _) = eng.start(.idle, now: d("2026-07-01T23:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(r, now: d("2026-07-05T10:00:00-04:00"), calendar: cal)
        XCTAssertEqual(sealed.map(\.day), ["2026-07-01"])
        XCTAssertEqual(sealed[0].segment.seconds, 3599)
        XCTAssertEqual(s.phase, .stopped)
        XCTAssertEqual(s.day, "2026-07-05")
    }

    func test_evaluate_same_day_is_noop() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(r, now: d("2026-07-01T15:00:00-04:00"), calendar: cal)
        XCTAssertEqual(s, r)
        XCTAssertTrue(sealed.isEmpty)
    }

    func test_button_gating() {
        XCTAssertTrue(StopwatchEngine.canStart(.idle))
        XCTAssertFalse(StopwatchEngine.canStart(.running))
        XCTAssertTrue(StopwatchEngine.canStop(.running))
        XCTAssertTrue(StopwatchEngine.canResume(.stopped))
        XCTAssertTrue(StopwatchEngine.canEnd(.running))
        XCTAssertTrue(StopwatchEngine.canEnd(.stopped))
        XCTAssertFalse(StopwatchEngine.canEnd(.idle))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter StopwatchEngineTests`
Expected: FAIL — `cannot find 'StopwatchEngine' in scope`.

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

public struct SealedSegment: Equatable, Sendable {
    public let day: String
    public let segment: WorkSegment
    public init(day: String, segment: WorkSegment) {
        self.day = day
        self.segment = segment
    }
}

/// Pure stopwatch state machine + wall-clock math + local-midnight cut. No I/O,
/// no bare Date(): every entry point takes `now` and `calendar` so all time
/// logic is unit-testable with a fake clock. No session coupling.
public struct StopwatchEngine {
    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func displaySeconds(_ snap: StopwatchSnapshot, now: Date) -> Int {
        guard snap.phase == .running, let start = snap.currentSegmentStart else {
            return snap.accumulatedSeconds
        }
        return snap.accumulatedSeconds + max(0, Int(now.timeIntervalSince(start)))
    }

    public func start(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .idle else { return (snap, []) }
        return (StopwatchSnapshot(phase: .running, day: Self.dayKey(now, calendar: calendar),
                                  accumulatedSeconds: 0, currentSegmentStart: now), [])
    }

    public func stop(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .running, let start = snap.currentSegmentStart else { return (snap, []) }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let seg = SealedSegment(day: snap.day ?? Self.dayKey(start, calendar: calendar),
                                segment: WorkSegment(start: start, end: now, seconds: seconds))
        var next = snap
        next.phase = .stopped
        next.accumulatedSeconds += seconds
        next.currentSegmentStart = nil
        return (next, [seg])
    }

    public func resume(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .stopped else { return (snap, []) }
        var next = snap
        next.phase = .running
        next.currentSegmentStart = now
        return (next, [])
    }

    public func end(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        var sealed: [SealedSegment] = []
        if snap.phase == .running, let start = snap.currentSegmentStart {
            let seconds = max(0, Int(now.timeIntervalSince(start)))
            sealed.append(SealedSegment(day: snap.day ?? Self.dayKey(start, calendar: calendar),
                                        segment: WorkSegment(start: start, end: now, seconds: seconds)))
        } else if snap.phase == .idle {
            return (snap, [])  // nothing to end
        }
        return (StopwatchSnapshot.idle, sealed)
    }

    public func evaluate(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .running, let start = snap.currentSegmentStart else { return (snap, []) }
        let startDay = Self.dayKey(start, calendar: calendar)
        guard startDay != Self.dayKey(now, calendar: calendar) else { return (snap, []) }
        // Cut at 23:59:59 local of the start day.
        let startOfStartDay = calendar.startOfDay(for: start)
        let cutEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfStartDay) ?? start
        let seconds = max(0, Int(cutEnd.timeIntervalSince(start)))
        let seg = SealedSegment(day: startDay,
                                segment: WorkSegment(start: start, end: cutEnd, seconds: seconds))
        // Reset to stopped/0 for the current day; spanned days produce nothing.
        let next = StopwatchSnapshot(phase: .stopped, day: Self.dayKey(now, calendar: calendar),
                                     accumulatedSeconds: 0, currentSegmentStart: nil)
        return (next, [seg])
    }

    public static func canStart(_ p: StopwatchPhase) -> Bool { p == .idle }
    public static func canStop(_ p: StopwatchPhase) -> Bool { p == .running }
    public static func canResume(_ p: StopwatchPhase) -> Bool { p == .stopped }
    public static func canEnd(_ p: StopwatchPhase) -> Bool { p == .running || p == .stopped }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter StopwatchEngineTests`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/StopwatchEngine.swift Tests/AignalsCoreTests/StopwatchEngineTests.swift
git commit -m "feat(core): StopwatchEngine — pure state machine + midnight cut"
```

---

### Task 5: `StopwatchStateStore` — persist the running snapshot

**Files:**
- Create: `Sources/AignalsCore/StopwatchStateStore.swift`
- Test: `Tests/AignalsCoreTests/StopwatchStateStoreTests.swift`

**Interfaces:**
- Consumes: `Paths.stopwatchStateFile`, `StopwatchSnapshot`.
- Produces: `public final class StopwatchStateStore { public init(paths: Paths); public private(set) var snapshot: StopwatchSnapshot; public func save(_ s: StopwatchSnapshot) }` — load corrupt/missing → `.idle`, atomic write, ISO-8601 dates.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class StopwatchStateStoreTests: XCTestCase {
    private func tmp() -> Paths {
        Paths(environment: ["AIGNALS_HOME":
            FileManager.default.temporaryDirectory.appendingPathComponent("sw-\(UUID().uuidString)").path])
    }
    func test_save_then_reload() {
        let p = tmp()
        let store = StopwatchStateStore(paths: p)
        store.save(StopwatchSnapshot(phase: .running, day: "2026-07-01",
                                     accumulatedSeconds: 10, currentSegmentStart: Date(timeIntervalSince1970: 5)))
        let fresh = StopwatchStateStore(paths: p)
        XCTAssertEqual(fresh.snapshot.phase, .running)
        XCTAssertEqual(fresh.snapshot.accumulatedSeconds, 10)
    }
    func test_missing_is_idle() {
        XCTAssertEqual(StopwatchStateStore(paths: tmp()).snapshot, .idle)
    }
    func test_corrupt_is_idle() throws {
        let p = tmp(); try p.ensureDirectories()
        try Data("garbage".utf8).write(to: p.stopwatchStateFile)
        XCTAssertEqual(StopwatchStateStore(paths: p).snapshot, .idle)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter StopwatchStateStoreTests`
Expected: FAIL — `cannot find 'StopwatchStateStore' in scope`.

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

/// Persists the volatile stopwatch running state to `stopwatch-state.json`.
/// Load is crash-safe (missing/malformed → `.idle`); writes are atomic. No
/// session coupling.
public final class StopwatchStateStore {
    private let paths: Paths
    public private(set) var snapshot: StopwatchSnapshot

    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.stopwatchStateFile),
           let snap = try? Self.decoder.decode(StopwatchSnapshot.self, from: data) {
            self.snapshot = snap
        } else {
            self.snapshot = .idle
        }
    }

    public func save(_ s: StopwatchSnapshot) {
        snapshot = s
        try? paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tmp = paths.stopwatchStateFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? enc.encode(s) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.stopwatchStateFile, withItemAt: tmp)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter StopwatchStateStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/StopwatchStateStore.swift Tests/AignalsCoreTests/StopwatchStateStoreTests.swift
git commit -m "feat(core): StopwatchStateStore — persist running snapshot"
```

---

### Task 6: `WorklogStore` — sealed history by day

**Files:**
- Create: `Sources/AignalsCore/WorklogStore.swift`
- Test: `Tests/AignalsCoreTests/WorklogStoreTests.swift`

**Interfaces:**
- Consumes: `Paths.worklogFile`, `WorkDay`, `WorkSegment`, `SealedSegment`.
- Produces:
  - `public final class WorklogStore { public init(paths: Paths) }`
  - `public func append(_ sealed: SealedSegment)` — add the segment to its day, bump that day's `totalSeconds`, persist.
  - `public func append(_ sealed: [SealedSegment])` — convenience, appends each.
  - `public var daysNewestFirst: [(day: String, work: WorkDay)]` — sorted by day string descending.
  - On-disk shape `{ "version": 1, "days": { "YYYY-MM-DD": WorkDay } }` (private `Envelope`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class WorklogStoreTests: XCTestCase {
    private func tmp() -> Paths {
        Paths(environment: ["AIGNALS_HOME":
            FileManager.default.temporaryDirectory.appendingPathComponent("wl-\(UUID().uuidString)").path])
    }
    private func seg(_ day: String, _ secs: Int) -> SealedSegment {
        SealedSegment(day: day, segment: WorkSegment(start: Date(timeIntervalSince1970: 0),
                                                     end: Date(timeIntervalSince1970: TimeInterval(secs)),
                                                     seconds: secs))
    }
    func test_append_accumulates_total_and_persists() {
        let p = tmp()
        let store = WorklogStore(paths: p)
        store.append(seg("2026-07-01", 5400))
        store.append(seg("2026-07-01", 4500))
        let today = store.daysNewestFirst.first { $0.day == "2026-07-01" }!.work
        XCTAssertEqual(today.segments.count, 2)
        XCTAssertEqual(today.totalSeconds, 9900)
        // Reload from disk.
        let fresh = WorklogStore(paths: p)
        XCTAssertEqual(fresh.daysNewestFirst.first!.work.totalSeconds, 9900)
    }
    func test_days_newest_first() {
        let p = tmp()
        let store = WorklogStore(paths: p)
        store.append(seg("2026-06-30", 60))
        store.append(seg("2026-07-02", 60))
        store.append(seg("2026-07-01", 60))
        XCTAssertEqual(store.daysNewestFirst.map(\.day), ["2026-07-02", "2026-07-01", "2026-06-30"])
    }
    func test_corrupt_is_empty() throws {
        let p = tmp(); try p.ensureDirectories()
        try Data("nope".utf8).write(to: p.worklogFile)
        XCTAssertTrue(WorklogStore(paths: p).daysNewestFirst.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter WorklogStoreTests`
Expected: FAIL — `cannot find 'WorklogStore' in scope`.

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

/// Persists sealed work history to `worklog.json`, keyed by local day. Append
/// adds a segment to its day and keeps `totalSeconds` in sync. Load is
/// crash-safe (missing/malformed → empty); writes are atomic. No session coupling.
public final class WorklogStore {
    private struct Envelope: Codable {
        var version: Int
        var days: [String: WorkDay]
    }

    private let paths: Paths
    private var days: [String: WorkDay]

    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.worklogFile),
           let env = try? Self.decoder.decode(Envelope.self, from: data) {
            self.days = env.days
        } else {
            self.days = [:]
        }
    }

    public func append(_ sealed: SealedSegment) {
        var day = days[sealed.day] ?? WorkDay()
        day.segments.append(sealed.segment)
        day.totalSeconds += sealed.segment.seconds
        days[sealed.day] = day
        persist()
    }

    public func append(_ sealed: [SealedSegment]) {
        guard !sealed.isEmpty else { return }
        for s in sealed { append(s) }
    }

    public var daysNewestFirst: [(day: String, work: WorkDay)] {
        days.keys.sorted(by: >).map { ($0, days[$0]!) }
    }

    private func persist() {
        try? paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tmp = paths.worklogFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? enc.encode(Envelope(version: 1, days: days)) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.worklogFile, withItemAt: tmp)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter WorklogStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/WorklogStore.swift Tests/AignalsCoreTests/WorklogStoreTests.swift
git commit -m "feat(core): WorklogStore — sealed history by local day"
```

---

### Task 7: `HomeWipe` keeps worklog too (verify)

**Files:**
- Modify: none expected (Quote plan Task 8 already keeps `worklog.json`).
- Test: `Tests/AignalsCoreTests/HomeWipeTests.swift`

The Quote feature's `uninstall(keepSavedData:)` already passes `["quotes.json", "worklog.json"]`. Add a test asserting worklog is preserved so this feature has its own gate.

- [ ] **Step 1: Add a failing test** (append to `HomeWipeTests.swift`)

```swift
func test_wipe_keeps_worklog_json() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
    try fm.createDirectory(at: home, withIntermediateDirectories: true)
    try Data("log".utf8).write(to: home.appendingPathComponent("worklog.json"))
    try Data("x".utf8).write(to: home.appendingPathComponent("config.json"))

    HomeWipe.wipe(home: home, keeping: ["quotes.json", "worklog.json"], fileManager: fm)

    XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("worklog.json").path))
    XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("config.json").path))
}
```

- [ ] **Step 2: Run — should PASS immediately** (HomeWipe already generic)

Run: `swift test --filter HomeWipeTests`
Expected: PASS. If `HomeWipe` doesn't exist yet, the Quote plan (Task 8) hasn't been implemented — implement the Quote plan first.

- [ ] **Step 3: Commit**

```bash
git add Tests/AignalsCoreTests/HomeWipeTests.swift
git commit -m "test(core): HomeWipe preserves worklog.json"
```

---

### Task 8: `AppViewModel` stopwatch coordination

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

Verified by build + Task 12 manual checklist (App target has no unit tests by convention; the logic lives in the Core engine which is fully tested).

**Interfaces:**
- Consumes: `StopwatchEngine`, `StopwatchStateStore`, `WorklogStore`, `WorktimeFormatter`, `sendCurrentQuoteToFeishu()` (Quote Task 9.5).
- Produces on `AppViewModel`:
  - `var stopwatchPhase: StopwatchPhase`
  - `func stopwatchDisplay(now: Date) -> String` → `WorktimeFormatter.clock(engine.displaySeconds(...))`
  - `func stopwatchStart()` / `stopwatchStop()` / `stopwatchResume()` / `stopwatchEnd()`
  - `func evaluateStopwatch(now: Date = Date())` — apply `engine.evaluate`, persist + seal if it cut
  - `var worklogDays: [(day: String, work: WorkDay)]`
  - button gates `canStopwatchStart/Stop/Resume/End`

- [ ] **Step 1: Add stored deps + observable version** — near the other stores in `AppViewModel`:

```swift
    private let stopwatchEngine = StopwatchEngine()
    private let stopwatchStore: StopwatchStateStore
    private let worklogStore: WorklogStore
    private let stopwatchCalendar = Calendar.current

    /// Bumped on every stopwatch mutation so SwiftUI re-derives phase/worklog
    /// (neither store is @Observable — same pattern as overridesVersion).
    private var stopwatchVersion = 0
```

Init in `init` where `paths` exists:

```swift
        self.stopwatchStore = StopwatchStateStore(paths: paths)
        self.worklogStore = WorklogStore(paths: paths)
```

- [ ] **Step 2: Add the coordination extension**

```swift
extension AppViewModel {
    var stopwatchPhase: StopwatchPhase {
        _ = stopwatchVersion
        return stopwatchStore.snapshot.phase
    }

    func stopwatchDisplay(now: Date = Date()) -> String {
        _ = stopwatchVersion
        return WorktimeFormatter.clock(stopwatchEngine.displaySeconds(stopwatchStore.snapshot, now: now))
    }

    var worklogDays: [(day: String, work: WorkDay)] {
        _ = stopwatchVersion
        return worklogStore.daysNewestFirst
    }

    var canStopwatchStart: Bool  { StopwatchEngine.canStart(stopwatchPhase) }
    var canStopwatchStop: Bool   { StopwatchEngine.canStop(stopwatchPhase) }
    var canStopwatchResume: Bool { StopwatchEngine.canResume(stopwatchPhase) }
    var canStopwatchEnd: Bool    { StopwatchEngine.canEnd(stopwatchPhase) }

    /// Apply a transition: persist the new snapshot and append any sealed segments.
    private func applyStopwatch(_ result: (StopwatchSnapshot, [SealedSegment])) {
        stopwatchStore.save(result.0)
        worklogStore.append(result.1)
        stopwatchVersion &+= 1
    }

    func stopwatchStart(now: Date = Date()) {
        let wasIdle = stopwatchStore.snapshot.phase == .idle
        applyStopwatch(stopwatchEngine.start(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
        // Feishu on the day's FIRST start only (idle → running). Resume never sends.
        if wasIdle, stopwatchStore.snapshot.phase == .running {
            sendCurrentQuoteToFeishu()
        }
    }
    func stopwatchStop(now: Date = Date()) {
        applyStopwatch(stopwatchEngine.stop(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
    }
    func stopwatchResume(now: Date = Date()) {
        applyStopwatch(stopwatchEngine.resume(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
    }
    func stopwatchEnd(now: Date = Date()) {
        applyStopwatch(stopwatchEngine.end(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
    }

    /// Called on launch + on the tick; performs the midnight cut when needed.
    func evaluateStopwatch(now: Date = Date()) {
        let result = stopwatchEngine.evaluate(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar)
        if !result.1.isEmpty || result.0 != stopwatchStore.snapshot {
            applyStopwatch(result)
        }
    }
}
```

- [ ] **Step 3: Evaluate on startup** — in `init` after the other setup (e.g. after `fetchQuoteIfNeeded()`), add:

```swift
        evaluateStopwatch()
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): AppViewModel stopwatch coordination (+Feishu on first start)"
```

---

### Task 9: Menubar stopwatch region

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `vm.stopwatchDisplay(now:)`, phase gates, `vm.stopwatchStart/Stop/Resume/End`, `vm.evaluateStopwatch`, existing `tick` state. Uses `openWindow(id: "stat")`.

- [ ] **Step 1: Add a `stopwatchRow` view** — add to `MenuContent`:

```swift
    @ViewBuilder
    private var stopwatchRow: some View {
        HStack(spacing: 10) {
            Text(vm.stopwatchDisplay(now: tick))
                .font(.system(.title3, design: .monospaced))
                .monospacedDigit()

            Spacer()

            if vm.canStopwatchStart {
                Button("Start") { vm.stopwatchStart() }
            }
            if vm.canStopwatchStop {
                Button("Stop") { vm.stopwatchStop() }
            }
            if vm.canStopwatchResume {
                Button("Resume") { vm.stopwatchResume() }
            }
            if vm.canStopwatchEnd {
                Button("End") { vm.stopwatchEnd() }
            }
            Button { openWindow(id: "stat") } label: {
                Image(systemName: "chart.bar")
            }
            .help("Work stats")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
```

- [ ] **Step 2: Insert it into the panel body** — place `stopwatchRow` just below `quoteRow` (from the Quote feature) at the top, before `header`:

```swift
        VStack(alignment: .leading, spacing: 0) {
            quoteRow
            Divider().background(style.hairline)
            stopwatchRow
            Divider().background(style.hairline)
            header
            …
```

> If the Quote feature isn't in this build, place `stopwatchRow` as the first child before `header`.

- [ ] **Step 3: Drive the midnight cut off the existing tick** — the panel already has `.onReceive(timer) { tick = $0 }`. Extend it to also evaluate:

```swift
        .onReceive(timer) { newTick in
            tick = newTick
            vm.evaluateStopwatch(now: newTick)
        }
```

> **Note (expected, not a bug):** the panel's `timer` only fires while the dropdown is open. If the app stays running but the panel is closed across midnight, the live cut won't fire in real time — but `evaluateStopwatch` runs on the next panel open AND on launch (Task 8 Step 3), applying the exact same `evaluate` cut. So the cut is never *lost*, only deferred to the next interaction. Test agents should verify the cut via reopen/relaunch, which is the spec's stated recovery path.

- [ ] **Step 4: Build** (fails until Task 10 adds the Stat window's `StatView`; do Task 10 next)

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: may fail with `cannot find 'StatView'` (the `openWindow(id:"stat")` target is registered in Task 10) — proceed to Task 10, then build.

- [ ] **Step 5: Commit** (after Task 10 builds green — commit together there). Skip here.

---

### Task 10: Stat window

**Files:**
- Create: `App/Aignals/Sources/StatView.swift`
- Modify: `App/Aignals/Sources/AignalsApp.swift` (register the `Window`)

**Interfaces:**
- Consumes: `vm.worklogDays` (`[(day: String, work: WorkDay)]`, newest-first), `WorktimeFormatter.human`, `WorktimeFormatter` for segment times.

- [ ] **Step 1: Create `StatView`**

```swift
import SwiftUI
import AignalsCore

/// Read-only work-history window: a by-day list, expandable to per-segment
/// detail. Opened via openWindow(id: "stat"). No session coupling.
@MainActor
struct StatView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var expanded: Set<String> = []

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d yyyy"; return f
    }()
    private static let dayParse: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let clockLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func dayTitle(_ day: String) -> String {
        guard let d = Self.dayParse.date(from: day) else { return day }
        return Self.dayLabel.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Work Stats").font(.headline)
                Spacer()
                Button("Done") { dismissWindow(id: "stat") }
            }
            .padding(12)
            Divider()

            if vm.worklogDays.isEmpty {
                Text("No work logged yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.worklogDays, id: \.day) { entry in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expanded.contains(entry.day) },
                                set: { on in
                                    if on { expanded.insert(entry.day) } else { expanded.remove(entry.day) }
                                }
                            )
                        ) {
                            ForEach(Array(entry.work.segments.enumerated()), id: \.offset) { _, seg in
                                HStack {
                                    Text("\(Self.clockLabel.string(from: seg.start))–\(Self.clockLabel.string(from: seg.end))")
                                        .font(.callout)
                                    Spacer()
                                    Text(WorktimeFormatter.human(seg.seconds))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            HStack {
                                Text(dayTitle(entry.day))
                                Spacer()
                                Text(WorktimeFormatter.human(entry.work.totalSeconds))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 460)
    }
}
```

- [ ] **Step 2: Register the `Window`** — in `AignalsApp.swift`, add next to the Settings/Projector windows:

```swift
        Window("Work Stats", id: "stat") {
            StatView(vm: vm)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 460)
```

- [ ] **Step 3: Build** (Tasks 9 + 10 together)

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

> If `StatView.swift` isn't in the target, add it to the `Aignals` target membership and rebuild.

- [ ] **Step 4: Commit** (Tasks 9 + 10)

```bash
git add App/Aignals/Sources/MenuContent.swift App/Aignals/Sources/StatView.swift App/Aignals/Sources/AignalsApp.swift
git commit -m "feat(app): menubar stopwatch row + Stat window"
```

---

### Task 11: Manual test-checklist file (App-level acceptance)

**Files:**
- Modify: `docs/superpowers/specs/manual-test-checklist.md`

- [ ] **Step 1: Add stopwatch rows** — append a section with each item from the spec's manual checklist (start/stop/resume/end, button gating, quit-and-reopen wall-clock continuation, cross-midnight cut, Stat list + expand + empty state, Feishu-on-first-start-only, files under `~/.aignals/` + upgrade preserves them).

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/manual-test-checklist.md
git commit -m "docs: stopwatch manual test checklist"
```

---

### Task 12: Full verification

- [ ] **Step 1: Whole Core suite**

Run: `swift test 2>&1 | tail -20`
Expected: all pass — new `WorktimeFormatterTests`, `StopwatchModelsTests`, `StopwatchEngineTests`, `StopwatchStateStoreTests`, `WorklogStoreTests`, updated `PathsTests`, `HomeWipeTests`.

- [ ] **Step 2: Build the app**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the manual checklist** (spec's "Manual integration checklist"), verifying each item against the running app. Pay special attention to:
  - Quit while running, reopen same day → time continued by wall clock.
  - Set the clock forward past midnight (or reopen next day) → yesterday sealed at 23:59:59; today stopped/0.
  - First Start of the day posts the quote to Feishu (if configured); Resume does not.
  - `~/.aignals/worklog.json` + `stopwatch-state.json` have the documented shapes; replacing the .app preserves them.

---

## Notes for the implementer

- Implement the **Quote plan first** — this plan depends on `sendCurrentQuoteToFeishu()` (Quote Task 9.5) and `HomeWipe` (Quote Task 8) already existing.
- Core tasks (1–7) run under `swift test`. App tasks (8–10) are verified by `xcodebuild build` + the Task 12 manual checklist.
- If a new `App/Aignals/Sources/*.swift` file isn't compiled, add it to the `Aignals` Xcode target membership.
- Hard decoupling: nothing in the stopwatch units may import/reference session types. The only shared thing is the 1-second UI tick.
- All time logic stays in `StopwatchEngine` behind the injected clock — do not sprinkle `Date()` into the engine.

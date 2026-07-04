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
        XCTAssertEqual(rs.accumulatedSeconds, 3600)
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

    // At midnight a running timer seals its work up to the start-day's
    // 23:59:59, then auto-ENDs (resets fully to idle) so the next day starts
    // from zero — same as if the user had clicked End.
    func test_evaluate_running_at_midnight_seals_then_auto_ends() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T23:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(r, now: d("2026-07-02T00:15:00-04:00"), calendar: cal)
        XCTAssertEqual(sealed.count, 1)
        XCTAssertEqual(sealed[0].day, "2026-07-01")
        XCTAssertEqual(sealed[0].segment.seconds, 3599)
        XCTAssertEqual(s.phase, .idle)
        XCTAssertEqual(s.accumulatedSeconds, 0)
        XCTAssertNil(s.day)
        XCTAssertNil(s.currentSegmentStart)
    }

    func test_evaluate_running_multiday_span_seals_only_start_day_then_ends() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T23:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(r, now: d("2026-07-05T10:00:00-04:00"), calendar: cal)
        XCTAssertEqual(sealed.map(\.day), ["2026-07-01"])
        XCTAssertEqual(sealed[0].segment.seconds, 3599)
        XCTAssertEqual(s.phase, .idle)
        XCTAssertNil(s.day)
    }

    // A paused (stopped) timer already sealed its time to the worklog when the
    // user hit pause, so crossing midnight auto-ENDs with NO new seal — it just
    // resets to idle so yesterday's paused timer doesn't linger.
    func test_evaluate_stopped_at_midnight_auto_ends_without_reseal() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T22:00:00-04:00"), calendar: cal)
        let (st, _) = eng.stop(r, now: d("2026-07-01T23:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(st, now: d("2026-07-02T00:15:00-04:00"), calendar: cal)
        XCTAssertTrue(sealed.isEmpty)
        XCTAssertEqual(s.phase, .idle)
        XCTAssertEqual(s.accumulatedSeconds, 0)
        XCTAssertNil(s.day)
        XCTAssertNil(s.currentSegmentStart)
    }

    func test_evaluate_stopped_same_day_is_noop() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (st, _) = eng.stop(r, now: d("2026-07-01T10:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(st, now: d("2026-07-01T15:00:00-04:00"), calendar: cal)
        XCTAssertEqual(s, st)
        XCTAssertTrue(sealed.isEmpty)
    }

    func test_evaluate_running_same_day_is_noop() {
        let (r, _) = eng.start(.idle, now: d("2026-07-01T09:00:00-04:00"), calendar: cal)
        let (s, sealed) = eng.evaluate(r, now: d("2026-07-01T15:00:00-04:00"), calendar: cal)
        XCTAssertEqual(s, r)
        XCTAssertTrue(sealed.isEmpty)
    }

    func test_evaluate_idle_is_noop() {
        let (s, sealed) = eng.evaluate(.idle, now: d("2026-07-02T00:15:00-04:00"), calendar: cal)
        XCTAssertEqual(s, .idle)
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

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

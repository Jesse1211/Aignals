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

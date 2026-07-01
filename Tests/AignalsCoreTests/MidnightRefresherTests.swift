import XCTest
@testable import AignalsCore

final class MidnightRefresherTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func test_didCrossMidnight_true_across_days() {
        let last = date("2026-07-01T23:30:00-04:00")
        let now  = date("2026-07-02T00:15:00-04:00")
        XCTAssertTrue(MidnightRefresher.didCrossMidnight(from: last, to: now, calendar: cal))
    }

    func test_didCrossMidnight_false_same_day() {
        let last = date("2026-07-01T09:00:00-04:00")
        let now  = date("2026-07-01T17:00:00-04:00")
        XCTAssertFalse(MidnightRefresher.didCrossMidnight(from: last, to: now, calendar: cal))
    }

    func test_nextMidnight_is_strictly_after_and_at_00() {
        let now = date("2026-07-01T09:00:00-04:00")
        let next = MidnightRefresher.nextMidnight(after: now, calendar: cal)
        let comps = cal.dateComponents([.hour, .minute, .second], from: next)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertTrue(next > now)
        XCTAssertEqual(cal.dateComponents([.day], from: next).day, 2)
    }
}

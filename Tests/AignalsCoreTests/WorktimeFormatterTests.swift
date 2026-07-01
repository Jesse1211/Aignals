import XCTest
@testable import AignalsCore

final class WorktimeFormatterTests: XCTestCase {
    func test_clock_pads_hms() {
        XCTAssertEqual(WorktimeFormatter.clock(0), "00:00:00")
        XCTAssertEqual(WorktimeFormatter.clock(9900), "02:45:00")
        XCTAssertEqual(WorktimeFormatter.clock(59), "00:00:59")
        XCTAssertEqual(WorktimeFormatter.clock(3661), "01:01:01")
    }
    func test_human_drops_zero_hours() {
        XCTAssertEqual(WorktimeFormatter.human(0), "0m")
        XCTAssertEqual(WorktimeFormatter.human(2700), "45m")
        XCTAssertEqual(WorktimeFormatter.human(9900), "2h 45m")
        XCTAssertEqual(WorktimeFormatter.human(3600), "1h 0m")
    }
}

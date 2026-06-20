import XCTest
@testable import AignalsCore

final class ElapsedFormatterTests: XCTestCase {
    func testSecondsUnder60() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 14), "14s")
    }
    func testMinutesUnder60() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 125), "2m")
    }
    func testHoursUnder24() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 3 * 3600 + 5), "3h")
    }
    func testDays() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 2 * 86_400 + 10), "2d")
    }
}

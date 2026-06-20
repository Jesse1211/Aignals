import XCTest
import AppKit
@testable import AignalsCore

final class StatusIconTests: XCTestCase {
    func testEachStateProducesNonTemplate18ptImage() {
        for state in [AggregateStatus.idle, .running, .error] {
            let img = StatusIcon.image(for: state)
            XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
            XCTAssertFalse(img.isTemplate, "Status images must keep their own color")
        }
    }
}

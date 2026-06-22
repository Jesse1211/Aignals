import XCTest
import AppKit
@testable import AignalsCore

final class StatusIconTests: XCTestCase {
    func testEachStateProducesNonTemplate18ptImage() {
        let cases: [(counts: StatusCounts, hasError: Bool)] = [
            (.zero, false),                                                   // idle
            (StatusCounts(working: 1, waitingPermission: 0, waitingInput: 0), false), // running
            (.zero, true),                                                   // error
        ]
        for c in cases {
            let img = StatusIcon.image(for: c.counts, hasError: c.hasError)
            XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
            XCTAssertFalse(img.isTemplate, "Status images must keep their own color")
        }
    }
}

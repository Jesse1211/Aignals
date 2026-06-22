import XCTest
import AppKit
@testable import AignalsCore

final class StatusIconTests: XCTestCase {
    func testImagesAreNonTemplateAndNonEmpty() {
        let cases: [(counts: StatusCounts, hasError: Bool)] = [
            (.zero, false),                                                           // idle / empty
            (StatusCounts(working: 1, waitingPermission: 0, waitingInput: 0), false), // single group
            (StatusCounts(working: 1, waitingPermission: 0, waitingInput: 2), false), // two groups
            (.zero, true),                                                            // error
        ]
        for c in cases {
            let img = StatusIcon.image(for: c.counts, hasError: c.hasError)
            XCTAssertGreaterThan(img.size.width, 0, "Status image must be non-empty")
            XCTAssertGreaterThan(img.size.height, 0, "Status image must be non-empty")
            XCTAssertFalse(img.isTemplate, "Status images must keep their own color")
        }
    }

    /// INV-5 / ADR-11: a zero-count group is omitted entirely. We assert this
    /// deterministically by width: {1,0,2} (two visible groups) must be strictly
    /// narrower than {1,1,2} (three visible groups), because the missing yellow
    /// group removes its dot + count + inter-group gap from the layout.
    func testZeroCountGroupIsOmittedNarrowerImage() {
        let withGap = StatusIcon.image(
            for: StatusCounts(working: 1, waitingPermission: 0, waitingInput: 2),
            hasError: false
        )
        let full = StatusIcon.image(
            for: StatusCounts(working: 1, waitingPermission: 1, waitingInput: 2),
            hasError: false
        )
        XCTAssertLessThan(
            withGap.size.width,
            full.size.width,
            "Omitting the zero-count (yellow) group must produce a narrower image"
        )
    }

    /// hasError takes precedence and renders the gray error treatment regardless
    /// of counts, at the fixed 18x18 size.
    func testErrorTreatmentTakesPrecedence() {
        let counts = StatusCounts(working: 3, waitingPermission: 2, waitingInput: 1)
        let img = StatusIcon.image(for: counts, hasError: true)
        XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(img.isTemplate)
    }

    func testEmptyStateRendersSomething() {
        let img = StatusIcon.image(for: .zero, hasError: false)
        XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(img.isTemplate)
    }
}

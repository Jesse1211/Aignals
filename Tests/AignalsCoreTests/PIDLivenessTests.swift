import XCTest
@testable import AignalsCore

final class PIDLivenessTests: XCTestCase {
    func testCurrentProcessIsAlive() {
        let liveness = SystemPIDLiveness()
        XCTAssertEqual(liveness.state(of: pid_t(getpid())), .alive)
    }

    func testHighlyUnlikelyPIDIsDead() {
        // pid 1 (launchd) is alive on macOS, so use a synthetic huge value
        let liveness = SystemPIDLiveness()
        XCTAssertEqual(liveness.state(of: 999_999), .dead)
    }
}

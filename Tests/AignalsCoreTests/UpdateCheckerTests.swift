import XCTest
@testable import AignalsCore

final class UpdateCheckerTests: XCTestCase {
    // --- version comparison ---
    func test_compare_detects_newer() {
        XCTAssertTrue(UpdateChecker.compare(current: "0.5.1", latest: "0.5.2"))
        XCTAssertTrue(UpdateChecker.compare(current: "0.5.1", latest: "0.6.0"))
        XCTAssertTrue(UpdateChecker.compare(current: "0.9.9", latest: "1.0.0"))
    }
    func test_compare_equal_or_older_is_not_newer() {
        XCTAssertFalse(UpdateChecker.compare(current: "0.5.1", latest: "0.5.1"))
        XCTAssertFalse(UpdateChecker.compare(current: "0.5.2", latest: "0.5.1"))
        XCTAssertFalse(UpdateChecker.compare(current: "1.0.0", latest: "0.9.9"))
    }
    func test_compare_handles_uneven_component_counts() {
        XCTAssertTrue(UpdateChecker.compare(current: "0.5", latest: "0.5.1"))
        XCTAssertFalse(UpdateChecker.compare(current: "0.5.0", latest: "0.5"))
    }

    // --- install source ---
    func test_detectSource_caskroom_path_is_homebrew() {
        let p = "/opt/homebrew/Caskroom/aignals/0.5.1/Aignals.app"
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: p), .homebrew)
    }
    func test_detectSource_intel_caskroom_is_homebrew() {
        let p = "/usr/local/Caskroom/aignals/0.5.1/Aignals.app"
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: p), .homebrew)
    }
    func test_detectSource_applications_is_direct() {
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: "/Applications/Aignals.app"), .direct)
    }
    func test_detectSource_unknown_defaults_direct() {
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: "/Users/x/Desktop/Aignals.app"), .direct)
    }

    // --- state mapping ---
    func test_state_nil_latest_is_failed() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: nil, source: .direct), .failed)
    }
    func test_state_same_version_is_upToDate() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: "0.5.1", source: .direct), .upToDate)
    }
    func test_state_newer_direct_is_available_direct() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: "0.6.0", source: .direct),
                       .available(version: "0.6.0", source: .direct))
    }
    func test_state_newer_homebrew_is_available_homebrew() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: "0.6.0", source: .homebrew),
                       .available(version: "0.6.0", source: .homebrew))
    }
}

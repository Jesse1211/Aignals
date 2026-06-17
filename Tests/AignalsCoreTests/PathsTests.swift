import XCTest
@testable import AignalsCore

final class PathsTests: XCTestCase {
    func testDefaultHomeIsDotAignalsInUserHome() {
        let paths = Paths(environment: [:])
        XCTAssertEqual(paths.home.path, NSHomeDirectory() + "/.aignals")
    }

    func testHomeOverrideViaEnvironment() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(paths.home.path, "/tmp/test-aignals")
    }

    func testSessionsDirectoryIsHomePlusSessions() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(paths.sessionsDirectory.path, "/tmp/test-aignals/sessions")
    }

    func testConfigFileIsHomePlusConfigJSON() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(paths.configFile.path, "/tmp/test-aignals/config.json")
    }

    func testSessionFilePath() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/test-aignals"])
        XCTAssertEqual(
            paths.sessionFile(id: "abc-123").path,
            "/tmp/test-aignals/sessions/abc-123.json"
        )
    }
}

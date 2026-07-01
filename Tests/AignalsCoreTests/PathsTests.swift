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

    func test_quotesFile_is_quotes_json_under_home() {
        let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/aignals-test-home"])
        XCTAssertEqual(paths.quotesFile.path, "/tmp/aignals-test-home/quotes.json")
    }

    func test_stopwatch_and_worklog_paths() {
        let p = Paths(environment: ["AIGNALS_HOME": "/tmp/aignals-sw"])
        XCTAssertEqual(p.stopwatchStateFile.path, "/tmp/aignals-sw/stopwatch-state.json")
        XCTAssertEqual(p.worklogFile.path, "/tmp/aignals-sw/worklog.json")
    }
}

extension PathsTests {
    func testEnsureDirectoriesCreatesMissingPathsWithMode0700() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-paths-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let paths = Paths(environment: ["AIGNALS_HOME": temp.path])
        try paths.ensureDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.home.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.sessionsDirectory.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: paths.home.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(perms & 0o777, 0o700)
    }

    func testEnsureDirectoriesIsIdempotent() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-paths-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let paths = Paths(environment: ["AIGNALS_HOME": temp.path])
        try paths.ensureDirectories()
        try paths.ensureDirectories()  // should not throw
    }
}

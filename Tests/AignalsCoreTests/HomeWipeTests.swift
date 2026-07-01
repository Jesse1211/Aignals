import XCTest
@testable import AignalsCore

final class HomeWipeTests: XCTestCase {
    private func tempHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
    }

    func test_wipe_keeping_preserves_named_file_and_removes_rest() throws {
        let fm = FileManager.default
        let home = tempHome()
        try fm.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: home.appendingPathComponent("quotes.json"))
        try Data("gone".utf8).write(to: home.appendingPathComponent("config.json"))

        HomeWipe.wipe(home: home, keeping: ["quotes.json"], fileManager: fm)

        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("quotes.json").path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("config.json").path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("sessions").path))
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("quotes.json")), "keep")
    }

    func test_wipe_keeping_nothing_removes_home() {
        let fm = FileManager.default
        let home = tempHome()
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: home.appendingPathComponent("quotes.json"))

        HomeWipe.wipe(home: home, keeping: [], fileManager: fm)

        XCTAssertFalse(fm.fileExists(atPath: home.path))
    }

    func test_wipe_keeping_missing_file_is_safe() {
        let fm = FileManager.default
        let home = tempHome()
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)

        HomeWipe.wipe(home: home, keeping: ["quotes.json"], fileManager: fm)

        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("config.json").path))
    }
}

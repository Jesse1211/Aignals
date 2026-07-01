import XCTest
@testable import AignalsCore

final class StopwatchStateStoreTests: XCTestCase {
    private func tmp() -> Paths {
        Paths(environment: ["AIGNALS_HOME":
            FileManager.default.temporaryDirectory.appendingPathComponent("sw-\(UUID().uuidString)").path])
    }
    func test_save_then_reload() {
        let p = tmp()
        let store = StopwatchStateStore(paths: p)
        store.save(StopwatchSnapshot(phase: .running, day: "2026-07-01",
                                     accumulatedSeconds: 10, currentSegmentStart: Date(timeIntervalSince1970: 5)))
        let fresh = StopwatchStateStore(paths: p)
        XCTAssertEqual(fresh.snapshot.phase, .running)
        XCTAssertEqual(fresh.snapshot.accumulatedSeconds, 10)
    }
    func test_missing_is_idle() {
        XCTAssertEqual(StopwatchStateStore(paths: tmp()).snapshot, .idle)
    }
    func test_corrupt_is_idle() throws {
        let p = tmp(); try p.ensureDirectories()
        try Data("garbage".utf8).write(to: p.stopwatchStateFile)
        XCTAssertEqual(StopwatchStateStore(paths: p).snapshot, .idle)
    }
}

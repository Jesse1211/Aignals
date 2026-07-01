import XCTest
@testable import AignalsCore

final class QuoteStoreTests: XCTestCase {
    private func tempPaths() -> Paths {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qs-\(UUID().uuidString)")
        return Paths(environment: ["AIGNALS_HOME": dir.path])
    }

    func test_save_appends_and_persists() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(store.saved.map(\.text), ["A"])
        XCTAssertEqual(QuoteStore(paths: paths).saved.map(\.text), ["A"])
    }

    func test_save_dedups_by_text() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        store.save(Quote(text: "A", author: "y"), at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(store.saved.count, 1)
    }

    func test_saved_is_newest_first() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "old", author: "x"), at: Date(timeIntervalSince1970: 10))
        store.save(Quote(text: "new", author: "x"), at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(store.saved.map(\.text), ["new", "old"])
    }

    func test_delete_removes_by_text() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        store.delete(text: "A")
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertFalse(QuoteStore(paths: paths).isSaved("A"))
    }

    func test_corrupt_file_loads_as_empty() throws {
        let paths = tempPaths()
        try paths.ensureDirectories()
        try Data("not json".utf8).write(to: paths.quotesFile)
        XCTAssertTrue(QuoteStore(paths: paths).saved.isEmpty)
    }

    func test_isSaved_reflects_state() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        XCTAssertFalse(store.isSaved("A"))
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(store.isSaved("A"))
    }
}

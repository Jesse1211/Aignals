import XCTest
@testable import AignalsCore

final class OverrideStoreTests: XCTestCase {
    private func tmpHome() throws -> Paths {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-overrides-\(UUID().uuidString)")
        let paths = Paths(environment: ["AIGNALS_HOME": dir.path])
        try paths.ensureDirectories()
        return paths
    }

    func testDefaultsWhenFileMissing() throws {
        let store = OverrideStore(paths: try tmpHome())
        XCTAssertNil(store.override(for: "s1"))
        XCTAssertTrue(store.overrides.isEmpty)
    }

    func testNameOrderPinnedRoundTripAcrossReload() throws {
        let paths = try tmpHome()
        let store = OverrideStore(paths: paths)
        store.setName("My Session", for: "s1")
        store.setOrder(3, for: "s1")
        store.setPinned(true, for: "s1")

        let reload = OverrideStore(paths: paths)
        let ov = reload.override(for: "s1")
        XCTAssertEqual(ov?.name, "My Session")
        XCTAssertEqual(ov?.order, 3)
        XCTAssertEqual(ov?.pinned, true)
    }

    func testSetPinnedTrueThenFalse() throws {
        let paths = try tmpHome()
        let store = OverrideStore(paths: paths)
        store.setPinned(true, for: "s1")
        XCTAssertEqual(store.override(for: "s1")?.pinned, true)
        store.setPinned(false, for: "s1")
        XCTAssertEqual(store.override(for: "s1")?.pinned, false)

        let reload = OverrideStore(paths: paths)
        XCTAssertEqual(reload.override(for: "s1")?.pinned, false)
    }

    func testRemoveDropsEntry() throws {
        let paths = try tmpHome()
        let store = OverrideStore(paths: paths)
        store.setName("X", for: "s1")
        store.setName("Y", for: "s2")
        store.remove(for: "s1")

        XCTAssertNil(store.override(for: "s1"))
        XCTAssertEqual(store.override(for: "s2")?.name, "Y")

        let reload = OverrideStore(paths: paths)
        XCTAssertNil(reload.override(for: "s1"))
        XCTAssertEqual(reload.override(for: "s2")?.name, "Y")
    }

    func testPruneDropsOrphansKeepsListed() throws {
        let paths = try tmpHome()
        let store = OverrideStore(paths: paths)
        store.setName("A", for: "s1")
        store.setName("B", for: "s2")
        store.setName("C", for: "s3")

        store.prune(keepingIDs: ["s1", "s3"])

        XCTAssertNotNil(store.override(for: "s1"))
        XCTAssertNil(store.override(for: "s2"))
        XCTAssertNotNil(store.override(for: "s3"))

        let reload = OverrideStore(paths: paths)
        XCTAssertNotNil(reload.override(for: "s1"))
        XCTAssertNil(reload.override(for: "s2"))
        XCTAssertNotNil(reload.override(for: "s3"))
    }

    func testMalformedFileFallsBackToEmpty() throws {
        let paths = try tmpHome()
        try Data("not json".utf8).write(to: paths.overridesFile)
        let store = OverrideStore(paths: paths)
        XCTAssertTrue(store.overrides.isEmpty)
        XCTAssertNil(store.override(for: "s1"))
    }

    func testWritesAreAtomicNoTmpLeftover() throws {
        let paths = try tmpHome()
        let store = OverrideStore(paths: paths)
        store.setName("X", for: "s1")
        store.setOrder(1, for: "s1")
        store.setPinned(true, for: "s1")
        store.remove(for: "s1")

        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: paths.home.path)
        let leftovers = contents.filter { $0.contains(".tmp.") || $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "found tmp leftovers: \(leftovers)")
    }

    func testHonorsAignalsHomeViaPaths() throws {
        let paths = try tmpHome()
        let store = OverrideStore(paths: paths)
        store.setName("Z", for: "s1")

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.overridesFile.path))
        XCTAssertEqual(paths.overridesFile.deletingLastPathComponent().path, paths.home.path)
        XCTAssertEqual(paths.overridesFile.lastPathComponent, "overrides.json")
    }
}

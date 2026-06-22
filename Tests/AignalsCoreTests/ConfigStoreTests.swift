import XCTest
@testable import AignalsCore

final class ConfigStoreTests: XCTestCase {
    private func tmpHome() throws -> Paths {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-config-\(UUID().uuidString)")
        let paths = Paths(environment: ["AIGNALS_HOME": dir.path])
        try paths.ensureDirectories()
        return paths
    }

    func testDefaultsWhenFileMissing() throws {
        let store = ConfigStore(paths: try tmpHome())
        XCTAssertEqual(store.config, .default)
    }

    func testRoundtrip() throws {
        let paths = try tmpHome()
        let store = ConfigStore(paths: paths)
        var c = store.config
        c.launchAtLogin = true
        c.dismissedInstallPrompt = true
        store.save(c)

        let reload = ConfigStore(paths: paths)
        XCTAssertEqual(reload.config.launchAtLogin, true)
        XCTAssertEqual(reload.config.dismissedInstallPrompt, true)
    }

    func testMalformedFileFallsBackToDefaults() throws {
        let paths = try tmpHome()
        try Data("not json".utf8).write(to: paths.configFile)
        let store = ConfigStore(paths: paths)
        XCTAssertEqual(store.config, .default)
    }
}

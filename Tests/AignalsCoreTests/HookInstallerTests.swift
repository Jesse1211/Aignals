import XCTest
@testable import AignalsCore

final class HookInstallerTests: XCTestCase {
    private func tmpFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hi-\(UUID().uuidString).json")
    }

    func testMergeIntoEmptyFile() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        try installer.install(into: file)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["SessionStart"])
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertNotNil(hooks["Stop"])
        XCTAssertNotNil(hooks["SessionEnd"])
    }

    func testMergePreservesUnrelatedHooks() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "user-bash-watch"]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted)
            .write(to: file)

        let installer = HookInstaller()
        try installer.install(into: file)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let pretool = (json["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        // user's entry preserved
        XCTAssertTrue(pretool.contains { ($0["matcher"] as? String) == "Bash" })
        // aignals entry added
        XCTAssertTrue(pretool.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String) == "aignals-hook on-pretool" }
        })
    }

    func testInstallIsIdempotent() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        try installer.install(into: file)
        try installer.install(into: file)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let sessionStart = (json["hooks"] as! [String: Any])["SessionStart"] as! [[String: Any]]
        let count = sessionStart.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { ($0["command"] as? String) == "aignals-hook on-sessionstart" }
            .count
        XCTAssertEqual(count, 1)
    }

    func testDetectsExistingInstallation() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        XCTAssertFalse(installer.isInstalled(in: file))
        try installer.install(into: file)
        XCTAssertTrue(installer.isInstalled(in: file))
    }

    func testMalformedExistingFileThrows() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        let installer = HookInstaller()
        XCTAssertThrowsError(try installer.install(into: file))
    }
}

import XCTest
@testable import AignalsCore

final class HookInstallerTests: XCTestCase {
    private func tmpFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hi-\(UUID().uuidString).json")
    }

    /// Returns every `command` string registered under the given event.
    private func commands(in json: [String: Any], event: String) -> [String] {
        guard let hooks = json["hooks"] as? [String: Any],
              let arr = hooks[event] as? [[String: Any]] else { return [] }
        return arr.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
    }

    private func readJSON(_ file: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    }

    func testMergeIntoEmptyFile() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        try installer.install(into: file)

        let json = try readJSON(file)
        // Every registered event's command must be present.
        for def in HookInstaller.events {
            XCTAssertTrue(commands(in: json, event: def.event).contains(def.command),
                          "missing command \(def.command) under event \(def.event)")
        }
    }

    func testAllNewEventsPresent() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try HookInstaller().install(into: file)
        let json = try readJSON(file)

        let expected: [(String, String)] = [
            ("SessionStart",     "aignals-hook on-sessionstart"),
            ("UserPromptSubmit", "aignals-hook on-prompt"),
            ("PreToolUse",       "aignals-hook on-pretool"),
            ("Notification",     "aignals-hook on-permission"),
            ("PostToolUse",      "aignals-hook on-posttool"),
            ("PermissionDenied", "aignals-hook on-permission-denied"),
            ("Notification",     "aignals-hook on-idle"),
            ("Stop",             "aignals-hook on-stop"),
            ("SessionEnd",       "aignals-hook on-sessionend"),
        ]
        for (event, command) in expected {
            XCTAssertTrue(commands(in: json, event: event).contains(command),
                          "expected \(command) under \(event)")
        }
    }

    func testBothNotificationEntriesPresentWithMatchers() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try HookInstaller().install(into: file)
        let json = try readJSON(file)

        let notifications = (json["hooks"] as! [String: Any])["Notification"] as! [[String: Any]]
        // Both subcommands present.
        XCTAssertTrue(commands(in: json, event: "Notification").contains("aignals-hook on-permission"))
        XCTAssertTrue(commands(in: json, event: "Notification").contains("aignals-hook on-idle"))

        // Each Notification entry is disambiguated by its notification_type matcher.
        func matcher(forCommand command: String) -> String? {
            for entry in notifications {
                let inner = (entry["hooks"] as? [[String: Any]]) ?? []
                if inner.contains(where: { ($0["command"] as? String) == command }) {
                    return entry["matcher"] as? String
                }
            }
            return nil
        }
        XCTAssertEqual(matcher(forCommand: "aignals-hook on-permission"), "permission_prompt")
        XCTAssertEqual(matcher(forCommand: "aignals-hook on-idle"), "idle_prompt")
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

        let json = try readJSON(file)
        let pretool = (json["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        // user's entry preserved
        XCTAssertTrue(pretool.contains { ($0["matcher"] as? String) == "Bash" })
        XCTAssertTrue(commands(in: json, event: "PreToolUse").contains("user-bash-watch"))
        // aignals entry added
        XCTAssertTrue(commands(in: json, event: "PreToolUse").contains("aignals-hook on-pretool"))
    }

    func testInstallIsIdempotent() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        try installer.install(into: file)
        try installer.install(into: file)

        let json = try readJSON(file)
        // No event's command may be duplicated by a second install.
        for def in HookInstaller.events {
            let count = commands(in: json, event: def.event)
                .filter { $0 == def.command }
                .count
            XCTAssertEqual(count, 1, "command \(def.command) duplicated under \(def.event)")
        }
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

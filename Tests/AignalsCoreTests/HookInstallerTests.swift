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

    /// H2 regression: a hook installed with an ABSOLUTE path
    /// (e.g. "/Users/x/.local/bin/aignals-hook on-stop") must be recognized as
    /// already-present, so re-installing does NOT append a duplicate bare-command
    /// entry. Before the suffix-match fix, mergeEvent compared the full string and
    /// appended a second entry. Verify exactly one Stop hook command afterwards.
    func testReinstallOverAbsolutePathDoesNotDuplicate() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let absolute = "/Users/x/.local/bin/aignals-hook on-stop"
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": absolute]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted).write(to: file)

        let installer = HookInstaller()
        // An absolute-path Stop hook should already read as installed for that command.
        try installer.install(into: file)

        let json = try readJSON(file)
        let stopCommands = commands(in: json, event: "Stop")
        // The absolute entry is preserved and NO bare "aignals-hook on-stop" was added.
        XCTAssertTrue(stopCommands.contains(absolute), "absolute-path entry must be preserved")
        XCTAssertFalse(stopCommands.contains("aignals-hook on-stop"),
                       "must not append a duplicate bare-command entry")
        XCTAssertEqual(stopCommands.count, 1, "exactly one Stop hook command expected, got \(stopCommands)")
    }

    /// H2: isInstalled must treat an absolute-path entry as installed (suffix match).
    func testIsInstalledRecognizesAbsolutePathEntries() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        // Build a fully-installed file, then rewrite every command to an absolute path.
        try HookInstaller().install(into: file)
        var json = try readJSON(file)
        var hooks = json["hooks"] as! [String: Any]
        for (event, value) in hooks {
            guard var arr = value as? [[String: Any]] else { continue }
            for i in arr.indices {
                guard var inner = arr[i]["hooks"] as? [[String: Any]] else { continue }
                for j in inner.indices {
                    if let c = inner[j]["command"] as? String {
                        inner[j]["command"] = "/abs/prefix/" + c
                    }
                }
                arr[i]["hooks"] = inner
            }
            hooks[event] = arr
        }
        json["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        XCTAssertTrue(HookInstaller().isInstalled(in: file),
                      "absolute-path commands must still report installed")
    }

    /// H3 regression: a Notification entry whose command is present but whose
    /// `matcher` is WRONG (or missing) must report isInstalled == false, because
    /// Claude Code routes Notification hooks by notification_type — a mis-routed
    /// entry would never fire. The two variants (permission_prompt / idle_prompt)
    /// must be distinguished by matcher, not command alone.
    func testWrongNotificationMatcherReportsNotInstalled() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        // Fully install, then corrupt ONLY the on-idle Notification entry's matcher.
        try HookInstaller().install(into: file)
        var json = try readJSON(file)
        var hooks = json["hooks"] as! [String: Any]
        var notifications = hooks["Notification"] as! [[String: Any]]
        for i in notifications.indices {
            let inner = (notifications[i]["hooks"] as? [[String: Any]]) ?? []
            if inner.contains(where: { ($0["command"] as? String) == "aignals-hook on-idle" }) {
                notifications[i]["matcher"] = "wrong_type"   // should be idle_prompt
            }
        }
        hooks["Notification"] = notifications
        json["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        XCTAssertFalse(HookInstaller().isInstalled(in: file),
                       "a Notification entry with the wrong matcher must report not-installed")
    }

    /// H3: a missing matcher on a Notification entry must also report not-installed.
    func testMissingNotificationMatcherReportsNotInstalled() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try HookInstaller().install(into: file)
        var json = try readJSON(file)
        var hooks = json["hooks"] as! [String: Any]
        var notifications = hooks["Notification"] as! [[String: Any]]
        for i in notifications.indices {
            let inner = (notifications[i]["hooks"] as? [[String: Any]]) ?? []
            if inner.contains(where: { ($0["command"] as? String) == "aignals-hook on-permission" }) {
                notifications[i].removeValue(forKey: "matcher")
            }
        }
        hooks["Notification"] = notifications
        json["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        XCTAssertFalse(HookInstaller().isInstalled(in: file),
                       "a Notification entry with a missing matcher must report not-installed")
    }

    // MARK: - C1: absolute-path install (root-cause fix)

    /// Installing with an absolute `hookPath` must write ABSOLUTE-path commands
    /// ("/abs/aignals-hook on-<sub>"), not the bare PATH-dependent form — so the
    /// hooks fire regardless of the hook shell's PATH.
    func testInstallWithAbsoluteHookPathWritesAbsoluteCommands() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let abs = "/Users/x/.local/bin/aignals-hook"
        try HookInstaller().install(into: file, hookPath: abs)

        let json = try readJSON(file)
        for (event, sub, _) in HookInstaller.eventSubcommands {
            let expected = "\(abs) \(sub)"
            XCTAssertTrue(commands(in: json, event: event).contains(expected),
                          "expected absolute command \(expected) under \(event); got \(commands(in: json, event: event))")
            // And NOT the bare form.
            XCTAssertFalse(commands(in: json, event: event).contains("aignals-hook \(sub)"),
                           "bare command for \(sub) must not be written when an absolute path is given")
        }
    }

    /// After an absolute-path install, `isInstalled` must report true (suffix
    /// match recognizes the absolute commands).
    func testIsInstalledRecognizesAbsoluteInstall() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try HookInstaller().install(into: file, hookPath: "/opt/aignals/aignals-hook")
        XCTAssertTrue(HookInstaller().isInstalled(in: file),
                      "an absolute-path install must report installed")
    }

    /// The bare-form default API must still work and write bare commands (back
    /// compat — existing tests and dev/unbundled flow depend on it).
    func testBareDefaultStillWritesBareCommands() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try HookInstaller().install(into: file)           // default, no path
        try HookInstaller().install(into: file, hookPath: nil)  // explicit nil
        let json = try readJSON(file)
        for def in HookInstaller.events {
            XCTAssertTrue(commands(in: json, event: def.event).contains(def.command),
                          "bare default must still write \(def.command)")
        }
    }

    /// Re-installing the absolute form over an existing bare install must NOT
    /// duplicate: the same " on-<sub>" hook already present should be left alone
    /// regardless of program-token form (idempotent across forms).
    func testAbsoluteReinstallOverBareIsIdempotent() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try HookInstaller().install(into: file)                              // bare
        try HookInstaller().install(into: file, hookPath: "/abs/aignals-hook") // absolute over bare

        let json = try readJSON(file)
        // Stop appears exactly once (no duplicate from the cross-form reinstall).
        let stop = commands(in: json, event: "Stop")
        XCTAssertEqual(stop.count, 1, "Stop hook must not be duplicated across forms, got \(stop)")
    }

    func testMalformedExistingFileThrows() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        let installer = HookInstaller()
        XCTAssertThrowsError(try installer.install(into: file))
    }
}

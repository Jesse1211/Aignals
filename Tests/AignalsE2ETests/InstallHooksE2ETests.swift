import XCTest
@testable import AignalsCore

@MainActor
final class InstallHooksE2ETests: XCTestCase {

    // Case 13: phase-09 implemented HookInstaller, so the gate is removed.
    func test_case13_installHooksMergeIdempotent() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "user-bash-watch"]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted).write(to: file)

        let installer = HookInstaller()
        try installer.install(into: file)
        try installer.install(into: file)  // idempotent

        XCTAssertTrue(installer.isInstalled(in: file))
        let data = try Data(contentsOf: file)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let pretool = (root["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        XCTAssertTrue(pretool.contains { ($0["matcher"] as? String) == "Bash" })
    }

    func test_case14_hookExitsZeroWhenJqMissing() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-jq-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let hookBinary = Harness.repoRoot
            .appendingPathComponent("CLI/aignals-hook/aignals-hook")

        // Restrict PATH to the system bin dirs so bash + coreutils (mkdir, cat,
        // mv, date, basename) still resolve, but Homebrew's jq — installed only
        // in /opt/homebrew/bin (arm64) or /usr/local/bin (Intel) — is excluded.
        // This isolates the "jq missing" condition without breaking the shell.
        let jqlessPath = "/usr/bin:/bin"

        // Sanity-guard: if jq somehow lives on the restricted PATH, the test's
        // premise is void — skip rather than assert a false positive.
        try XCTSkipIf(
            FileManager.default.isExecutableFile(atPath: "/usr/bin/jq")
                || FileManager.default.isExecutableFile(atPath: "/bin/jq"),
            "jq present on system PATH; cannot simulate jq-missing")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [
            "-c",
            "echo '{\"session_id\":\"x\",\"cwd\":\"/p\"}' | \"\(hookBinary.path)\" on-sessionstart",
        ]
        p.environment = [
            "PATH": jqlessPath,
            "AIGNALS_HOME": tmp.path,
            "HOME": NSHomeDirectory(),
        ]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }
}

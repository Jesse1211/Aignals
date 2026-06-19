import XCTest
@testable import AignalsCore

@MainActor
final class InstallHooksE2ETests: XCTestCase {

    // Case 13 lands in phase-09 (InstallHooksCommand). Until then it's skipped so
    // CI stays green; phase-09 flips AIGNALS_PHASE9_DONE=1 in the workflow to unskip.
    func test_case13_installHooksMergeIdempotent() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AIGNALS_PHASE9_DONE"] == "1",
            "InstallHooks tests are gated until phase-09 ships")
        XCTFail("phase-09 must implement InstallHooksCommand and flip the gate env var")
    }

    func test_case14_hookExitsZeroWhenJqMissing() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-jq-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let hookBinary = Harness.repoRoot
            .appendingPathComponent("CLI/aignals-hook/aignals-hook")

        // A real-but-empty directory as the only PATH entry → jq is unfindable
        // regardless of /opt/homebrew/bin or /usr/local/bin on the runner.
        let emptyPathDir = tmp.appendingPathComponent("nojq")
        try FileManager.default.createDirectory(at: emptyPathDir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [
            "-c",
            "echo '{\"session_id\":\"x\",\"cwd\":\"/p\"}' | \"\(hookBinary.path)\" on-sessionstart",
        ]
        p.environment = [
            "PATH": emptyPathDir.path,
            "AIGNALS_HOME": tmp.path,
            "HOME": NSHomeDirectory(),
        ]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }
}

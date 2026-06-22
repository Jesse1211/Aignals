import Foundation
@testable import AignalsCore

/// End-to-end harness: boots a real SessionStore + FSEventsWatcher + PIDSweeper
/// against a temp `AIGNALS_HOME`, and can invoke the real `aignals-hook` CLI
/// as a subprocess with constructed stdin payloads (spec §9.4).
@MainActor
final class Harness {
    let paths: Paths
    let store: SessionStore
    let watcher: FSEventsWatcher
    let sweeper: PIDSweeper
    let hookBinary: URL

    init(liveness: PIDLiveness = SystemPIDLiveness()) throws {
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-e2e-\(UUID().uuidString)", isDirectory: true)
        self.paths = Paths(environment: ["AIGNALS_HOME": tempBase.path])
        try paths.ensureDirectories()

        self.store = SessionStore()
        self.watcher = FSEventsWatcher(directory: paths.sessionsDirectory, store: store)
        self.sweeper = PIDSweeper(
            sessionsDirectory: paths.sessionsDirectory,
            store: store,
            liveness: liveness
        )
        self.sweeper.interval = 0.5     // fast for tests
        // Large enough that a live-PID session is never swept by the mtime
        // backstop mid-test (lifecycle tests can run >1s); the mtime-backstop
        // test opts into a short window locally via `sweeper.staleAfter`.
        self.sweeper.staleAfter = 30.0

        // Locate the bundled CLI relative to repo root.
        self.hookBinary = Harness.repoRoot
            .appendingPathComponent("CLI/aignals-hook/aignals-hook")

        watcher.start()
        sweeper.start()
    }

    /// Repo root, derived from this file's location:
    /// Tests/AignalsE2ETests/Helpers/Harness.swift → up 4 levels.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Helpers
        .deletingLastPathComponent() // AignalsE2ETests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo

    /// Call from test tearDown — avoids `deinit` racing with @MainActor cleanup.
    func cleanup() {
        watcher.stop()
        sweeper.stop()
        // Restore perms in case a test left the dir at 0o000.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: paths.sessionsDirectory.path)
        try? FileManager.default.removeItem(at: paths.home)
    }

    @discardableResult
    func runHook(_ subcommand: String, payload: String) throws -> Int32 {
        let p = Process()
        // Invoke the binary directly so paths with spaces don't need shell quoting.
        p.executableURL = hookBinary
        p.arguments = [subcommand]
        var env = ProcessInfo.processInfo.environment
        env["AIGNALS_HOME"] = paths.home.path
        p.environment = env

        let pipe = Pipe()
        p.standardInput = pipe
        try p.run()
        pipe.fileHandleForWriting.write(Data(payload.utf8))
        try pipe.fileHandleForWriting.close()
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Await a derived store condition, polling on the main actor.
    /// (We poll rather than consume `store.changes` because that AsyncStream
    /// is single-consumer and the watcher/sweeper feed it asynchronously.)
    func waitUntil(timeout: TimeInterval = 3.0, _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    /// old `.running` (sessions present) → nonzero total.
    func waitForRunning(timeout: TimeInterval = 3.0) async -> Bool {
        await waitUntil(timeout: timeout) { store.statusCounts.total > 0 }
    }

    /// old `.idle` (no sessions) → all-zero counts.
    func waitForIdle(timeout: TimeInterval = 3.0) async -> Bool {
        await waitUntil(timeout: timeout) { store.statusCounts.isEmpty }
    }

    /// old `.error` → hasError == true.
    func waitForError(timeout: TimeInterval = 3.0) async -> Bool {
        await waitUntil(timeout: timeout) { store.hasError }
    }
}

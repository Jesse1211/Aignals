import Foundation
import AppKit
import AignalsCore

@MainActor
@Observable
final class AppViewModel {
    let paths: Paths
    let store: SessionStore

    /// App-owned per-session user preferences side-car (name/order/pinned),
    /// `~/.aignals/overrides.json` (ADR-12). Lives alongside `ConfigStore` and
    /// uses the same `paths`. Merged onto sessions at read time (INV-9).
    let overrideStore: OverrideStore

    /// Bumped on every override mutation so SwiftUI re-derives `sortedSessions`
    /// (`OverrideStore` is not `@Observable`).
    private var overridesVersion = 0

    private let configStore: ConfigStore
    private let watcher: FSEventsWatcher
    private let sweeper: PIDSweeper

    init() {
        let paths = Paths()
        try? paths.ensureDirectories()
        let store = SessionStore()

        self.paths = paths
        self.store = store
        self.configStore = ConfigStore(paths: paths)
        self.overrideStore = OverrideStore(paths: paths)
        self.watcher = FSEventsWatcher(directory: paths.sessionsDirectory, store: store)
        self.sweeper = PIDSweeper(sessionsDirectory: paths.sessionsDirectory, store: store)

        if #available(macOS 13.0, *) {
            try? LaunchAtLogin.set(configStore.config.launchAtLogin) // re-apply on launch
        }

        watcher.start()
        sweeper.start()
        seedInitialState()
    }

    /// Load any session files already on disk so the UI reflects current state
    /// before the first FSEvents callback arrives.
    private func seedInitialState() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: paths.sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            store.loadFromDisk(path: url)
        }
    }

    func revealAignalsHome() {
        NSWorkspace.shared.open(paths.home)
    }
}

// MARK: - Session overrides (name / order / pin) — ADR-15/16/18/19, INV-11

extension AppViewModel {
    /// The override record for a session, if any.
    func override(for session: Session) -> SessionOverride? {
        _ = overridesVersion // establish observation dependency
        return overrideStore.override(for: session.sessionID)
    }

    /// Effective display name = `override.name ?? projectName` (ADR-18).
    /// An empty/whitespace override name falls back to the project name.
    func displayName(for session: Session) -> String {
        if let name = overrideStore.override(for: session.sessionID)?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return session.projectName
    }

    func isPinned(_ session: Session) -> Bool {
        overrideStore.override(for: session.sessionID)?.pinned ?? false
    }

    /// Session list in display order (INV-11 / ADR-16 / ADR-19):
    /// 1. PINNED sessions first — newest pinned (by `startedAt`) on top.
    /// 2. then sessions carrying an explicit `override.order`, ascending by it.
    /// 3. then the remaining (unordered) sessions newest-first by `startedAt`,
    ///    so a brand-new session appears at the TOP of its group.
    var sortedSessions: [Session] {
        _ = overridesVersion // re-derive when overrides change
        let sessions = store.sessions

        func ov(_ s: Session) -> SessionOverride? { overrideStore.override(for: s.sessionID) }

        return sessions.sorted { a, b in
            let oa = ov(a), ob = ov(b)
            let pa = oa?.pinned ?? false
            let pb = ob?.pinned ?? false

            // 1. pinned first; within pinned, newest on top.
            if pa != pb { return pa }
            if pa && pb { return a.startedAt > b.startedAt }

            // 2. explicit order beats unordered; ascending by order.
            let orderA = oa?.order
            let orderB = ob?.order
            switch (orderA, orderB) {
            case let (.some(x), .some(y)):
                if x != y { return x < y }
                return a.startedAt > b.startedAt
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                // 3. unordered: newest-first so a new session lands on top.
                return a.startedAt > b.startedAt
            }
        }
    }

    func setName(_ name: String?, for session: Session) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideStore.setName((trimmed?.isEmpty == true) ? nil : trimmed, for: session.sessionID)
        overridesVersion &+= 1
    }

    func setPinned(_ pinned: Bool, for session: Session) {
        overrideStore.setPinned(pinned, for: session.sessionID)
        overridesVersion &+= 1
    }

    /// Persist a new explicit order for the given session ordering (ADR-16/INV-11).
    /// Assigns sequential indices so the on-screen order round-trips.
    func setOrder(_ orderedSessions: [Session]) {
        for (index, s) in orderedSessions.enumerated() {
            overrideStore.setOrder(index, for: s.sessionID)
        }
        overridesVersion &+= 1
    }

    /// Dismiss a session: remove it from the store AND prune its override (ADR-15/INV-10).
    func removeSession(_ session: Session) {
        store.remove(id: session.sessionID)
        overrideStore.remove(for: session.sessionID)
        overridesVersion &+= 1
    }
}

extension AppViewModel {
    var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    func installClaudeHooks() throws {
        try HookInstaller().install(into: claudeSettingsURL)
    }

    var claudeHooksInstalled: Bool {
        HookInstaller().isInstalled(in: claudeSettingsURL)
    }
}

extension AppViewModel {
    /// The `aignals-hook` script embedded in the app bundle (phase-11).
    var bundledHookURL: URL? {
        Bundle.main.url(forResource: "aignals-hook", withExtension: nil)
    }

    /// Where we symlink the CLI so it lands on the user's PATH (no sudo).
    var hookSymlinkURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/bin/aignals-hook")
    }

    var hookIsLinked: Bool {
        FileManager.default.fileExists(atPath: hookSymlinkURL.path)
    }

    func linkHookCLI() throws {
        guard let src = bundledHookURL else { return }
        let dir = hookSymlinkURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: hookSymlinkURL)
        try FileManager.default.createSymbolicLink(at: hookSymlinkURL, withDestinationURL: src)
    }
}

extension AppViewModel {
    var config: AignalsConfig {
        get { configStore.config }
        set {
            configStore.save(newValue)
            if #available(macOS 13.0, *) {
                try? LaunchAtLogin.set(newValue.launchAtLogin)
            }
        }
    }

    var launchAtLogin: Bool {
        get { config.launchAtLogin }
        set { var c = config; c.launchAtLogin = newValue; config = c }
    }
}

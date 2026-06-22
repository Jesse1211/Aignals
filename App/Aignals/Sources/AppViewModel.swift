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

        // Prune orphaned overrides whenever the session set changes (covers the
        // normal SessionEnd path: FSEvents deletes the file → store.remove, which
        // never touches overrides). INV-10. (ADR-12)
        let stream = store.changes
        Task { @MainActor [weak self] in
            for await _ in stream { self?.pruneOrphanedOverrides() }
        }
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

    /// Session list in display order (INV-11 / ADR-16 / ADR-19). The pure
    /// ordering rule lives in `AignalsCore.SessionOrdering` so it is unit-tested
    /// outside the (untestable) view-model. Key behaviors:
    ///   1. pinned sessions first; pinned rows honor a drag-set `order` among
    ///      themselves (so a pinned reorder persists), falling back to
    ///      `startedAt`;
    ///   2. an UNORDERED (brand-new) session sorts to the TOP of its group even
    ///      after other sessions were ordered by a drag (ADR-16).
    var sortedSessions: [Session] {
        _ = overridesVersion // re-derive when overrides change
        return SessionOrdering.sorted(store.sessions) { s in
            guard let ov = overrideStore.override(for: s.sessionID) else { return nil }
            return OrderingOverride(order: ov.order, pinned: ov.pinned)
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

    /// Persist a new explicit order for the given on-screen ordering
    /// (ADR-16/INV-11). A drag never moves a row between the pinned and unpinned
    /// groups (rule 1 — pinned-first — would immediately override that anyway),
    /// so we stamp sequential indices WITHIN each group, in the order the rows
    /// currently appear. This keeps the persisted result coherent with the
    /// visible drop and lets two pinned rows be reordered (their `order` now
    /// participates in the sort, see `SessionOrdering`).
    ///
    /// We deliberately do NOT stamp sessions that were already orderless and
    /// stayed at the top untouched? — no: to make a drag round-trip we must give
    /// every row in the dragged group a concrete index. A brand-new session that
    /// appears AFTER this drag still has no override and therefore sorts to the
    /// top (ADR-16), which is the whole point of the orderless-on-top rule.
    func setOrder(_ orderedSessions: [Session]) {
        var index = 0
        // Stamp pinned rows first (in their displayed order), then unpinned —
        // matching the group order the sort itself uses, so indices never fight
        // the pinned-first rule.
        for s in orderedSessions where isPinned(s) {
            overrideStore.setOrder(index, for: s.sessionID)
            index += 1
        }
        index = 0
        for s in orderedSessions where !isPinned(s) {
            overrideStore.setOrder(index, for: s.sessionID)
            index += 1
        }
        overridesVersion &+= 1
    }

    /// Dismiss a session: delete its on-disk file, remove it from the store, and
    /// drop its override (ADR-15/INV-10). The file delete is essential — a gray
    /// (disconnected) session's file is left on disk by `PIDSweeper`, so without
    /// removing it the 5s sweep would re-read it and resurrect the dismissed row.
    func removeSession(_ session: Session) {
        try? FileManager.default.removeItem(at: paths.sessionFile(id: session.sessionID))
        store.remove(id: session.sessionID)
        overrideStore.remove(for: session.sessionID)
        overridesVersion &+= 1
    }

    /// Drop overrides whose session no longer exists (INV-10 orphan cleanup for
    /// the normal SessionEnd path, which deletes the file via FSEvents without
    /// touching the override). Called after the session set may have shrunk.
    func pruneOrphanedOverrides() {
        let live = Set(store.sessions.map(\.sessionID))
        overrideStore.prune(keepingIDs: live)
    }
}

extension AppViewModel {
    var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    /// Install the Claude Code hooks so the indicator actually lights up.
    ///
    /// ROOT-CAUSE FIX: previously this wrote BARE commands ("aignals-hook on-…")
    /// into settings.json. A bare command only resolves if `aignals-hook` is on
    /// the PATH the hook shell sees — which only happens if the user ALSO ran the
    /// SEPARATE "Install aignals-hook CLI" item AND that dir is on PATH. So the
    /// default first-launch flow produced settings.json with commands that
    /// silently never fired, yet reported "installed". Here we instead:
    ///   1. resolve the hook's ABSOLUTE path (linked CLI if present, else the
    ///      bundled hook), and write absolute-path commands that fire regardless
    ///      of PATH; and
    ///   2. ALSO link the bundled hook into ~/.local/bin so the CLI is available
    ///      from one action — no second click, no PATH dependency for hooks.
    /// If no absolute path can be resolved (e.g. running unbundled in dev), we
    /// fall back to the bare form rather than failing.
    func installClaudeHooks() throws {
        let hookPath = try resolveHookPathForInstall()
        try HookInstaller().install(into: claudeSettingsURL, hookPath: hookPath)
    }

    /// Resolve the absolute path to write into the hook commands. Prefers an
    /// already-linked CLI; otherwise links the bundled hook into ~/.local/bin
    /// (so the CLI is available too) and returns that. Returns `nil` only when no
    /// bundled hook exists (dev/unbundled), in which case the caller writes the
    /// bare fallback form.
    private func resolveHookPathForInstall() throws -> String? {
        // Already linked onto PATH from a prior CLI install — point at it.
        if hookIsLinked {
            return hookSymlinkURL.path
        }
        // Couple the steps: linking the bundled hook makes the CLI available AND
        // gives us a stable absolute path for the hook commands.
        if bundledHookURL != nil {
            try? linkHookCLI()
            if hookIsLinked { return hookSymlinkURL.path }
            // Linking failed (e.g. ~/.local not writable); fall back to the
            // bundled path directly so the hooks still fire.
            return bundledHookURL?.path
        }
        return nil // dev/unbundled: HookInstaller writes the bare fallback.
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

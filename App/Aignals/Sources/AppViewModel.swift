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

    /// Bumped after a hook/CLI install so SwiftUI re-derives `claudeHooksInstalled`
    /// / `hookIsLinked` immediately — those read settings.json / the filesystem,
    /// which `@Observable` can't track, so without this the "Install…" menu items
    /// wouldn't hide until the menu is reopened.
    private var installVersion = 0

    /// Bumped on every `config` mutation so SwiftUI re-derives anything reading it
    /// (e.g. `soundEnabled`, `launchAtLogin`) — `ConfigStore` is not `@Observable`,
    /// so without this, toggling global sound wouldn't update the per-row mute
    /// icons or the Launch button until the menu is reopened.
    private var configVersion = 0

    private let quoteProvider = QuoteProvider()
    private let quoteStore: QuoteStore
    private let quoteCalendar = Calendar.current

    var currentQuote: Quote?
    var isFetchingQuote = false
    private(set) var lastQuoteFetch: Date?

    /// Bumped on every saved-quote mutation so SwiftUI re-derives `savedQuotes`
    /// (`QuoteStore` is not `@Observable` — same pattern as `overridesVersion`).
    private var quotesVersion = 0

    /// Draft for the API Ninjas key field (mirrors the Feishu draft pattern):
    /// edited in place, committed to config only on Save.
    var quoteAPIKeyDraft: String = ""

    private let stopwatchEngine = StopwatchEngine()
    private let stopwatchStore: StopwatchStateStore
    private let worklogStore: WorklogStore
    private let stopwatchCalendar = Calendar.current

    /// Bumped on every stopwatch mutation so SwiftUI re-derives phase/worklog
    /// (neither store is @Observable — same pattern as overridesVersion).
    private var stopwatchVersion = 0

    private let configStore: ConfigStore
    private let watcher: FSEventsWatcher
    private let sweeper: PIDSweeper
    private let feishuClient = FeishuClient()

    /// Last Feishu send outcome surfaced to Settings: `nil` = ok/never-sent, else a
    /// short human string. Set on the main actor after each send completes.
    private(set) var lastFeishuError: String?

    /// Draft values for the Feishu card's text fields. Edited in place; committed
    /// to config only on Save (so a half-typed webhook isn't persisted). Seeded
    /// from persisted config at init and equal to config again after a Save.
    var feishuURLDraft: String = ""
    var feishuSecretDraft: String = ""
    var feishuKeywordDraft: String = ""

    /// Which Settings page the standalone window should show when next opened.
    /// `MenuContent`'s "Settings…" sets this to `.general`; the brand header sets
    /// it to `.about`. `SettingsView` syncs its selection from this on appear and
    /// on change (so it works whether the window was closed or already open).
    var settingsLandingSection: SettingsSection = .general

    // MARK: Sound playback bookkeeping (ADR-21/22/23/24)

    /// Last-known state per session id, so a change can be classified as a
    /// TRANSITION (compare to the prior value) vs. a first observation. A
    /// session id absent from this map is being seen for the first time
    /// (startup seed or adoption) and never plays a sound (ADR-22).
    private var lastKnownState: [String: SessionState] = [:]

    /// Last wall-clock instant an alert (sound or Feishu) fired for a given session
    /// id, used to throttle to at most one alert per `soundThrottle` seconds (ADR-22).
    private var lastAlertAt: [String: Date] = [:]

    /// Minimum gap between two sounds for the SAME session (ADR-22).
    private let soundThrottle: TimeInterval = 3

    init() {
        let paths = Paths()
        try? paths.ensureDirectories()
        let store = SessionStore()

        self.paths = paths
        self.store = store
        self.configStore = ConfigStore(paths: paths)
        self.overrideStore = OverrideStore(paths: paths)
        self.quoteStore = QuoteStore(paths: paths)
        self.stopwatchStore = StopwatchStateStore(paths: paths)
        self.worklogStore = WorklogStore(paths: paths)
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
        //
        // We ALSO drive sound playback off the same stream (ADR-24): on every
        // change we diff the current sessions against `lastKnownState` and play
        // an alert sound for any session that just transitioned INTO a
        // waiting state. The seed above already populated `lastKnownState`, so
        // sessions present at launch are treated as known and never fire a
        // startup sound-storm (ADR-22).
        let stream = store.changes
        Task { @MainActor [weak self] in
            for await _ in stream {
                self?.handleSessionAlerts()
                self?.pruneOrphanedOverrides()
            }
        }

        seedFeishuDrafts()
        seedQuoteDraft()
        fetchQuoteIfNeeded()
        evaluateStopwatch()
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

        // Record the seeded sessions as already-known so their first appearance
        // in `store.changes` is NOT classified as a transition — suppressing a
        // startup sound-storm (ADR-22). Sessions adopted later via a hook event
        // are likewise first observed (absent from the map) and stay silent.
        for session in store.sessions {
            lastKnownState[session.sessionID] = session.state
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

    /// Whether this session's sound is muted (ADR-20). Defaults to false.
    func isMuted(_ session: Session) -> Bool {
        _ = overridesVersion // establish observation dependency
        return overrideStore.override(for: session.sessionID)?.muted ?? false
    }

    /// Toggle a session's per-row mute (ADR-20). A muted session is skipped by
    /// the sound trigger even when global sound is on.
    func setMuted(_ muted: Bool, for session: Session) {
        overrideStore.setMuted(muted, for: session.sessionID)
        overridesVersion &+= 1
    }

    /// Whether this session will ACTUALLY make a sound: global sound on AND this
    /// session not individually muted. Drives the per-row speaker icon.
    func soundActive(for session: Session) -> Bool {
        _ = configVersion   // re-derive when global sound toggles
        _ = overridesVersion
        return soundEnabled && !isMuted(session)
    }

    /// Toggle sound for one session from its row speaker button, with the
    /// global toggle as the master switch (per the user's rule):
    ///  - If this session is currently active (audible) → mute just this session.
    ///  - If it is NOT active → make it the audible one: turn the global switch ON,
    ///    unmute this session, and mute every OTHER session (so "enable sound on
    ///    s1" while globally off yields s1 audible, others muted, global = ON).
    func toggleSound(for session: Session) {
        if soundActive(for: session) {
            setMuted(true, for: session)
            return
        }
        if !soundEnabled {
            // Global was off: turning a single session on flips the master switch
            // on, so mute every other current session to keep only this one audible.
            for other in store.sessions where other.sessionID != session.sessionID {
                overrideStore.setMuted(true, for: other.sessionID)
            }
            soundEnabled = true
        }
        overrideStore.setMuted(false, for: session.sessionID)
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
    /// Every row in the dragged group gets a concrete index so the drag
    /// round-trips. A brand-new session that appears AFTER this drag still has no
    /// override and therefore sorts to the top (ADR-16) — the whole point of the
    /// orderless-on-top rule.
    func setOrder(_ orderedSessions: [Session]) {
        // Stamp pinned rows first (in their displayed order), then unpinned —
        // matching the group order the sort itself uses, so indices never fight
        // the pinned-first rule. Each group is numbered from 0 independently.
        func stamp(_ sessions: [Session]) {
            for (index, s) in sessions.enumerated() {
                overrideStore.setOrder(index, for: s.sessionID)
            }
        }
        stamp(orderedSessions.filter { isPinned($0) })
        stamp(orderedSessions.filter { !isPinned($0) })
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

// MARK: - Session alerts: sound + Feishu (ADR-21/22/23/24, INV-13)

extension AppViewModel {
    /// Diff the current sessions against `lastKnownState` and fire alerts for any
    /// session that just TRANSITIONED INTO a waiting state. Two independent
    /// channels ride this one diff pass: a system sound (waiting_permission →
    /// "Ping", waiting_input → "Glass"; ADR-23) and a Feishu webhook message.
    ///
    /// Channel-independent gating (ADR-21/22/24, INV-13): a transition is a
    /// candidate only when
    ///   - the new state is `.waitingPermission` or `.waitingInput` (never
    ///     `.working`/`.disconnected`); AND
    ///   - the session was already KNOWN (present in `lastKnownState`) — a
    ///     first observation (startup seed or hook adoption) is silent; AND
    ///   - the state actually CHANGED from the prior value; AND
    ///   - the session is not per-row muted (mute silences BOTH channels).
    /// Each channel then opts in: sound when `config.soundEnabled`, Feishu when
    /// `config.feishuEnabled` and a webhook URL is set. A SHARED per-session
    /// throttle (`lastAlertAt`, at least `soundThrottle` seconds) is stamped once
    /// for whichever channel(s) fire, so a single transition never double-fires.
    ///
    /// `lastKnownState` is updated for EVERY current session on every call so
    /// the next diff has a fresh baseline; ids no longer present fall out via
    /// the prune pass below.
    private func handleSessionAlerts() {
        let now = Date()
        let soundOn = config.soundEnabled
        var live = Set<String>()

        for session in store.sessions {
            let id = session.sessionID
            live.insert(id)
            let previous = lastKnownState[id]
            lastKnownState[id] = session.state

            // Channel-independent gate: first observation or unchanged state → nothing,
            // and a per-session muted row sends neither channel.
            guard let previous, previous != session.state else { continue }
            guard overrideStore.override(for: id)?.muted != true else { continue }

            // Decide per channel whether it wants to fire THIS transition.
            let soundName = sound(forTransitionInto: session.state)
            let wantsSound = soundOn && soundName != nil
            let wantsFeishu = config.feishuEnabled
                && !config.feishuWebhookURL.isEmpty
                && FeishuMessage.text(displayName: displayName(for: session),
                                      state: session.state,
                                      keyword: config.feishuKeyword) != nil
            guard wantsSound || wantsFeishu else { continue }

            // Shared per-session throttle: one stamp covers both channels.
            if let last = lastAlertAt[id], now.timeIntervalSince(last) < soundThrottle {
                continue
            }
            lastAlertAt[id] = now

            if wantsSound, let soundName { Self.play(soundName) }
            if wantsFeishu,
               let text = FeishuMessage.text(displayName: displayName(for: session),
                                             state: session.state,
                                             keyword: config.feishuKeyword) {
                sendFeishu(text: text)
            }
        }

        // Forget bookkeeping for sessions that have gone away so a future
        // session reusing the id (unlikely) starts fresh, and the maps don't
        // grow unbounded.
        lastKnownState = lastKnownState.filter { live.contains($0.key) }
        lastAlertAt = lastAlertAt.filter { live.contains($0.key) }
    }

    /// The macOS system sound name for a transition INTO `state`, or `nil` for
    /// states that never alert (ADR-21: working/disconnected are silent) and for
    /// a state whose configured sound is `.none`. The 🟡/🟢 sounds are
    /// user-selectable via `config.permissionSound` / `config.inputSound`
    /// (ADR-28); defaults are Ping/Glass.
    private func sound(forTransitionInto state: SessionState) -> String? {
        switch state {
        case .waitingPermission: return config.permissionSound.systemSoundName
        case .waitingInput:      return config.inputSound.systemSoundName
        case .working, .disconnected: return nil
        }
    }

    /// Play a named macOS system sound. Prefers `NSSound(named:)`; falls back to
    /// `afplay` on the bundled `.aiff` if the named sound can't be resolved.
    private static func play(_ name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
            return
        }
        let path = "/System/Library/Sounds/\(name).aiff"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        proc.arguments = [path]
        try? proc.run()
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
        installVersion &+= 1 // re-derive claudeHooksInstalled so the item hides now
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
        _ = installVersion // re-derive after an install (settings.json isn't @Observable)
        return HookInstaller().isInstalled(in: claudeSettingsURL)
    }

    /// Full in-app uninstall (everything EXCEPT the app bundle itself — the app
    /// is running, so it can't delete itself; the UI tells the user to drag
    /// Aignals.app to the Trash). The inverse of installClaudeHooks + linkHookCLI
    /// plus a wipe of the data dir:
    ///   1. remove ONLY Aignals' hook entries from ~/.claude/settings.json
    ///      (HookInstaller.uninstall leaves all other hooks untouched);
    ///   2. remove the CLI symlink at ~/.local/bin/aignals-hook if present;
    ///   3. delete the entire ~/.aignals data dir.
    ///
    /// Only step 1 can throw (malformed settings.json → surfaces an error so the
    /// UI does NOT quit and the user can fix it). Steps 2/3 are best-effort
    /// (try?) — a missing symlink/dir is fine. We do NOT terminate here: the UI
    /// layer owns the confirm + final dialog + quit, so an error can surface
    /// first. `installVersion` is bumped so the menu re-derives its state.
    func uninstall(keepSavedData: Bool = false) throws {
        try HookInstaller().uninstall(from: claudeSettingsURL)
        if FileManager.default.fileExists(atPath: hookSymlinkURL.path) {
            try? FileManager.default.removeItem(at: hookSymlinkURL)
        }
        // Wipe ~/.aignals, optionally preserving saved data (quotes.json, and
        // future worklog.json). Best-effort.
        HomeWipe.wipe(home: paths.home,
                      keeping: keepSavedData ? ["quotes.json", "worklog.json"] : [],
                      fileManager: .default)
        installVersion &+= 1
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
        _ = installVersion // re-derive after a link (the filesystem isn't @Observable)
        return FileManager.default.fileExists(atPath: hookSymlinkURL.path)
    }

    func linkHookCLI() throws {
        guard let src = bundledHookURL else { return }
        let dir = hookSymlinkURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: hookSymlinkURL)
        try FileManager.default.createSymbolicLink(at: hookSymlinkURL, withDestinationURL: src)
        installVersion &+= 1 // re-derive hookIsLinked so the item hides now
    }
}

extension AppViewModel {
    var config: AignalsConfig {
        get {
            _ = configVersion // re-derive when config changes (ConfigStore isn't @Observable)
            return configStore.config
        }
        set {
            configStore.save(newValue)
            configVersion &+= 1
            if #available(macOS 13.0, *) {
                try? LaunchAtLogin.set(newValue.launchAtLogin)
            }
        }
    }

    var launchAtLogin: Bool {
        _ = installVersion // re-derive after enableLaunchAtLogin() so the button hides now
        return config.launchAtLogin
    }

    /// One-way enable for launch-at-login (ADR-26/INV-15). The menu shows an
    /// "Enable Launch at Login" button only while this is off; tapping it sets
    /// the flag and bumps `installVersion` so the button hides immediately
    /// (mirroring the Install-items refresh pattern). Disabling is done in
    /// System Settings.
    func enableLaunchAtLogin() {
        var c = config
        c.launchAtLogin = true
        config = c
        installVersion &+= 1
    }

    /// Global sound toggle backing (ADR-20). Reads/writes
    /// `AignalsConfig.soundEnabled` through the existing config setter.
    var soundEnabled: Bool {
        get { config.soundEnabled }
        set { var c = config; c.soundEnabled = newValue; config = c }
    }

    /// Selected theme (ADR-0810). Reads/writes `AignalsConfig.theme` through the
    /// existing config setter, which bumps `configVersion` so SwiftUI re-derives
    /// the themed UI immediately.
    var theme: Theme {
        get { config.theme }
        set { var c = config; c.theme = newValue; config = c }
    }

    /// Alert sound for 🟡 waiting-permission (ADR-28/31). Reads/writes
    /// `config.permissionSound` through the config setter (bumps `configVersion`);
    /// previews the new sound once so the choice is audible.
    var permissionSound: AlertSound {
        get { config.permissionSound }
        set {
            var c = config; c.permissionSound = newValue; config = c
            Self.preview(newValue)
        }
    }

    /// Alert sound for 🟢 waiting-input (ADR-28/31). Same pattern as
    /// `permissionSound`, backed by `config.inputSound`.
    var inputSound: AlertSound {
        get { config.inputSound }
        set {
            var c = config; c.inputSound = newValue; config = c
            Self.preview(newValue)
        }
    }

    /// Play `sound` once for selection feedback. `.none` is silent.
    private static func preview(_ sound: AlertSound) {
        if let name = sound.systemSoundName { play(name) }
    }

    /// Feishu master toggle, backed by `config.feishuEnabled` (persisted).
    var feishuEnabled: Bool {
        get { config.feishuEnabled }
        set { var c = config; c.feishuEnabled = newValue; config = c }
    }


}

// MARK: - Feishu notifications (send + test)

extension AppViewModel {
    /// Fire-and-forget POST of `text` to the configured webhook. Best-effort: on
    /// completion sets `lastFeishuError` (nil on success) so Settings can warn.
    /// Caller is responsible for all gating; this just sends.
    func sendFeishu(text: String) {
        let url = config.feishuWebhookURL
        let secret = config.feishuSecret
        guard !url.isEmpty else { return }
        let ts = Int(Date().timeIntervalSince1970)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.feishuClient.send(text: text, webhookURL: url, secret: secret, timestamp: ts)
            switch result {
            case .success:
                self.lastFeishuError = nil
            case .failure(let err):
                self.lastFeishuError = Self.describe(err)
            }
        }
    }

    /// Push today's quote to the configured Feishu bot, reusing the same tokens
    /// as session notifications. Gated: no-op when Feishu is disabled/unconfigured
    /// or when there is no real quote (currentQuote == nil ⇒ “—”). Called when the
    /// stopwatch transitions from idle to running (see `stopwatchStart`).
    func sendCurrentQuoteToFeishu() {
        guard config.feishuEnabled, !config.feishuWebhookURL.isEmpty else { return }
        guard let quote = currentQuote else { return }   // no “—”
        let author = quote.author.isEmpty ? "" : " — \(quote.author)"
        sendFeishu(text: "\(quote.text)\(author)")
    }

    /// Seed the card's draft fields from persisted config (call at init).
    func seedFeishuDrafts() {
        feishuURLDraft = config.feishuWebhookURL
        feishuSecretDraft = config.feishuSecret
        feishuKeywordDraft = config.feishuKeyword
    }

    /// True when any draft differs from the persisted value — enables Save.
    var feishuDraftDirty: Bool {
        feishuURLDraft != config.feishuWebhookURL
        || feishuSecretDraft != config.feishuSecret
        || feishuKeywordDraft != config.feishuKeyword
    }

    /// Commit the drafts to config in one persist. After this, drafts == config
    /// so `feishuDraftDirty` is false again.
    func saveFeishuDrafts() {
        var c = config
        c.feishuWebhookURL = feishuURLDraft
        c.feishuSecret = feishuSecretDraft
        c.feishuKeyword = feishuKeywordDraft
        config = c
    }

    /// Send the fixed test message using the CURRENT draft values (so the user can
    /// verify before saving). Routed through the same keyword-append rule.
    func sendFeishuTest() {
        let base = "Aignals • test — notifications are working"
        let kw = feishuKeywordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (kw.isEmpty || base.contains(kw)) ? base : base + " [\(kw)]"
        sendFeishuFromDraft(text: text)
    }

    /// Like `sendFeishu(text:)` but reads the draft URL/secret instead of config —
    /// used by the test button so unsaved edits can be verified.
    func sendFeishuFromDraft(text: String) {
        let url = feishuURLDraft
        let secret = feishuSecretDraft
        guard !url.isEmpty else { return }
        let ts = Int(Date().timeIntervalSince1970)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.feishuClient.send(text: text, webhookURL: url, secret: secret, timestamp: ts)
            switch result {
            case .success: self.lastFeishuError = nil
            case .failure(let err): self.lastFeishuError = Self.describe(err)
            }
        }
    }

    /// Map a `FeishuError` to a short UI string.
    private static func describe(_ err: FeishuError) -> String {
        switch err {
        case .transport(let m): return "Send failed: \(m)"
        case .http(let s):      return "Send failed: HTTP \(s)"
        case .feishu(let c, let m): return "Feishu rejected: \(m) (\(c))"
        }
    }
}

// MARK: - Quote coordination (fetch / refresh / save)

extension AppViewModel {
    /// Fetch on first launch or after crossing local midnight since the last fetch.
    func fetchQuoteIfNeeded(now: Date = Date()) {
        guard config.quoteEnabled else { return }       // disabled → no fetching
        if let last = lastQuoteFetch,
           !MidnightRefresher.didCrossMidnight(from: last, to: now, calendar: quoteCalendar) {
            return
        }
        refreshQuote()
    }

    /// Fetch a quote from API Ninjas using the configured key and category. On
    /// failure leaves `currentQuote` = nil so the dropdown shows a placeholder.
    /// No-op display when the key is empty or the quote card is disabled.
    func refreshQuote() {
        guard config.quoteEnabled else { return }
        let key = config.quoteAPIKey
        let category = config.quoteCategory
        isFetchingQuote = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let q = await self.quoteProvider.fetchQuote(apiKey: key, category: category)
            self.currentQuote = q
            self.lastQuoteFetch = Date()
            self.isFetchingQuote = false
        }
    }

    var quoteCategory: QuoteCategory {
        get { config.quoteCategory }
        set { var c = config; c.quoteCategory = newValue; config = c }
    }

    /// Master toggle for the daily-quote card. Turning it on fetches immediately;
    /// off clears the current quote so nothing lingers when re-enabled.
    var quoteEnabled: Bool {
        get { config.quoteEnabled }
        set {
            var c = config; c.quoteEnabled = newValue; config = c
            if newValue {
                lastQuoteFetch = nil
                refreshQuote()
            } else {
                currentQuote = nil
            }
        }
    }

    /// API-key draft plumbing (mirrors Feishu). Seed on launch; Save commits.
    func seedQuoteDraft() { quoteAPIKeyDraft = config.quoteAPIKey }
    var quoteDraftDirty: Bool { quoteAPIKeyDraft != config.quoteAPIKey }
    func saveQuoteDraft() {
        var c = config
        c.quoteAPIKey = quoteAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        config = c
        lastQuoteFetch = nil
        refreshQuote()
    }

    // Saved-quote passthrough to QuoteStore.
    var savedQuotes: [SavedQuote] {
        _ = quotesVersion
        return quoteStore.saved
    }
    func isCurrentQuoteSaved() -> Bool {
        _ = quotesVersion
        guard let q = currentQuote else { return false }
        return quoteStore.isSaved(q.text)
    }
    func saveCurrentQuote() {
        guard let q = currentQuote else { return }
        quoteStore.save(q, at: Date())
        quotesVersion &+= 1
    }
    func deleteSavedQuote(text: String) {
        quoteStore.delete(text: text)
        quotesVersion &+= 1
    }
}

// MARK: - Stopwatch coordination

extension AppViewModel {
    /// Master toggle for the stopwatch row. Turning it off ends any running or
    /// paused timer (sealing today's time to the work log) so nothing keeps
    /// counting while hidden.
    var stopwatchEnabled: Bool {
        get { config.stopwatchEnabled }
        set {
            var c = config; c.stopwatchEnabled = newValue; config = c
            if !newValue, stopwatchStore.snapshot.phase != .idle {
                stopwatchEnd()
            }
        }
    }

    var stopwatchPhase: StopwatchPhase {
        _ = stopwatchVersion
        return stopwatchStore.snapshot.phase
    }

    func stopwatchDisplay(now: Date = Date()) -> String {
        _ = stopwatchVersion
        return WorktimeFormatter.clock(stopwatchEngine.displaySeconds(stopwatchStore.snapshot, now: now))
    }

    var worklogDays: [(day: String, work: WorkDay)] {
        _ = stopwatchVersion
        return worklogStore.daysNewestFirst
    }

    var canStopwatchStart: Bool  { StopwatchEngine.canStart(stopwatchPhase) }
    var canStopwatchStop: Bool   { StopwatchEngine.canStop(stopwatchPhase) }
    var canStopwatchResume: Bool { StopwatchEngine.canResume(stopwatchPhase) }
    var canStopwatchEnd: Bool    { StopwatchEngine.canEnd(stopwatchPhase) }

    private func applyStopwatch(_ result: (StopwatchSnapshot, [SealedSegment])) {
        stopwatchStore.save(result.0)
        worklogStore.append(result.1)
        stopwatchVersion &+= 1
    }

    func stopwatchStart(now: Date = Date()) {
        let wasIdle = stopwatchStore.snapshot.phase == .idle
        applyStopwatch(stopwatchEngine.start(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
        if wasIdle, stopwatchStore.snapshot.phase == .running {
            sendCurrentQuoteToFeishu()
        }
    }
    func stopwatchStop(now: Date = Date()) {
        applyStopwatch(stopwatchEngine.stop(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
    }
    func stopwatchResume(now: Date = Date()) {
        applyStopwatch(stopwatchEngine.resume(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
    }
    func stopwatchEnd(now: Date = Date()) {
        applyStopwatch(stopwatchEngine.end(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar))
    }

    func evaluateStopwatch(now: Date = Date()) {
        let result = stopwatchEngine.evaluate(stopwatchStore.snapshot, now: now, calendar: stopwatchCalendar)
        if !result.1.isEmpty || result.0 != stopwatchStore.snapshot {
            applyStopwatch(result)
        }
    }
}

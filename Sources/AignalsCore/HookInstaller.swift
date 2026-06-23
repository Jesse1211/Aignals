import Foundation

public struct HookInstaller {
    public enum InstallError: Error {
        case malformedSettingsJSON
    }

    public struct EventDef {
        let event: String
        let command: String
        /// Optional notification_type matcher used to disambiguate multiple
        /// entries that share the same hook event (e.g. two `Notification`
        /// hooks). Claude Code matches `Notification` hooks by
        /// `notification_type`, so it is written into the settings.json entry.
        let matcher: String?

        init(event: String, command: String, matcher: String? = nil) {
            self.event = event
            self.command = command
            self.matcher = matcher
        }
    }

    /// The `(event, subcommand)` pairs the state machine needs. The leading
    /// program token (`aignals-hook` vs an absolute path) is supplied separately
    /// so we can write either a bare command (PATH-dependent fallback) or an
    /// absolute-path command that fires regardless of PATH (CRITICAL fix: a bare
    /// command silently never resolves unless the user ALSO links the CLI onto
    /// PATH — decoupling registration from where the hook actually lives).
    static let eventSubcommands: [(event: String, subcommand: String, matcher: String?)] = [
        ("SessionStart",     "on-sessionstart",      nil),
        ("UserPromptSubmit", "on-prompt",            nil),
        ("PreToolUse",       "on-pretool",           nil),
        ("Notification",     "on-permission",        "permission_prompt"),
        ("PostToolUse",      "on-posttool",          nil),
        ("PermissionDenied", "on-permission-denied", nil),
        ("Notification",     "on-idle",              "idle_prompt"),
        ("Stop",             "on-stop",              nil),
        ("SessionEnd",       "on-sessionend",        nil),
    ]

    /// The bare-command program token written when no absolute hook path is
    /// known. Resolves only if `aignals-hook` is on the hook shell's PATH.
    public static let bareProgram = "aignals-hook"

    /// Build the event table for a given hook program token. Passing the
    /// absolute path to the embedded/linked `aignals-hook` makes the registered
    /// commands fire without any PATH dependency (the root-cause fix). Passing
    /// `nil` keeps the legacy bare-command form.
    public static func events(hookPath: String? = nil) -> [EventDef] {
        let program = hookPath ?? bareProgram
        return eventSubcommands.map {
            .init(event: $0.event, command: "\(program) \($0.subcommand)", matcher: $0.matcher)
        }
    }

    /// Every hook event the state machine needs, each mapped to its matching
    /// bare `aignals-hook` subcommand (PATH-dependent fallback form). Tests and
    /// the suffix-matching `isInstalled`/`mergeEvent` logic key off the
    /// subcommand suffix, so an absolute-path install still round-trips.
    public static let events: [EventDef] = events(hookPath: nil)

    public init() {}

    /// Whether all required hooks are present. Suffix-matching means an install
    /// that wrote absolute paths (e.g. "/abs/aignals-hook on-stop") still counts
    /// as installed, since each command ends in the bare " on-<subcommand>".
    public func isInstalled(in file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return Self.events.allSatisfy { hasCommand($0.command, event: $0.event, matcher: $0.matcher, root: root) }
    }

    /// Install the bare-command form (legacy default; PATH-dependent).
    public func install(into file: URL) throws {
        try install(into: file, hookPath: nil)
    }

    /// Install, writing each command with `hookPath` as the program token when
    /// provided. With an absolute `hookPath`, the registered commands fire
    /// regardless of the hook shell's PATH — the root-cause fix for "install
    /// registers a bare command that silently never fires".
    public func install(into file: URL, hookPath: String?) throws {
        let events = Self.events(hookPath: hookPath)
        try install(events: events, into: file)
    }

    private func install(events: [EventDef], into file: URL) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            if !data.isEmpty {
                guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    throw InstallError.malformedSettingsJSON
                }
                root = obj
            }
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for e in events {
            hooks[e.event] = mergeEvent(eventArray: hooks[e.event] as? [[String: Any]] ?? [],
                                        command: e.command,
                                        matcher: e.matcher)
        }
        root["hooks"] = hooks

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let tmp = file.appendingPathExtension("tmp.\(UUID().uuidString)")
        let serialized = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try serialized.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }

    private func mergeEvent(eventArray: [[String: Any]], command: String, matcher: String?) -> [[String: Any]] {
        // Already present? Match on the bare " on-<subcommand>" suffix (and, for
        // disambiguated Notification entries, the matcher) so that ANY program
        // token form — bare "aignals-hook on-stop", an old absolute path, or the
        // new absolute path we are about to write — counts as the same hook and
        // we never append a duplicate. `bareSuffix` is the program-independent
        // tail, so dedup ignores the program token entirely (a superset of what
        // `hasCommand`/`isInstalled` recognizes).
        let bareSuffix = Self.bareSuffix(of: command)
        for entry in eventArray {
            if matcher != nil, (entry["matcher"] as? String) != matcher { continue }
            if let inner = entry["hooks"] as? [[String: Any]],
               inner.contains(where: { ($0["command"] as? String)?.hasSuffix(bareSuffix) == true }) {
                return eventArray
            }
        }
        var out = eventArray
        var entry: [String: Any] = [
            "hooks": [
                ["type": "command", "command": command]
            ]
        ]
        if let matcher = matcher {
            entry["matcher"] = matcher
        }
        out.append(entry)
        return out
    }

    /// The program-token-independent tail of a hook command, e.g.
    /// "/abs/aignals-hook on-stop" → " on-stop" and "aignals-hook on-stop" →
    /// " on-stop". Used to recognize the same hook regardless of whether it was
    /// written bare or with an absolute path, so re-install stays idempotent.
    static func bareSuffix(of command: String) -> String {
        if let r = command.range(of: " on-") {
            return String(command[r.lowerBound...])
        }
        return command
    }

    private func hasCommand(_ command: String, event: String, matcher: String?, root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let arr = hooks[event] as? [[String: Any]] else { return false }
        // Match by suffix so a hook installed with an absolute path
        // (e.g. "/path/to/aignals-hook on-stop") still counts as installed,
        // not just the bare "aignals-hook on-stop" form this installer writes.
        // For events disambiguated by matcher (the two `Notification` variants:
        // permission_prompt vs idle_prompt), the matcher must also agree, else a
        // mis-routed entry would be reported as installed yet never fire.
        return arr.contains { entry in
            if let matcher = matcher, (entry["matcher"] as? String) != matcher { return false }
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String)?.hasSuffix(command) == true }
        }
    }
}

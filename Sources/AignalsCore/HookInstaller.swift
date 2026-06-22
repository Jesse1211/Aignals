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

    /// Every hook event the state machine needs, each mapped to its
    /// matching `aignals-hook` subcommand. The two `Notification` events are
    /// distinguished by their `matcher` (notification_type).
    public static let events: [EventDef] = [
        .init(event: "SessionStart",    command: "aignals-hook on-sessionstart"),
        .init(event: "UserPromptSubmit", command: "aignals-hook on-prompt"),
        .init(event: "PreToolUse",      command: "aignals-hook on-pretool"),
        .init(event: "Notification",    command: "aignals-hook on-permission", matcher: "permission_prompt"),
        .init(event: "PostToolUse",     command: "aignals-hook on-posttool"),
        .init(event: "PermissionDenied", command: "aignals-hook on-permission-denied"),
        .init(event: "Notification",    command: "aignals-hook on-idle", matcher: "idle_prompt"),
        .init(event: "Stop",            command: "aignals-hook on-stop"),
        .init(event: "SessionEnd",      command: "aignals-hook on-sessionend"),
    ]

    public init() {}

    public func isInstalled(in file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return Self.events.allSatisfy { hasCommand($0.command, event: $0.event, matcher: $0.matcher, root: root) }
    }

    public func install(into file: URL) throws {
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
        for e in Self.events {
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
        // Already present? Match by suffix so an existing absolute-path entry
        // (e.g. "/path/to/aignals-hook on-stop") counts as present and we don't
        // append a duplicate bare-command entry. Must use the same rule as
        // `hasCommand` (isInstalled) so the two never disagree.
        for entry in eventArray {
            if let inner = entry["hooks"] as? [[String: Any]],
               inner.contains(where: { ($0["command"] as? String)?.hasSuffix(command) == true }) {
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

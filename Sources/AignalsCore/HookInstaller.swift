import Foundation

public struct HookInstaller {
    public enum InstallError: Error {
        case malformedSettingsJSON
    }

    public struct EventDef { let event: String; let command: String }
    public static let events: [EventDef] = [
        .init(event: "SessionStart", command: "aignals-hook on-sessionstart"),
        .init(event: "PreToolUse",   command: "aignals-hook on-pretool"),
        .init(event: "Stop",         command: "aignals-hook on-stop"),
        .init(event: "SessionEnd",   command: "aignals-hook on-sessionend"),
    ]

    public init() {}

    public func isInstalled(in file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return Self.events.allSatisfy { hasCommand($0.command, event: $0.event, root: root) }
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
            hooks[e.event] = mergeEvent(eventArray: hooks[e.event] as? [[String: Any]] ?? [], command: e.command)
        }
        root["hooks"] = hooks

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let tmp = file.appendingPathExtension("tmp.\(UUID().uuidString)")
        let serialized = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try serialized.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }

    private func mergeEvent(eventArray: [[String: Any]], command: String) -> [[String: Any]] {
        // Already present?
        for entry in eventArray {
            if let inner = entry["hooks"] as? [[String: Any]],
               inner.contains(where: { ($0["command"] as? String) == command }) {
                return eventArray
            }
        }
        var out = eventArray
        out.append([
            "hooks": [
                ["type": "command", "command": command]
            ]
        ])
        return out
    }

    private func hasCommand(_ command: String, event: String, root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let arr = hooks[event] as? [[String: Any]] else { return false }
        return arr.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String) == command }
        }
    }
}

import Foundation

/// Deletes the `~/.aignals` data dir during uninstall, optionally preserving
/// named top-level files (e.g. `quotes.json`) so the user can keep saved data.
/// Preserved files are moved to a sibling temp dir, `home` is removed, then a
/// fresh `home` is recreated and the kept files restored. All best-effort.
public enum HomeWipe {
    public static func wipe(home: URL, keeping keepFilenames: [String], fileManager fm: FileManager) {
        let present = keepFilenames
            .map { home.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }

        guard !present.isEmpty else {
            try? fm.removeItem(at: home)
            return
        }

        let stash = home.deletingLastPathComponent()
            .appendingPathComponent(".aignals-keep-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: stash, withIntermediateDirectories: true)
        for file in present {
            try? fm.moveItem(at: file, to: stash.appendingPathComponent(file.lastPathComponent))
        }

        try? fm.removeItem(at: home)
        try? fm.createDirectory(at: home, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        for file in present {
            let from = stash.appendingPathComponent(file.lastPathComponent)
            try? fm.moveItem(at: from, to: home.appendingPathComponent(file.lastPathComponent))
        }
        try? fm.removeItem(at: stash)
    }
}

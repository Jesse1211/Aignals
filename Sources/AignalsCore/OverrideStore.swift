import Foundation

/// App-owned persistence for per-session user preferences (`SessionOverride`),
/// keyed by `session_id`, stored in `~/.aignals/overrides.json` (ADR-12).
///
/// This is the side-car for user preferences (name/order/pinned) and is SEPARATE
/// from the hook-owned session files (INV-9): the hook never writes overrides.json,
/// so user preferences are never clobbered by hook updates.
///
/// Load is crash-safe: a missing or malformed file yields an empty `[:]` (like
/// `ConfigStore`). Every mutator persists immediately via atomic temp-file +
/// `FileManager.replaceItemAt`.
public final class OverrideStore {
    private let paths: Paths
    public private(set) var overrides: [String: SessionOverride]

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.overridesFile),
           let decoded = try? JSONDecoder().decode([String: SessionOverride].self, from: data) {
            self.overrides = decoded
        } else {
            self.overrides = [:]
        }
    }

    public func override(for id: String) -> SessionOverride? {
        overrides[id]
    }

    public func setName(_ name: String?, for id: String) {
        var ov = overrides[id] ?? SessionOverride()
        ov.name = name
        overrides[id] = ov
        persist()
    }

    public func setOrder(_ order: Int?, for id: String) {
        var ov = overrides[id] ?? SessionOverride()
        ov.order = order
        overrides[id] = ov
        persist()
    }

    public func setPinned(_ pinned: Bool, for id: String) {
        var ov = overrides[id] ?? SessionOverride()
        ov.pinned = pinned
        overrides[id] = ov
        persist()
    }

    public func setMuted(_ muted: Bool, for id: String) {
        var ov = overrides[id] ?? SessionOverride()
        ov.muted = muted
        overrides[id] = ov
        persist()
    }

    public func remove(for id: String) {
        overrides.removeValue(forKey: id)
        persist()
    }

    /// Drop any override whose id is not in `keepingIDs` (orphan cleanup, INV-10).
    public func prune(keepingIDs: Set<String>) {
        let before = overrides.count
        overrides = overrides.filter { keepingIDs.contains($0.key) }
        if overrides.count != before {
            persist()
        }
    }

    private func persist() {
        try? paths.ensureDirectories()
        let tmp = paths.overridesFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? JSONEncoder().encode(overrides) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.overridesFile, withItemAt: tmp)
        }
    }
}

import Foundation

@MainActor
public final class PIDSweeper {
    public let sessionsDirectory: URL
    public let store: SessionStore
    public let liveness: PIDLiveness
    public var staleAfter: TimeInterval = 24 * 3600
    public var interval: TimeInterval = 5

    private var timer: Timer?

    public init(sessionsDirectory: URL, store: SessionStore, liveness: PIDLiveness = SystemPIDLiveness()) {
        self.sessionsDirectory = sessionsDirectory
        self.store = store
        self.liveness = liveness
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.sweepOnce() }
        }
        sweepOnce()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func sweepOnce() {
        let fm = FileManager.default

        // FS access check
        guard let entries = try? fm.contentsOfDirectory(atPath: sessionsDirectory.path) else {
            store.setFSAccessError(true)
            return
        }
        store.setFSAccessError(false)

        let now = Date()
        for name in entries where name.hasSuffix(".json") && !name.hasSuffix(".json.tmp") {
            let path = sessionsDirectory.appendingPathComponent(name)
            sweepFile(at: path, now: now)
        }
    }

    private func sweepFile(at path: URL, now: Date) {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: path) else { return }

        let mtime = (try? fm.attributesOfItem(atPath: path.path)[.modificationDate] as? Date) ?? now
        let staleByMtime = now.timeIntervalSince(mtime) > staleAfter

        let session = try? Session.decode(from: data)
        let pid = session?.pid

        // Two distinct outcomes (ADR-13/ADR-14, INV-12):
        //  • removal: the 24h mtime backstop still deletes the file + drops the
        //    session. (The hook-driven SessionEnd/file-delete path is handled
        //    elsewhere — FSEvents — and is unchanged.)
        //  • mark-disconnected: a *dead pid* no longer deletes; instead the
        //    session is kept and its state flipped to `.disconnected` (gray).
        //    `.disconnected` is set ONLY here (polling), never by aignals-hook.
        let shouldRemove: Bool
        let markDisconnected: Bool
        switch (pid, staleByMtime) {
        case (let p?, let stale):
            switch liveness.state(of: p) {
            case .dead:
                // pid-dead → keep as gray (still honor the 24h backstop for removal).
                shouldRemove = stale
                markDisconnected = !stale
            case .alive, .unknown:
                shouldRemove = stale
                markDisconnected = false
            }
        case (nil, let stale):
            shouldRemove = stale
            markDisconnected = false
        }

        let id = (path.lastPathComponent as NSString).deletingPathExtension

        if shouldRemove {
            try? fm.removeItem(at: path)
            store.remove(id: id)
        } else if markDisconnected, let session {
            // Idempotent: only upsert if the store doesn't already show gray, so
            // repeated sweeps of the same dead session don't re-publish.
            let current = store.sessions.first { $0.sessionID == id }
            if current?.state != .disconnected {
                store.upsert(session.withState(.disconnected))
            }
        }
    }
}

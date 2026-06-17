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
            Task { @MainActor in self?.sweepOnce() }
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

        let shouldDelete: Bool
        switch (pid, staleByMtime) {
        case (let p?, _):
            switch liveness.state(of: p) {
            case .dead: shouldDelete = true
            case .alive, .unknown: shouldDelete = staleByMtime
            }
        case (nil, let stale):
            shouldDelete = stale
        }

        if shouldDelete {
            try? fm.removeItem(at: path)
            let id = (path.lastPathComponent as NSString).deletingPathExtension
            store.remove(id: id)
        }
    }
}

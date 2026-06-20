import Foundation
import AppKit
import AignalsCore

@MainActor
@Observable
final class AppViewModel {
    let paths: Paths
    let store: SessionStore

    private let watcher: FSEventsWatcher
    private let sweeper: PIDSweeper

    init() {
        let paths = Paths()
        try? paths.ensureDirectories()
        let store = SessionStore()

        self.paths = paths
        self.store = store
        self.watcher = FSEventsWatcher(directory: paths.sessionsDirectory, store: store)
        self.sweeper = PIDSweeper(sessionsDirectory: paths.sessionsDirectory, store: store)

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

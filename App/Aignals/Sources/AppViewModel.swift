import Foundation
import AppKit
import AignalsCore

@MainActor
@Observable
final class AppViewModel {
    let paths: Paths
    let store: SessionStore

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
        self.watcher = FSEventsWatcher(directory: paths.sessionsDirectory, store: store)
        self.sweeper = PIDSweeper(sessionsDirectory: paths.sessionsDirectory, store: store)

        if #available(macOS 13.0, *) {
            try? LaunchAtLogin.set(configStore.config.launchAtLogin) // re-apply on launch
        }

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

extension AppViewModel {
    var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    func installClaudeHooks() throws {
        try HookInstaller().install(into: claudeSettingsURL)
    }

    var claudeHooksInstalled: Bool {
        HookInstaller().isInstalled(in: claudeSettingsURL)
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

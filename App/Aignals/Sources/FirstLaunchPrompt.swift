import AppKit
import AignalsCore

/// First-launch install prompt (spec §7).
///
/// Shown at most once per machine: if the user dismisses with "Later" we set a
/// `UserDefaults` flag so it never re-appears. We use `UserDefaults` here as a
/// stopgap; Phase 10 introduces `ConfigStore.dismissedInstallPrompt` and this
/// prompt migrates to read/write that field instead.
@MainActor
enum FirstLaunchPrompt {
    private static let defaultsKey = "aignals.dismissedInstallPrompt"

    static func maybeShow(viewModel: AppViewModel) {
        if UserDefaults.standard.bool(forKey: defaultsKey) { return }
        if viewModel.claudeHooksInstalled { return }

        let alert = NSAlert()
        alert.messageText = "Aignals needs hooks to light up"
        alert.informativeText = "Install Aignals hooks into ~/.claude/settings.json so the indicator can track Claude Code sessions?"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Later")
        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn {
            try? viewModel.installClaudeHooks()
        } else {
            UserDefaults.standard.set(true, forKey: defaultsKey)
        }
    }
}

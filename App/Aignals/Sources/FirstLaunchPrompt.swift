import AppKit
import AignalsCore

/// First-launch install prompt (spec §7).
///
/// Shown at most once per machine. Dismissal state lives in
/// `ConfigStore.dismissedInstallPrompt` (Phase 10). A one-shot migration reads
/// the Phase 9 `UserDefaults` stopgap key, copies it into config, then removes
/// the legacy key.
@MainActor
enum FirstLaunchPrompt {
    private static let legacyKey = "aignals.dismissedInstallPrompt"

    static func maybeShow(viewModel: AppViewModel) {
        // One-shot migration from the Phase 9 UserDefaults stopgap.
        if UserDefaults.standard.bool(forKey: legacyKey), !viewModel.config.dismissedInstallPrompt {
            var c = viewModel.config; c.dismissedInstallPrompt = true; viewModel.config = c
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        if viewModel.config.dismissedInstallPrompt { return }
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
            var c = viewModel.config; c.dismissedInstallPrompt = true; viewModel.config = c
        }
    }
}

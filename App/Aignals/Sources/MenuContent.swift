import SwiftUI
import AignalsCore

/// Menu bar dropdown content.
///
/// Per ADR-0802 this view lives under `App/Aignals/Sources/` and binds to the
/// shared `AppViewModel`. The "Install Claude Code Hooks…" button (phase-09)
/// performs the idempotent merge into `~/.claude/settings.json` via
/// `AppViewModel.installClaudeHooks()` and reports the outcome via `NSAlert`.
struct MenuContent: View {
    @Bindable var vm: AppViewModel

    @Environment(\.openWindow) private var openWindow

    @State private var tick = Date()

    /// 30s tick keeps elapsed-time subtitles fresh while the menu is open
    /// (ADR-0804: coarse, low-frequency UI refresh).
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if vm.store.hasError {
            Label("Cannot read ~/.aignals", systemImage: "exclamationmark.triangle")
            Button("Reveal in Finder") { vm.revealAignalsHome() }
            Divider()
        }

        if vm.store.sessions.isEmpty {
            Text("No active sessions")
                .foregroundStyle(.secondary)
        } else {
            Text("Active Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(vm.store.sessions, id: \.sessionID) { session in
                sessionRow(session)
            }
        }

        Divider()

        Button("Install Claude Code Hooks…") {
            do {
                try vm.installClaudeHooks()
                Self.alert("Hooks installed", informative: "Aignals will now light up when Claude Code is working.")
            } catch {
                Self.alert("Couldn't install hooks",
                           informative: "Edit ~/.claude/settings.json manually. Error: \(error)")
            }
        }
        if !vm.hookIsLinked {
            Button("Install aignals-hook CLI…") {
                do {
                    try vm.linkHookCLI()
                    Self.alert("Linked", informative: "Symlinked aignals-hook into ~/.local/bin. If that's not on your PATH, add: export PATH=\"$HOME/.local/bin:$PATH\"")
                } catch {
                    Self.alert("Couldn't link CLI", informative: error.localizedDescription)
                }
            }
        }
        Button("Open ~/.aignals") { vm.revealAignalsHome() }
        Button("About Aignals…") { openWindow(id: "about") }

        Toggle("Launch at Login", isOn: Binding(
            get: { vm.launchAtLogin },
            set: { vm.launchAtLogin = $0 }
        ))

        Divider()

        Button("Quit Aignals") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
            .onReceive(timer) { tick = $0 }
            .onAppear { FirstLaunchPrompt.maybeShow(viewModel: vm) }
    }

    private static func alert(_ title: String, informative: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = informative
        a.runModal()
    }

    @ViewBuilder
    private func sessionRow(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(s.projectName)
            }
            Text(subtitle(for: s))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for s: Session) -> String {
        let elapsed = ElapsedFormatter.format(from: s.startedAt, to: tick)
        if let a = s.currentAction {
            let verb = VerbMapper.verb(forTool: a.tool)
            let target = a.target.isEmpty ? "" : " \(a.target)"
            return "\(verb)\(target) · \(elapsed)"
        } else {
            return "Active · \(elapsed)"
        }
    }
}

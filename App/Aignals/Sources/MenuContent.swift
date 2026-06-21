import SwiftUI
import AignalsCore

/// Menu bar dropdown content.
///
/// Per ADR-0802 this view lives under `App/Aignals/Sources/` and binds to the
/// shared `AppViewModel`. The "Install Claude Code Hooks…" button is an
/// intentional no-op stub per ADR-0805 / OQ-81 — install is out of scope for
/// this phase and must NOT be implemented here.
struct MenuContent: View {
    @Bindable var vm: AppViewModel

    @Environment(\.openWindow) private var openWindow

    @State private var tick = Date()

    /// 30s tick keeps elapsed-time subtitles fresh while the menu is open
    /// (ADR-0804: coarse, low-frequency UI refresh).
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if vm.store.aggregateStatus == .error {
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

        // NO-OP stub per ADR-0805 / OQ-81 — do not implement install here.
        Button("Install Claude Code Hooks…") {}
        Button("Open ~/.aignals") { vm.revealAignalsHome() }
        Button("About Aignals…") { openWindow(id: "about") }

        Divider()

        Button("Quit Aignals") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
            .onReceive(timer) { tick = $0 }
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

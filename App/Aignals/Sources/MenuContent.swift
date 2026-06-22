import SwiftUI
import AignalsCore

/// Menu bar dropdown content for the `.window` MenuBarExtra style (ADR-17).
///
/// Unlike the old `.menu` style (a modal `NSMenu` event loop where SwiftUI
/// timers never fire, there is no text input, and rows cannot be dragged), the
/// `.window` style renders a *real* SwiftUI view. That unlocks:
///   - a live 1-second elapsed-time tick (`Timer.publish(every: 1)`),
///   - inline rename via a `TextField` committing through `setName` (ADR-18),
///   - drag-to-reorder rows persisting `order` via `setOrder` (ADR-16/INV-11),
///   - a per-row pin toggle (ADR-19) and a gray-row remove ✕ (ADR-15).
///
/// The session list is rendered in `vm.sortedSessions` order. The menu-bar
/// label (the `StatusIcon` count image) is unchanged and lives in `AignalsApp`.
@MainActor
struct MenuContent: View {
    @Bindable var vm: AppViewModel

    @Environment(\.openWindow) private var openWindow

    /// Live 1-second tick driving elapsed-time labels. Fires under `.window`
    /// because the panel is a real SwiftUI view, not a modal `NSMenu`.
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.store.hasError {
                errorBanner
                Divider()
            }

            sessionList

            Divider()

            actions
        }
        .frame(width: 320)
        .onReceive(timer) { tick = $0 }
        .onAppear { FirstLaunchPrompt.maybeShow(viewModel: vm) }
    }

    // MARK: - Sections

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Cannot read ~/.aignals", systemImage: "exclamationmark.triangle")
                .font(.callout)
            Button("Reveal in Finder") { vm.revealAignalsHome() }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sessionList: some View {
        let sessions = vm.sortedSessions
        if sessions.isEmpty {
            Text("No active sessions")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            Text("Active Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)

            List {
                ForEach(sessions, id: \.sessionID) { session in
                    SessionRow(vm: vm, session: session, tick: tick)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                }
                .onMove { indices, newOffset in
                    var reordered = sessions
                    reordered.move(fromOffsets: indices, toOffset: newOffset)
                    vm.setOrder(reordered)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(sessions.count) * 56 + 8, 320))
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("Install Claude Code Hooks…") {
                do {
                    try vm.installClaudeHooks()
                    Self.alert("Hooks installed",
                               informative: "Aignals will now light up when Claude Code is working.")
                } catch {
                    Self.alert("Couldn't install hooks",
                               informative: "Edit ~/.claude/settings.json manually. Error: \(error)")
                }
            }

            if !vm.hookIsLinked {
                menuButton("Install aignals-hook CLI…") {
                    do {
                        try vm.linkHookCLI()
                        Self.alert("Linked", informative: "Symlinked aignals-hook into ~/.local/bin. If that's not on your PATH, add: export PATH=\"$HOME/.local/bin:$PATH\"")
                    } catch {
                        Self.alert("Couldn't link CLI", informative: error.localizedDescription)
                    }
                }
            }

            menuButton("Open ~/.aignals") { vm.revealAignalsHome() }
            menuButton("About Aignals…") { openWindow(id: "about") }

            Toggle("Launch at Login", isOn: Binding(
                get: { vm.launchAtLogin },
                set: { vm.launchAtLogin = $0 }
            ))
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 2)

            menuButton("Quit Aignals") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.vertical, 6)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private static func alert(_ title: String, informative: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = informative
        a.runModal()
    }
}

/// A single session row: state dot, editable name, "doing" subtitle, live
/// elapsed time, pin toggle, and a remove ✕ shown only for gray rows.
@MainActor
private struct SessionRow: View {
    @Bindable var vm: AppViewModel
    let session: Session
    let tick: Date

    /// Local editing buffer for the name field. Seeded from the effective
    /// display name and committed to `setName` on submit / focus loss.
    @State private var draftName: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Self.dotColor(for: session.state))
                .frame(width: 9, height: 9)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                vm.setPinned(!vm.isPinned(session), for: session)
            } label: {
                Image(systemName: vm.isPinned(session) ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(vm.isPinned(session) ? "Unpin" : "Pin to top")

            if session.state == .disconnected {
                Button {
                    vm.removeSession(session)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove disconnected session")
            }
        }
        .padding(.vertical, 2)
        .onAppear { draftName = vm.displayName(for: session) }
        .onChange(of: vm.displayName(for: session)) { _, newValue in
            // Keep the buffer in sync when not actively editing.
            if !nameFocused { draftName = newValue }
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == session.projectName {
            // Clear the override so the effective name falls back to projectName.
            vm.setName(nil, for: session)
            draftName = session.projectName
        } else {
            vm.setName(trimmed, for: session)
        }
    }

    private var subtitle: String {
        let elapsed = ElapsedFormatter.format(from: session.startedAt, to: tick)
        if session.state == .disconnected {
            return "Disconnected · \(elapsed)"
        }
        if let a = session.currentAction {
            let verb = VerbMapper.verb(forTool: a.tool)
            let target = a.target.isEmpty ? "" : " \(a.target)"
            return "\(verb)\(target) · \(elapsed)"
        }
        return "Active · \(elapsed)"
    }

    /// Per-session status dot colour (ADR-13 multi-status): working→red,
    /// waitingPermission→yellow, waitingInput→green, disconnected→gray.
    private static func dotColor(for state: SessionState) -> Color {
        switch state {
        case .working: return .red
        case .waitingPermission: return .yellow
        case .waitingInput: return .green
        case .disconnected: return .gray
        }
    }
}

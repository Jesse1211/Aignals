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

    /// Whether the General / Customization sections are expanded. Both start
    /// expanded (the old single "Settings" fold is gone — these section headers
    /// replace it directly). Each is an independent collapsible group.
    @State private var generalExpanded = true
    @State private var customizationExpanded = true

    /// Whether the side pop-out theme picker is showing (ADR-0809).
    @State private var themePopoverShown = false

    /// Concrete style tokens for the currently-selected theme (ADR-0808).
    private var style: ThemeStyle { ThemeStyle.tokens(for: vm.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(style.hairline)

            if vm.store.hasError {
                errorBanner
                Divider().background(style.hairline)
            }

            sessionList

            Divider().background(style.hairline)

            actions
        }
        .frame(width: 320)
        .environment(\.themeStyle, style)
        .foregroundStyle(style.textPrimary)
        .background(panelBackground)
        .onReceive(timer) { tick = $0 }
        .onAppear { FirstLaunchPrompt.maybeShow(viewModel: vm) }
    }

    /// Glass themes blur the desktop via NSVisualEffectView; fixed themes use a
    /// flat fill.
    @ViewBuilder
    private var panelBackground: some View {
        if let material = style.panelMaterial {
            VisualEffectBackground(material: material, appearance: style.panelAppearance)
        } else {
            style.panelColor
        }
    }

    // MARK: - Brand header

    private var header: some View {
        Button { openWindow(id: "about") } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .red], center: .center))
                    .frame(width: 18, height: 18)
                Text("AIGNALS").font(.system(size: 12, weight: .bold)).kerning(0.5)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(style.textSecondary)
                Spacer()
                countChips
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private var countChips: some View {
        let c = vm.store.statusCounts
        return HStack(spacing: 6) {
            chip(.red, c.working)
            chip(.yellow, c.waitingPermission)
            chip(.green, c.waitingInput)
        }
    }

    private func chip(_ color: Color, _ n: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: style.dotGlow ? color : .clear, radius: 3)
            Text("\(n)").font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.10)))
    }

    // MARK: - Sections

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Cannot read ~/.aignals", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
            Button("Reveal in Finder") { vm.revealAignalsHome() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: style.rowCorner)
                .fill(Color.red.opacity(0.12))
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sessionList: some View {
        let sessions = vm.sortedSessions
        if sessions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 28))
                    .foregroundStyle(style.textSecondary)
                Text("No active sessions")
                    .font(.callout)
                    .foregroundStyle(style.textPrimary)
                Text("Start Claude Code to see it light up.")
                    .font(.caption)
                    .foregroundStyle(style.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
        } else {
            Text("Active Sessions")
                .font(.caption)
                .foregroundStyle(style.textSecondary)
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
            // The config-class items live under two collapsible section headers
            // (General / Customization). No outer "Settings" fold — these groups
            // are the top level of the actions area.
            settingsItems

            Divider()
                .padding(.vertical, 2)

            menuButton("Quit Aignals") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.vertical, 6)
    }

    /// The config-class items, flattened: two collapsible section headers
    /// (General / Customization) over transparent rows. Sounds/Feishu sub-items
    /// are grouped by a faint left rule (no card background).
    @ViewBuilder
    private var settingsItems: some View {
        // ── GENERAL ──────────────────────────────────────────────
        sectionHeader("General", isExpanded: $generalExpanded)

        if generalExpanded {
            if !vm.claudeHooksInstalled {
                menuButton("🔗", "Install Claude Code Hooks…") {
                    runInstall(vm.installClaudeHooks,
                               successTitle: "Hooks installed",
                               successInfo: "Aignals will now light up when Claude Code is working.",
                               failureTitle: "Couldn't install hooks") { "Edit ~/.claude/settings.json manually. Error: \($0)" }
                }
            }
            if !vm.hookIsLinked {
                menuButton("⌘", "Install aignals-hook CLI…") {
                    runInstall(vm.linkHookCLI,
                               successTitle: "Linked",
                               successInfo: "Symlinked aignals-hook into ~/.local/bin. If that's not on your PATH, add: export PATH=\"$HOME/.local/bin:$PATH\"",
                               failureTitle: "Couldn't link CLI") { $0.localizedDescription }
                }
            }
            menuButton("📂", "Open ~/.aignals/") { vm.revealAignalsHome() }
            if !vm.launchAtLogin {
                menuButton("🚀", "Launch at Login") { vm.enableLaunchAtLogin() }
            }
            uninstallRow
        }

        // ── CUSTOMIZATION ────────────────────────────────────────
        sectionHeader("Customization", isExpanded: $customizationExpanded)

        if customizationExpanded {
            // Theme — existing side popover.
            Button { themePopoverShown.toggle() } label: {
                HStack(spacing: 9) {
                    Text("🎨").frame(width: 18, alignment: .center)
                    Text("Theme").font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .popover(isPresented: $themePopoverShown, arrowEdge: .trailing) {
                ThemePicker(vm: vm)
            }

            // Sounds — transparent title row + left-rule grouped sub-items.
            switchRow(icon: "🔊", title: "Sounds", isOn: Binding(
                get: { vm.soundEnabled }, set: { vm.soundEnabled = $0 }
            ))
            if vm.soundEnabled {
                groupedBlock {
                    soundPicker("🟡 Permission", selection: $vm.permissionSound)
                    soundPicker("🟢 Input", selection: $vm.inputSound)
                    if !vm.claudeHooksInstalled {
                        Button {
                            runInstall(vm.installClaudeHooks,
                                       successTitle: "Hooks installed",
                                       successInfo: "Aignals will now light up when Claude Code is working.",
                                       failureTitle: "Couldn't install hooks") { "Edit ~/.claude/settings.json manually. Error: \($0)" }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("⚠︎")
                                Text("Hooks not installed — sounds won't fire. Install…")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Feishu — transparent title row + left-rule grouped draft fields.
            switchRow(icon: "✈️", title: "Feishu", isOn: Binding(
                get: { vm.feishuEnabled }, set: { vm.feishuEnabled = $0 }
            ))
            if vm.feishuEnabled {
                groupedBlock {
                    feishuField("Webhook URL", text: Binding(
                        get: { vm.feishuURLDraft }, set: { vm.feishuURLDraft = $0 }))
                    feishuField("Secret (optional)", text: Binding(
                        get: { vm.feishuSecretDraft }, set: { vm.feishuSecretDraft = $0 }))
                    feishuField("Keyword (optional)", text: Binding(
                        get: { vm.feishuKeywordDraft }, set: { vm.feishuKeywordDraft = $0 }))

                    Text("Secret: for signature-mode bots. Keyword: only if your bot uses keyword security.")
                        .font(.caption2).foregroundStyle(.secondary)

                    HStack {
                        Button("Send test") { vm.sendFeishuTest() }
                        Spacer()
                        Button("Save") { vm.saveFeishuDrafts() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!vm.feishuDraftDirty)
                    }
                    .padding(.top, 2)

                    if let err = vm.lastFeishuError {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("⚠︎")
                            Text(err).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption).foregroundStyle(.red).padding(.top, 2)
                    }
                }
            }
        }
    }

    /// The destructive uninstall row (red, no ellipsis), placed in General.
    private var uninstallRow: some View {
        Button(action: runUninstall) {
            HStack(spacing: 9) {
                Text("🗑️").frame(width: 18, alignment: .center)
                Text("Uninstall Aignals").font(.system(size: 13)).foregroundStyle(.red)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    /// A transparent settings row with an icon, title, and a trailing macOS
    /// switch. Same metrics as the icon `menuButton` (no card background). Used
    /// as the Sounds / Feishu title row; its sub-items render below via
    /// `groupedBlock`.
    private func switchRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Text(icon).frame(width: 18, alignment: .center)
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    /// Groups a switch's sub-items under a faint 1px left rule (Version B) —
    /// replaces the old filled card. The rule sits just inside the 18pt icon
    /// column; content is inset to align under the title.
    @ViewBuilder
    private func groupedBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(style.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 4) { content() }
                .padding(.leading, 9)
        }
        .padding(.leading, 21)
        .padding(.trailing, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func soundPicker(_ title: String, selection: Binding<AlertSound>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AlertSound.allCases, id: \.self) { sound in
                Text(sound.displayName).tag(sound)
            }
        }
        .padding(.vertical, 2)
    }

    private func feishuField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .padding(.vertical, 2)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// A settings row with a leading icon (emoji), aligned to an 18pt column so
    /// titles line up. Coexists with the icon-less `menuButton(_:action:)`.
    private func menuButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(icon).frame(width: 18, alignment: .center)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// A clickable, collapsible section header (e.g. "General", "Customization").
    /// A caret reflects expanded/collapsed; tapping toggles the bound flag with a
    /// short slide. Keeps the uppercase eyebrow styling of the old static label.
    private func sectionHeader(_ text: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(style.textSecondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded.wrappedValue)
                Text(text)
                    .font(.system(size: 10, weight: .semibold)).kerning(0.6)
                    .foregroundStyle(style.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    /// Runs an install action, showing a success alert on completion or a
    /// failure alert built from the thrown error. The two install buttons differ
    /// only in their action and message text, so this factors out the shared
    /// do/try/catch → alert flow.
    private func runInstall(_ action: () throws -> Void,
                            successTitle: String,
                            successInfo: String,
                            failureTitle: String,
                            failureInfo: (Error) -> String) {
        do {
            try action()
            Self.alert(successTitle, informative: successInfo)
        } catch {
            Self.alert(failureTitle, informative: failureInfo(error))
        }
    }

    /// The destructive uninstall flow: a confirmation alert first, and only if
    /// the user explicitly confirms do we call `vm.uninstall()`. On success we
    /// show a final "drag to Trash" alert and quit; on error we show the error
    /// and do NOT quit (so the user can fix e.g. a malformed settings.json). This
    /// is a dedicated handler (not `runInstall`) because it needs the two-alert
    /// confirm-then-act shape.
    private func runUninstall() {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall Aignals?"
        confirm.informativeText = "This removes its Claude Code hooks, the aignals-hook CLI link, and all data in ~/.aignals. Aignals.app itself you'll drag to the Trash."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Cancel")
        let uninstallButton = confirm.addButton(withTitle: "Uninstall")
        if #available(macOS 11.0, *) {
            uninstallButton.hasDestructiveAction = true
        }

        // First button (.alertFirstButtonReturn) is Cancel; the second is Uninstall.
        guard confirm.runModal() == .alertSecondButtonReturn else { return }

        do {
            try vm.uninstall()
            Self.alert("Aignals uninstalled",
                       informative: "Aignals uninstalled — drag Aignals.app to the Trash to finish.")
            NSApplication.shared.terminate(nil)
        } catch {
            Self.alert("Couldn't uninstall",
                       informative: "Aignals was not fully uninstalled. Error: \(error)")
            // Do NOT quit — let the user resolve the problem and retry.
        }
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

    /// The current theme's style tokens, injected by `MenuContent` (ADR-0808).
    @Environment(\.themeStyle) private var style

    /// Local editing buffer for the name field. Seeded from the effective
    /// display name and committed to `setName` on submit / focus loss.
    @State private var draftName: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Self.dotColor(for: session.state))
                .frame(width: 9, height: 9)
                .shadow(color: style.dotGlow ? Self.dotColor(for: session.state) : .clear, radius: 4)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let prefix = style.rowPrefix {
                        Text(prefix)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(style.textSecondary)
                    }
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(style.usesMonospaced ? .system(.body, design: .monospaced) : .body)
                        .focused($nameFocused)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { commitName() }
                        }
                }

                Text(subtitle)
                    .font(style.usesMonospaced ? .system(.caption, design: .monospaced) : .caption)
                    .foregroundStyle(style.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                vm.toggleSound(for: session)
            } label: {
                // The icon reflects whether this session will ACTUALLY make a
                // sound: 🔊 when audible (global sound on AND not individually
                // muted), 🔇 otherwise — so turning global sound off shows every
                // row as muted. Clicking a muted row turns sound on for just it
                // (flipping the global master on, muting the others).
                Image(systemName: vm.soundActive(for: session) ? "speaker.wave.2" : "speaker.slash.fill")
            }
            .buttonStyle(.borderless)
            .help(vm.soundActive(for: session) ? "Mute this session" : "Enable sound for this session")

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
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: style.rowCorner)
                .fill(style.rowTint(session.state)?.opacity(0.14) ?? .clear)
        )
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

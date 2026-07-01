import SwiftUI
import AignalsCore

/// The standalone Settings window (ADR: replaces in-dropdown settings, which
/// flickered on collapse in the `.window` MenuBarExtra panel). A System-Settings-
/// style sidebar (General / Customization / About) over a detail pane. A normal
/// `NSWindow` resizes natively, so switching pages / toggling controls never
/// flickers — the reason this exists.
@MainActor
struct SettingsView: View {
    @Bindable var vm: AppViewModel

    @State private var selection: SettingsSection = .general

    private var style: ThemeStyle { ThemeStyle.tokens(for: vm.theme) }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
        } detail: {
            page(for: selection)
                .navigationTitle(selection.title)
                .frame(minWidth: 380, minHeight: 420)
        }
        .environment(\.themeStyle, style)
        // Land on the requested page: `.onAppear` covers a freshly-opened window;
        // `.onChange` covers the window being re-fronted while already open.
        .onAppear { selection = vm.settingsLandingSection }
        .onChange(of: vm.settingsLandingSection) { _, new in selection = new }
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .general:       generalPage
        case .customization: customizationPage
        case .about:         aboutPage
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalPage: some View {
        Form {
            Section("Setup") {
                if !vm.claudeHooksInstalled {
                    LabeledContent("Claude Code hooks") {
                        Button("Install…") {
                            runInstall(vm.installClaudeHooks,
                                       successTitle: "Hooks installed",
                                       successInfo: "Aignals will now light up when Claude Code is working.",
                                       failureTitle: "Couldn't install hooks") { "Edit ~/.claude/settings.json manually. Error: \($0)" }
                        }
                    }
                }
                if !vm.hookIsLinked {
                    LabeledContent("aignals-hook CLI") {
                        Button("Install…") {
                            runInstall(vm.linkHookCLI,
                                       successTitle: "Linked",
                                       successInfo: "Symlinked aignals-hook into ~/.local/bin. If that's not on your PATH, add: export PATH=\"$HOME/.local/bin:$PATH\"",
                                       failureTitle: "Couldn't link CLI") { $0.localizedDescription }
                        }
                    }
                }
                LabeledContent("Data folder") {
                    Button("Open ~/.aignals/") { vm.revealAignalsHome() }
                }
                if !vm.launchAtLogin {
                    LabeledContent("Launch at login") {
                        Button("Enable") { vm.enableLaunchAtLogin() }
                    }
                }
            }

            Section {
                Button(role: .destructive, action: runUninstall) {
                    Label("Uninstall Aignals", systemImage: "trash")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Customization

    @ViewBuilder
    private var customizationPage: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: Binding(
                    get: { vm.theme },
                    set: { newTheme in
                        vm.theme = newTheme               // applies instantly
                        Self.popMenuBarPanel()            // preview it in the menu dropdown
                    })) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        HStack(spacing: 8) {
                            ThemeSwatch(hexes: theme.swatchHexes)
                            Text(theme.displayName)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Sounds") {
                Toggle("Play sounds", isOn: Binding(
                    get: { vm.soundEnabled }, set: { vm.soundEnabled = $0 }))
                Picker("🟡 Permission", selection: $vm.permissionSound) {
                    ForEach(AlertSound.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .disabled(!vm.soundEnabled)
                Picker("🟢 Input", selection: $vm.inputSound) {
                    ForEach(AlertSound.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .disabled(!vm.soundEnabled)
                if vm.soundEnabled && !vm.claudeHooksInstalled {
                    Button {
                        runInstall(vm.installClaudeHooks,
                                   successTitle: "Hooks installed",
                                   successInfo: "Aignals will now light up when Claude Code is working.",
                                   failureTitle: "Couldn't install hooks") { "Edit ~/.claude/settings.json manually. Error: \($0)" }
                    } label: {
                        Label("Hooks not installed — sounds won't fire. Install…", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Toggle("Feishu notifications", isOn: Binding(
                    get: { vm.feishuEnabled }, set: { vm.feishuEnabled = $0 }))
                TextField("Webhook URL", text: $vm.feishuURLDraft)
                    .disabled(!vm.feishuEnabled)
                TextField("Secret (optional)", text: $vm.feishuSecretDraft)
                    .disabled(!vm.feishuEnabled)
                TextField("Keyword (optional)", text: $vm.feishuKeywordDraft)
                    .disabled(!vm.feishuEnabled)
                HStack {
                    Button("Send test") { vm.sendFeishuTest() }
                        .disabled(!vm.feishuEnabled)
                    Spacer()
                    Button("Save") { vm.saveFeishuDrafts() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.feishuEnabled || !vm.feishuDraftDirty)
                }
                if let err = vm.lastFeishuError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Feishu")
            } footer: {
                Text("Secret: for signature-mode bots. Keyword: only if your bot uses keyword security.")
            }

            Section {
                SecureField("API Ninjas key", text: $vm.quoteAPIKeyDraft)
                HStack {
                    Spacer()
                    Button("Save") { vm.saveQuoteDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.quoteDraftDirty)
                }
                Picker("Category", selection: Binding(
                    get: { vm.quoteCategory },
                    set: { vm.quoteCategory = $0 }
                )) {
                    ForEach(QuoteCategory.allCases, id: \.self) { cat in
                        Text(cat.label).tag(cat)
                    }
                }
            } header: {
                Text("Daily Quote")
            } footer: {
                Text("Get a free key at api-ninjas.com. The quote shows in the dropdown and refreshes daily.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    @ViewBuilder
    private var aboutPage: some View {
        VStack(spacing: 12) {
            Spacer()
            RoundedRectangle(cornerRadius: 18)
                .fill(AngularGradient(colors: [.red, .yellow, .green, .red], center: .center))
                .frame(width: 72, height: 72)
            Text("Aignals").font(.title2).bold()
            Text("Version \(appVersion)")
                .font(.callout).foregroundStyle(style.textSecondary)
            Text("Menu bar signal light for your AI coding agents.")
                .font(.callout).foregroundStyle(style.textSecondary)
                .multilineTextAlignment(.center)
            Link("github.com/Jesse1211/Aignals",
                 destination: URL(string: "https://github.com/Jesse1211/Aignals")!)
                .font(.callout)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Install / uninstall actions (moved from MenuContent)

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

    private func runUninstall() {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall Aignals?"
        confirm.informativeText = "This removes its Claude Code hooks, the aignals-hook CLI link, and all data in ~/.aignals. Aignals.app itself you'll drag to the Trash."
        confirm.alertStyle = .warning

        let keep = NSButton(checkboxWithTitle: "Keep my saved data (work log & quotes)", target: nil, action: nil)
        keep.state = .off
        confirm.accessoryView = keep

        confirm.addButton(withTitle: "Cancel")
        let uninstallButton = confirm.addButton(withTitle: "Uninstall")
        if #available(macOS 11.0, *) {
            uninstallButton.hasDestructiveAction = true
        }
        guard confirm.runModal() == .alertSecondButtonReturn else { return }
        do {
            try vm.uninstall(keepSavedData: keep.state == .on)
            Self.alert("Aignals uninstalled",
                       informative: "Aignals uninstalled — drag Aignals.app to the Trash to finish.")
            NSApplication.shared.terminate(nil)
        } catch {
            Self.alert("Couldn't uninstall",
                       informative: "Aignals was not fully uninstalled. Error: \(error)")
        }
    }

    private static func alert(_ title: String, informative: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = informative
        a.runModal()
    }

    /// Pops the menu-bar dropdown so the user can preview the just-selected theme
    /// on the live session list / header.
    ///
    /// `MenuBarExtra` is system-owned and has no public "open" API, so we reach
    /// the underlying `NSStatusItem` button (an `NSStatusBarButton` hosted in a
    /// status-bar window) and synthesize a click. Deferred one runloop tick so the
    /// theme write commits first; no-op if the button can't be found (degrades to
    /// "theme still applied, just not previewed").
    private static func popMenuBarPanel() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if let button = Self.statusBarButton(in: window.contentView) {
                    button.performClick(nil)
                    return
                }
            }
        }
    }

    private static func statusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let found = statusBarButton(in: sub) { return found }
        }
        return nil
    }
}

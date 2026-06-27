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
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            ScrollView {
                page(for: selection)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 340, minHeight: 380)
        }
        .environment(\.themeStyle, style)
        .foregroundStyle(style.textPrimary)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("General").font(.title2).bold()

            if !vm.claudeHooksInstalled {
                Button("Install Claude Code Hooks…") {
                    runInstall(vm.installClaudeHooks,
                               successTitle: "Hooks installed",
                               successInfo: "Aignals will now light up when Claude Code is working.",
                               failureTitle: "Couldn't install hooks") { "Edit ~/.claude/settings.json manually. Error: \($0)" }
                }
            }
            if !vm.hookIsLinked {
                Button("Install aignals-hook CLI…") {
                    runInstall(vm.linkHookCLI,
                               successTitle: "Linked",
                               successInfo: "Symlinked aignals-hook into ~/.local/bin. If that's not on your PATH, add: export PATH=\"$HOME/.local/bin:$PATH\"",
                               failureTitle: "Couldn't link CLI") { $0.localizedDescription }
                }
            }
            Button("Open ~/.aignals/") { vm.revealAignalsHome() }
            if !vm.launchAtLogin {
                Button("Launch at Login") { vm.enableLaunchAtLogin() }
            }

            Spacer(minLength: 8)
            Divider()
            Button(role: .destructive, action: runUninstall) {
                Text("Uninstall Aignals").foregroundStyle(.red)
            }
        }
    }

    // MARK: - Customization

    @ViewBuilder
    private var customizationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customization").font(.title2).bold()

            // Theme — inline (no popover). Reuses ThemePicker, which writes
            // vm.theme instantly on selection.
            VStack(alignment: .leading, spacing: 6) {
                Text("Theme").font(.headline)
                ThemePicker(vm: vm)
            }

            Divider()

            // Sounds — instant-apply.
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { vm.soundEnabled }, set: { vm.soundEnabled = $0 })) {
                    Text("Sounds").font(.headline)
                }
                if vm.soundEnabled {
                    Picker("🟡 Permission", selection: $vm.permissionSound) {
                        ForEach(AlertSound.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("🟢 Input", selection: $vm.inputSound) {
                        ForEach(AlertSound.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    if !vm.claudeHooksInstalled {
                        Button {
                            runInstall(vm.installClaudeHooks,
                                       successTitle: "Hooks installed",
                                       successInfo: "Aignals will now light up when Claude Code is working.",
                                       failureTitle: "Couldn't install hooks") { "Edit ~/.claude/settings.json manually. Error: \($0)" }
                        } label: {
                            Text("⚠︎ Hooks not installed — sounds won't fire. Install…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Feishu — draft + explicit Save (unchanged semantics).
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { vm.feishuEnabled }, set: { vm.feishuEnabled = $0 })) {
                    Text("Feishu").font(.headline)
                }
                if vm.feishuEnabled {
                    TextField("Webhook URL", text: $vm.feishuURLDraft).textFieldStyle(.roundedBorder)
                    TextField("Secret (optional)", text: $vm.feishuSecretDraft).textFieldStyle(.roundedBorder)
                    TextField("Keyword (optional)", text: $vm.feishuKeywordDraft).textFieldStyle(.roundedBorder)
                    Text("Secret: for signature-mode bots. Keyword: only if your bot uses keyword security.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Send test") { vm.sendFeishuTest() }
                        Spacer()
                        Button("Save") { vm.saveFeishuDrafts() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!vm.feishuDraftDirty)
                    }
                    if let err = vm.lastFeishuError {
                        Text("⚠︎ \(err)").font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - About

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    @ViewBuilder
    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About").font(.title2).bold()
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .red], center: .center))
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aignals").font(.title3).bold()
                    Text("Version \(appVersion)").foregroundStyle(style.textSecondary)
                }
            }
            Text("Menu bar signal light for your AI coding agents.")
                .font(.callout).foregroundStyle(style.textSecondary)
            Link("github.com/Jesse1211/Aignals",
                 destination: URL(string: "https://github.com/Jesse1211/Aignals")!)
        }
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
        confirm.addButton(withTitle: "Cancel")
        let uninstallButton = confirm.addButton(withTitle: "Uninstall")
        if #available(macOS 11.0, *) {
            uninstallButton.hasDestructiveAction = true
        }
        guard confirm.runModal() == .alertSecondButtonReturn else { return }
        do {
            try vm.uninstall()
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
}

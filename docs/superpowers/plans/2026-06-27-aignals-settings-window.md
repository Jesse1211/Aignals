# Aignals Settings-as-Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all Aignals settings out of the flicker-prone `MenuBarExtra(.window)` dropdown into a standalone, natively-resizable `Window` scene with a macOS System-Settings-style sidebar (General / Customization / About); slim the dropdown to session list + "Settings…" + Quit.

**Architecture:** Add a `Window("Aignals Settings", id: "settings")` scene hosting a new `SettingsView` (a `NavigationSplitView` with three page subviews). Delete the standalone About window and the entire in-dropdown settings UI + `PanelSizer`/`GeometryReader` resize workaround from `MenuContent`. `AppViewModel` gains exactly one field (`settingsLandingSection`) so the header and "Settings…" can land the window on a chosen page; everything else reuses existing VM API.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, XcodeGen project at `App/Aignals/Aignals.xcodeproj`, scheme "Aignals". Built via `xcodebuild`.

## Global Constraints

- App is built via the App xcodeproj, NOT the root SwiftPM package:
  ```bash
  xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
    -configuration Debug -derivedDataPath App/Aignals/DerivedData build
  ```
  If xcodebuild fails under the command sandbox with "Operation not permitted", re-run the SAME command with the Bash tool's `dangerouslyDisableSandbox: true` (expected for this project).
- Verification is **build-clean + visual run** (no XCTest covers these SwiftUI views). Do not invent tests for views.
- No behavior change to any setting. Draft+Save Feishu semantics, instant-apply Sounds/theme toggles, install/uninstall flows — all preserved exactly.
- `AppViewModel` changes are limited to adding the single `settingsLandingSection` property. No other VM edits.
- Reuse existing types: `ThemeStyle.tokens(for:)`, `Theme` (CaseIterable, `.displayName`, `.swatchHexes`), `AlertSound` (CaseIterable, `.displayName`), `ThemePicker(vm:)`, `VisualEffectBackground`, `Paths`, `ConfigStore`.
- New Swift files under `App/Aignals/Sources/` are picked up automatically by XcodeGen (the project globs `Sources/**`), so no project.yml edit is needed — but if the build reports the new file isn't compiled, regenerate with `xcodegen` in `App/Aignals/` (only if needed).
- Commit trailer required on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```

---

### Task 1: Add `SettingsSection` enum + `settingsLandingSection` to AppViewModel

The enum is the sidebar's model and the landing-page selector. It's tiny and is consumed by every later task, so it lands first together with its one VM field.

**Files:**
- Create: `App/Aignals/Sources/SettingsSection.swift`
- Modify: `App/Aignals/Sources/AppViewModel.swift` (add one stored property near the other `@Observable` state)

**Interfaces:**
- Produces: `enum SettingsSection: String, CaseIterable, Identifiable { case general, customization, about }` with `var id: String`, `var title: String`, `var symbol: String`. And `AppViewModel.settingsLandingSection: SettingsSection` (default `.general`), settable.

- [ ] **Step 1: Create the enum file**

Create `App/Aignals/Sources/SettingsSection.swift`:

```swift
import Foundation

/// The three pages of the standalone Settings window, used both as the sidebar
/// model and as the "land on this page" selector when the window is opened from
/// the menu (Settings… → .general) or the brand header (ⓘ → .about).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case customization
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .customization: return "Customization"
        case .about: return "About"
        }
    }

    /// SF Symbol shown beside the title in the sidebar.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .customization: return "paintpalette"
        case .about: return "info.circle"
        }
    }
}
```

- [ ] **Step 2: Add the landing-section property to AppViewModel**

In `App/Aignals/Sources/AppViewModel.swift`, find the Feishu draft properties (around line 44, `var feishuURLDraft: String = ""`). Immediately after the draft property group, add:

```swift
    /// Which Settings page the standalone window should show when next opened.
    /// `MenuContent`'s "Settings…" sets this to `.general`; the brand header sets
    /// it to `.about`. `SettingsView` syncs its selection from this on appear and
    /// on change (so it works whether the window was closed or already open).
    var settingsLandingSection: SettingsSection = .general
```

(Place it among the other plain `var` observable properties so `@Observable` tracks it. It must NOT be a computed config bridge — it's pure in-memory UI state.)

- [ ] **Step 3: Build clean**

Run:
```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/SettingsSection.swift App/Aignals/Sources/AppViewModel.swift docs/superpowers/specs/2026-06-27-aignals-settings-window-design.md docs/superpowers/plans/2026-06-27-aignals-settings-window.md
git commit -m "feat(settings): SettingsSection enum + vm.settingsLandingSection

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Build `SettingsView` (sidebar shell + three pages)

The whole new window, self-contained. It reuses `ThemePicker(vm:)` and existing VM API, and owns the install/uninstall/alert helpers (moved out of `MenuContent` here, deleted from `MenuContent` in Task 3).

**Files:**
- Create: `App/Aignals/Sources/SettingsView.swift`

**Interfaces:**
- Consumes: `SettingsSection` (Task 1); `AppViewModel` (`theme`, `permissionSound`, `inputSound`, `soundEnabled`, `feishuEnabled`, `feishuURLDraft`, `feishuSecretDraft`, `feishuKeywordDraft`, `feishuDraftDirty`, `saveFeishuDrafts()`, `sendFeishuTest()`, `lastFeishuError`, `installClaudeHooks`, `linkHookCLI`, `enableLaunchAtLogin()`, `revealAignalsHome()`, `uninstall()`, `claudeHooksInstalled`, `hookIsLinked`, `launchAtLogin`, `settingsLandingSection`); `ThemeStyle.tokens(for:)`; `ThemePicker(vm:)`; `Theme`, `AlertSound`; `VisualEffectBackground`.
- Produces: `struct SettingsView: View` initialised as `SettingsView(vm:)`.

- [ ] **Step 1: Create `SettingsView.swift` with the split-view shell**

Create `App/Aignals/Sources/SettingsView.swift`:

```swift
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
}
```

- [ ] **Step 2: Add the General page**

Append inside `SettingsView` (before the closing brace):

```swift
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
```

- [ ] **Step 3: Add the Customization page**

Append inside `SettingsView`:

```swift
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
```

Note: `$vm.feishuURLDraft` works because `vm` is `@Bindable` and `feishuURLDraft` is a stored `var`.

- [ ] **Step 4: Add the About page**

Append inside `SettingsView`. This reproduces `AboutView`'s content WITHOUT its fixed `.frame(width: 320)` / own background (the window supplies chrome), reading the theme from the injected `style`:

```swift
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
```

- [ ] **Step 5: Add the install/uninstall/alert helpers (moved from MenuContent)**

Append inside `SettingsView` (these are verbatim moves from `MenuContent`; Task 3 deletes the originals):

```swift
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
```

- [ ] **Step 6: Build clean**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build
```
Expected: `** BUILD SUCCEEDED **`. (`SettingsView` compiles standalone even though `MenuContent` still has its own copies of the helpers at this point — there is no name clash because they're in separate types.)

- [ ] **Step 7: Commit**

```bash
git add App/Aignals/Sources/SettingsView.swift
git commit -m "feat(settings): SettingsView window (sidebar General/Customization/About)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Wire the window scene, slim MenuContent, delete the dropdown settings + resize workaround

This task makes the new window live and removes the old in-dropdown UI in one cohesive change (the scene swap and the `MenuContent` slim-down are interdependent: the header/Settings… buttons reference `openWindow(id: "settings")`, and the removed About scene must be replaced atomically).

**Files:**
- Modify: `App/Aignals/Sources/AignalsApp.swift`
- Modify: `App/Aignals/Sources/MenuContent.swift`
- Delete: `App/Aignals/Sources/AboutView.swift` (after confirming nothing else references it)

**Interfaces:**
- Consumes: `SettingsView(vm:)` (Task 2), `SettingsSection` (Task 1), `vm.settingsLandingSection`.

- [ ] **Step 1: Swap the About window scene for the Settings window scene**

In `App/Aignals/Sources/AignalsApp.swift`, replace the About `Window` block:

```swift
        Window("About Aignals", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
```

with:

```swift
        Window("Aignals Settings", id: "settings") {
            SettingsView(vm: vm)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 440)
```

- [ ] **Step 2: Repoint the brand header to open Settings on the About page**

In `App/Aignals/Sources/MenuContent.swift`, in `header`, replace:

```swift
        Button { openWindow(id: "about") } label: {
```

with:

```swift
        Button {
            vm.settingsLandingSection = .about
            openWindow(id: "settings")
        } label: {
```

- [ ] **Step 3: Replace `actions` with the slim version**

Replace the entire `actions` computed property (the `VStack` containing `settingsItems`, the Divider, and Quit) with:

```swift
    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("⚙", "Settings…") {
                vm.settingsLandingSection = .general
                openWindow(id: "settings")
            }
            menuButton("⏻", "Quit Aignals") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.vertical, 6)
    }
```

(Uses the existing icon `menuButton(_:_:action:)` helper, which stays.)

- [ ] **Step 4: Delete the dropdown settings UI, collapse state, and resize workaround from MenuContent**

Delete from `MenuContent.swift`:
- the `@State private var generalExpanded` / `customizationExpanded` properties
- the `@State private var themePopoverShown` property
- the `settingsItems` computed property
- the `uninstallRow`, `switchRow`, `groupedBlock`, `soundPicker`, `feishuField`, `sectionHeader` helpers
- the `runInstall`, `runUninstall`, and `static alert` helpers (now living in `SettingsView`)
- the entire `PanelSizer` struct (after the `MenuContent` closing brace)
- in `body`, the `.background(GeometryReader { proxy in PanelSizer(contentHeight: proxy.size.height) })` modifier and its explanatory comment block

Keep: `header`, `countChips`, `chip`, `errorBanner`, `sessionList`, the icon-less `menuButton(_:action:)` and icon `menuButton(_:_:action:)`, the `timer`/`tick`, `panelBackground`, `SessionRow`, and `body`'s remaining modifiers (`.frame(width: 320)`, `.environment`, `.foregroundStyle`, `.background(panelBackground)`, `.onReceive`, `.onAppear`).

- [ ] **Step 5: Confirm no dangling references, then delete AboutView.swift**

Run:
```bash
grep -rn "AboutView\|openWindow(id: \"about\")\|settingsItems\|PanelSizer\|themePopoverShown\|generalExpanded\|customizationExpanded\|groupCard\|switchRow\|groupedBlock\|sectionHeader" App/Aignals/Sources/
```
Expected: zero hits except possibly `SettingsView.swift` (which does NOT use any of these names — so truly zero). If `AboutView` has zero references, delete it:
```bash
git rm App/Aignals/Sources/AboutView.swift
```

- [ ] **Step 6: Build clean**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build
```
Expected: `** BUILD SUCCEEDED **`, no "unused" warnings for the removed symbols.

- [ ] **Step 7: Commit**

```bash
git add App/Aignals/Sources/AignalsApp.swift App/Aignals/Sources/MenuContent.swift
git rm --cached App/Aignals/Sources/AboutView.swift 2>/dev/null || true
git commit -m "feat(settings): open Settings window from menu/header; remove in-dropdown settings + PanelSizer + About window

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Launch and verify locally

**Files:** none (run-only).

- [ ] **Step 1: Kill any running instance and launch the fresh build**

```bash
pkill -x Aignals 2>/dev/null; sleep 1
open App/Aignals/DerivedData/Build/Products/Debug/Aignals.app
```

- [ ] **Step 2: Verify against the spec's acceptance list**

1. Menu dropdown shows only: header + session list + "⚙ Settings…" + "⏻ Quit Aignals".
2. Clicking "Settings…" opens the window on the **General** page.
3. Clicking the brand header (AIGNALS ⓘ) opens the window on the **About** page.
4. Sidebar switches between General / Customization / About.
5. Toggling Sounds reveals the two pickers; toggling Feishu reveals the draft fields + Send test/Save (Save disabled until a field changes).
6. **The window resizes natively with NO flicker** on every page switch and every toggle — the whole point of this redesign.
7. All actions work: Open ~/.aignals/, Launch at Login, Uninstall (confirm dialog), Theme switch (live), sound pickers, Feishu Save/Send test.
8. Re-clicking "Settings…" or the header fronts the single existing window (no duplicate windows); the header path lands it on About even when already open.

---

## Self-Review

**1. Spec coverage:**
- Window scene + sidebar layout → Task 2 + Task 3 Step 1. ✅
- Three pages (General/Customization/About) → Task 2 Steps 2–4. ✅
- Menu slim to session list + Settings… + Quit → Task 3 Steps 3–4. ✅
- Header opens Settings on About → Task 3 Step 2. ✅
- Theme inline (no popover), reuse ThemePicker → Task 2 Step 3. ✅
- Sounds/Feishu instant/draft semantics preserved → Task 2 Step 3. ✅
- Uninstall at bottom of General, red → Task 2 Step 2. ✅
- About inlined (no fixed width/own bg) → Task 2 Step 4. ✅
- Single VM addition `settingsLandingSection` → Task 1 Step 2. ✅
- Landing dual-path (`.onAppear` + `.onChange`) → Task 2 Step 1. ✅
- Delete About window + PanelSizer + dropdown settings → Task 3 Steps 1, 4, 5. ✅
- Single-instance window (Window not WindowGroup) → Task 3 Step 1. ✅
- Build clean + visual run → every task's build step + Task 4. ✅

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N" — every code step shows full code. ✅

**3. Type consistency:** `SettingsSection` cases (`general`/`customization`/`about`) and members (`title`/`symbol`/`id`) consistent across Tasks 1–3. `settingsLandingSection` named identically in VM (Task 1), header + Settings… (Task 3), and SettingsView sync (Task 2). `SettingsView(vm:)` init matches usage in Task 3 Step 1. Helper names (`runInstall`/`runUninstall`/`alert`) moved (Task 2 Step 5) then deleted from origin (Task 3 Step 4) — no duplication survives. `ThemePicker(vm:)` and `AlertSound.allCases`/`.displayName` match the real API. ✅

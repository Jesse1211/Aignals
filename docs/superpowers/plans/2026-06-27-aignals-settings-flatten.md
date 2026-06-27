# Aignals Settings Flatten + Visual Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flatten the Aignals settings menu — remove the "Settings" disclosure fold, make General/Customization collapsible section headers, and give every row one transparent style with unified font/padding (Version B: faint left rule grouping for Sounds/Feishu sub-items).

**Architecture:** Chrome-only refactor of a single SwiftUI file (`MenuContent.swift`). No behavior, view-model, or theme-token changes. The `groupCard` card helper is replaced by a transparent `switchRow` + `groupedBlock` (left-rule) pair; `sectionLabel` becomes a clickable `sectionHeader` backed by two `@State` expand flags.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, XcodeGen project at `App/Aignals/Aignals.xcodeproj`, scheme "Aignals". Built via `xcodebuild`.

## Global Constraints

- Single file touched: `App/Aignals/Sources/MenuContent.swift`. No edits to `AppViewModel.swift` or any ThemeStyle definition.
- Reuse existing theme tokens only: `style.hairline`, `style.textSecondary`, `style.textPrimary`. No new tokens.
- Panel width stays `320`. All behavior (draft+Save, `soundEnabled`/`feishuEnabled` toggles, theme popover, install/uninstall, header→About) is preserved exactly.
- Switches stay on the Sounds/Feishu title rows.
- Build command (run from repo root, sandbox must be disabled for xcodebuild):
  ```bash
  xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
    -configuration Debug -derivedDataPath App/Aignals/DerivedData build
  ```
- Verification is **build-clean + visual run** (SwiftUI layout isn't unit-testable here). There is no XCTest for `MenuContent`.
- Commit trailer required on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```

---

### Task 1: Flatten chrome — remove Settings fold, add collapsible headers, transparent rows (Version B)

This is one cohesive task: the changes are mutually dependent (removing the fold, adding the expand flags, and swapping `groupCard`→`switchRow`+`groupedBlock` all touch the same `actions`/`settingsItems`/helper region and won't compile in isolation). It ends with a clean build and a visual run.

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes (existing, unchanged — all already present in `AppViewModel`):
  - `vm.claudeHooksInstalled: Bool`, `vm.hookIsLinked: Bool`, `vm.launchAtLogin: Bool`
  - `vm.soundEnabled: Bool` (settable), `vm.feishuEnabled: Bool` (settable)
  - `vm.permissionSound`/`vm.inputSound: AlertSound` (bindable)
  - `vm.feishuURLDraft`/`feishuSecretDraft`/`feishuKeywordDraft: String` (settable)
  - `vm.feishuDraftDirty: Bool`, `vm.saveFeishuDrafts()`, `vm.sendFeishuTest()`, `vm.lastFeishuError: String?`
  - `vm.revealAignalsHome()`, `vm.enableLaunchAtLogin()`, `vm.installClaudeHooks`, `vm.linkHookCLI`, `vm.uninstall()`
  - `style.hairline`, `style.textSecondary` (theme tokens)
- Produces: new private helpers `sectionHeader(_:isExpanded:)`, `switchRow(icon:title:isOn:body:)`, `groupedBlock(content:)`; new `@State generalExpanded`, `customizationExpanded`. Removes `@State settingsExpanded`, the `groupCard` helper, and the `sectionLabel` helper.

- [ ] **Step 1: Replace the `settingsExpanded` state with two section-expand flags**

In `MenuContent.swift`, replace the `settingsExpanded` property (currently lines ~27–30):

```swift
    /// Whether the "Settings" fold is expanded (ADR-27/INV-16). Collapsed by
    /// default so the always-visible menu is just the session list + the
    /// "Settings" button + Quit.
    @State private var settingsExpanded = false
```

with:

```swift
    /// Whether the General / Customization sections are expanded. Both start
    /// expanded (the old single "Settings" fold is gone — these section headers
    /// replace it directly). Each is an independent collapsible group.
    @State private var generalExpanded = true
    @State private var customizationExpanded = true
```

- [ ] **Step 2: Remove the Settings disclosure from `actions`**

Replace the whole `actions` computed property (currently lines ~179–201) with:

```swift
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
```

- [ ] **Step 3: Rewrite `settingsItems` to use collapsible headers + transparent group rows**

Replace the whole `settingsItems` computed property (currently lines ~206–308) with:

```swift
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
```

- [ ] **Step 4: Update `uninstallRow` font to the unified size**

In `uninstallRow` (currently lines ~310–323), add `.font(.system(size: 13))` to the title so it matches every other row. Replace:

```swift
                Text("Uninstall Aignals").foregroundStyle(.red)
```

with:

```swift
                Text("Uninstall Aignals").font(.system(size: 13)).foregroundStyle(.red)
```

- [ ] **Step 5: Replace `groupCard` with `switchRow` + `groupedBlock`**

Delete the entire `groupCard(...)` helper (currently lines ~325–352) and replace it with these two helpers:

```swift
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
        .padding(.bottom, 4)
    }
```

- [ ] **Step 6: Drop the per-item horizontal padding from `soundPicker` and `feishuField`**

The `groupedBlock` now supplies the left inset, so the sub-items must not also pad horizontally (that would double-indent them). 

Replace `soundPicker` (currently lines ~354–362):

```swift
    private func soundPicker(_ title: String, selection: Binding<AlertSound>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AlertSound.allCases, id: \.self) { sound in
                Text(sound.displayName).tag(sound)
            }
        }
        .padding(.vertical, 2)
    }
```

Replace `feishuField` (currently lines ~364–370):

```swift
    private func feishuField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .padding(.vertical, 2)
    }
```

- [ ] **Step 7: Replace `sectionLabel` with the clickable `sectionHeader`**

Delete `sectionLabel(_:)` (currently lines ~400–407) and replace it with:

```swift
    /// A clickable, collapsible section header (e.g. "General", "Customization").
    /// A caret reflects expanded/collapsed; tapping toggles the bound flag with a
    /// short slide. Keeps the uppercase eyebrow styling of the old static label.
    private func sectionHeader(_ text: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(style.textSecondary)
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
```

- [ ] **Step 8: Unify the icon-less `menuButton` font**

The icon-less `menuButton(_:action:)` (used by Quit, currently lines ~372–381) should declare the same explicit size so Quit matches every row. Replace its label:

```swift
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
```

And the icon `menuButton(_:_:action:)` (currently lines ~385–398) — add the font to its title. Replace:

```swift
                Text(icon).frame(width: 18, alignment: .center)
                Text(title)
                Spacer(minLength: 0)
```

with:

```swift
                Text(icon).frame(width: 18, alignment: .center)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
```

- [ ] **Step 9: Build clean**

Run (sandbox disabled — xcodebuild needs it):

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
  -configuration Debug -derivedDataPath App/Aignals/DerivedData build
```

Expected: `** BUILD SUCCEEDED **`, no warnings about unused `settingsExpanded`, `groupCard`, or `sectionLabel` (they should all be gone).

- [ ] **Step 10: Sanity-grep that the removed symbols are gone**

Run:

```bash
grep -nE "settingsExpanded|groupCard|sectionLabel" App/Aignals/Sources/MenuContent.swift || echo "clean — all three removed"
```

Expected: `clean — all three removed`.

- [ ] **Step 11: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift docs/superpowers/specs/2026-06-27-aignals-settings-flatten-design.md docs/superpowers/plans/2026-06-27-aignals-settings-flatten.md
git commit -m "feat(ui): flatten Settings — collapsible General/Customization, transparent rows, left-rule grouping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Launch the rebuilt app locally

**Files:** none (run-only).

- [ ] **Step 1: Kill any running instance**

```bash
pkill -x Aignals 2>/dev/null; echo "killed (if running)"
```

- [ ] **Step 2: Launch the freshly built app**

```bash
open App/Aignals/DerivedData/Build/Products/Debug/Aignals.app
```

Expected: the menu-bar icon appears. Click it and verify against the spec's acceptance list:
1. No "Settings" disclosure — General/Customization are top-level.
2. Clicking a section header collapses/expands just that section (animated); both start expanded.
3. No card behind Sounds/Feishu — only a faint left rule under expanded sub-items.
4. Every row shares font size 13 / padding h12·v4; icons align on the 18pt column.
5. Sounds toggle+picker, Feishu draft/Save/Send-test, Theme popover, Uninstall all still work.

---

## Self-Review

**1. Spec coverage:**
- Remove Settings fold → Task 1 Steps 1–2. ✅
- General/Customization collapsible headers, expanded by default → Steps 1, 3, 7. ✅
- All rows transparent (remove card) → Steps 3, 5. ✅
- Version B faint left rule → Step 5 (`groupedBlock`). ✅
- Unify font size 13 / padding h12·v4 → Steps 3, 4, 5, 6, 8. ✅
- Switches stay on title rows → Step 5 (`switchRow`). ✅
- No AppViewModel / theme-token changes → Global Constraints; all `vm.*` consumed, none added. ✅
- Build clean + visual run → Steps 9–10, Task 2. ✅

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — every step shows full code. ✅

**3. Type consistency:** `sectionHeader(_:isExpanded:)`, `switchRow(icon:title:isOn:)`, `groupedBlock(content:)` named identically in interfaces and Steps 3/5/7. `generalExpanded`/`customizationExpanded` consistent across Steps 1 and 3. Removed symbols (`settingsExpanded`, `groupCard`, `sectionLabel`) verified gone in Step 10. ✅

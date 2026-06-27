# Settings Dropdown Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the Settings fold into General + Customization sections with iconed rows and grouped Sounds/Feishu cards, make the dropdown header open the About window, and give Feishu an explicit Save (draft → commit).

**Architecture:** All changes are in the App target — `App/Aignals/Sources/MenuContent.swift` (layout, helpers, cards, clickable header) and `App/Aignals/Sources/AppViewModel.swift` (Feishu draft state + Save). No `AignalsCore`, config-schema, send-pipeline, or hook changes. Verification is the Xcode build (`App/Aignals/Aignals.xcodeproj`) plus a manual checklist — this is SwiftUI/view-model code outside the unit-test target, consistent with the existing sound/Feishu UI.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, the `Aignals` scheme in `App/Aignals/Aignals.xcodeproj`.

## Global Constraints

- Build the app via the App xcodeproj, NOT the root SwiftPM scheme:
  `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build` → must print `** BUILD SUCCEEDED **`.
- No change to `AignalsConfig`, `FeishuClient`, `FeishuMessage`, or `handleSessionAlerts`.
- The About window (`AignalsApp.swift:23 Window(id:"about")`) is unchanged — only its trigger moves to the header.
- Icons are emoji, matching the file's existing 🎨/🟡/🟢 convention.
- Exact copy: `Open ~/.aignals/`, `Launch at Login`, `Uninstall Aignals` (no ellipsis), section labels `General` and `Customization`.
- Sounds stays immediate-apply (picker writes config on select). Only Feishu's three text fields become draft+Save.
- `ThemeStyle` has `textPrimary`/`textSecondary`/`hairline` but NO `cardFill` — use a literal `Color.primary.opacity(0.04)` fallback for card fill; do not add a theme token.
- Conventional-commit messages ending with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

### Task 1: Feishu draft model on `AppViewModel`

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

**Interfaces:**
- Consumes: existing `config` get/set bridge (set persists), existing `sendFeishuTest()`/`sendFeishu(text:)`.
- Produces (used by Task 5 UI):
  - `var feishuURLDraft: String`, `var feishuSecretDraft: String`, `var feishuKeywordDraft: String` (observable, mutable)
  - `func seedFeishuDrafts()` — copies persisted config into the drafts
  - `var feishuDraftDirty: Bool` — any draft differs from persisted config
  - `func saveFeishuDrafts()` — commits drafts → config (one persist)
  - `sendFeishuTest()` now builds from the DRAFT values (so the user can test before saving)

- [ ] **Step 1: Add the draft properties and helpers**

In `App/Aignals/Sources/AppViewModel.swift`, find the `// MARK: - Feishu notifications (send + test)` extension (added in the Feishu feature). Add these stored properties near the other stored vars at the top of the class (after `private(set) var lastFeishuError: String?`):

```swift
    /// Draft values for the Feishu card's text fields. Edited in place; committed
    /// to config only on Save (so a half-typed webhook isn't persisted). Seeded
    /// from persisted config at init and equal to config again after a Save.
    var feishuURLDraft: String = ""
    var feishuSecretDraft: String = ""
    var feishuKeywordDraft: String = ""
```

- [ ] **Step 2: Seed drafts at init**

In `init()`, after the config store is created (the `self.configStore = ConfigStore(paths: paths)` line), add a call to seed drafts. Since `seedFeishuDrafts()` reads `config`, place the call after `configStore` is assigned. Add at the end of `init()` (before the closing brace, after `seedInitialState()` and the stream Task is fine too — order doesn't matter as it only reads config):

```swift
        seedFeishuDrafts()
```

- [ ] **Step 3: Add the helper methods**

In the `// MARK: - Feishu notifications (send + test)` extension, add:

```swift
    /// Seed the card's draft fields from persisted config (call at init).
    func seedFeishuDrafts() {
        feishuURLDraft = config.feishuWebhookURL
        feishuSecretDraft = config.feishuSecret
        feishuKeywordDraft = config.feishuKeyword
    }

    /// True when any draft differs from the persisted value — enables Save.
    var feishuDraftDirty: Bool {
        feishuURLDraft != config.feishuWebhookURL
        || feishuSecretDraft != config.feishuSecret
        || feishuKeywordDraft != config.feishuKeyword
    }

    /// Commit the drafts to config in one persist. After this, drafts == config
    /// so `feishuDraftDirty` is false again.
    func saveFeishuDrafts() {
        var c = config
        c.feishuWebhookURL = feishuURLDraft
        c.feishuSecret = feishuSecretDraft
        c.feishuKeyword = feishuKeywordDraft
        config = c
    }
```

- [ ] **Step 4: Make `sendFeishuTest()` use the drafts**

Find the existing `sendFeishuTest()`. It currently reads `config.feishuKeyword` and relies on `sendFeishu` reading `config.feishuWebhookURL`/`config.feishuSecret`. Replace it with a version that sends from the drafts directly, so a test works before saving:

```swift
    /// Send the fixed test message using the CURRENT draft values (so the user can
    /// verify before saving). Routed through the same keyword-append rule.
    func sendFeishuTest() {
        let base = "Aignals • test — notifications are working"
        let kw = feishuKeywordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (kw.isEmpty || base.contains(kw)) ? base : base + " [\(kw)]"
        sendFeishuFromDraft(text: text)
    }

    /// Like `sendFeishu(text:)` but reads the draft URL/secret instead of config —
    /// used by the test button so unsaved edits can be verified.
    func sendFeishuFromDraft(text: String) {
        let url = feishuURLDraft
        let secret = feishuSecretDraft
        guard !url.isEmpty else { return }
        let ts = Int(Date().timeIntervalSince1970)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.feishuClient.send(text: text, webhookURL: url, secret: secret, timestamp: ts)
            switch result {
            case .success: self.lastFeishuError = nil
            case .failure(let err): self.lastFeishuError = Self.describe(err)
            }
        }
    }
```

> `Self.describe(err)` reuses the EXISTING `private static func describe(_ err: FeishuError) -> String` already in this file (at `AppViewModel.swift:602`). Do NOT add a second mapper — there is exactly one. Confirm with `grep -n 'func describe' App/Aignals/Sources/AppViewModel.swift` (one result).

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): Feishu draft model — seed/dirty/save + test sends from draft

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Iconed row helper + section label helper

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: existing `style` (`ThemeStyle` with `textSecondary`/`hairline`).
- Produces (used by Tasks 3–5):
  - `func menuButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View` — a row with a fixed-width leading icon. Coexists with the existing `menuButton(_:action:)`.
  - `func sectionLabel(_ text: String) -> some View` — a small uppercase section header.

- [ ] **Step 1: Add the two helpers**

In `App/Aignals/Sources/MenuContent.swift`, next to the existing `menuButton(_:action:)` (around line 356), add:

```swift
    /// A settings row with a leading icon (emoji), aligned to an 18pt column so
    /// titles line up. Coexists with the icon-less `menuButton(_:action:)`.
    private func menuButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(icon).frame(width: 18, alignment: .center)
                Text(title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// A small uppercase section label (e.g. "General", "Customization").
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).kerning(0.6)
            .foregroundStyle(style.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. (The helpers are unused for now — Swift allows unused private methods; if it warns, that's fine. They're consumed in Tasks 3–5.)

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(ui): iconed menuButton + sectionLabel helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `groupCard` helper

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `style.hairline`.
- Produces (used by Tasks 4–5): `func groupCard<Body: View>(icon: String, title: String, isOn: Binding<Bool>, @ViewBuilder body: () -> Body) -> some View` — a card with an icon+title+switch header and a body shown only when `isOn`.

- [ ] **Step 1: Add the `groupCard` helper**

In `App/Aignals/Sources/MenuContent.swift`, near the other private view helpers, add:

```swift
    /// A grouped settings card: a header row (icon + title + a macOS switch) and a
    /// body that is shown only when the switch is on. Used by Sounds and Feishu.
    @ViewBuilder
    private func groupCard<CardBody: View>(
        icon: String,
        title: String,
        isOn: Binding<Bool>,
        @ViewBuilder body: () -> CardBody
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(icon).frame(width: 18, alignment: .center)
                Text(title).fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
            }
            .padding(.horizontal, 10).padding(.vertical, 9)

            if isOn.wrappedValue {
                Divider().background(style.hairline)
                VStack(alignment: .leading, spacing: 4) { body() }
                    .padding(.horizontal, 11).padding(.top, 5).padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(style.hairline))
        .padding(.horizontal, 4).padding(.vertical, 6)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(ui): groupCard helper (icon+title+switch header, conditional body)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Clickable header → About; remove About row

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `openWindow` (`@Environment(\.openWindow)`, already in the view), `countChips`.
- Produces: header is a button opening `openWindow(id: "about")` with an ⓘ affordance.

- [ ] **Step 1: Make the header a button with an info affordance**

Replace the existing `header` computed property (around `MenuContent.swift:75`):

```swift
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
```

- [ ] **Step 2: Remove the "About Aignals…" row**

In `settingsItems`, delete the line:

```swift
        menuButton("About Aignals…") { openWindow(id: "about") }
```

(It will be gone entirely — About is now reached via the header.)

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(ui): clickable header opens About; drop About settings row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Reorganize `settingsItems` into General + Customization with cards

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `sectionLabel`, `menuButton(icon:,title:)`, `groupCard` (Tasks 2–3), the Feishu drafts + `saveFeishuDrafts`/`feishuDraftDirty`/`sendFeishuTest` (Task 1), existing `soundPicker`, `feishuField`, `vm.soundEnabled`/`vm.feishuEnabled`, install/uninstall/launch actions.
- Produces: the final settings layout.

This task rewrites the body of `settingsItems`. The Theme popover button, the install runners, the sound pickers, the `feishuField` helper, and the uninstall flow all already exist — this task RE-ARRANGES them into the new structure and wraps Sounds/Feishu in `groupCard`.

- [ ] **Step 1: Rewrite `settingsItems`**

Replace the entire body of `settingsItems` (from `MenuContent.swift:200` `private var settingsItems` through its closing brace at ~line 336) with:

```swift
    @ViewBuilder
    private var settingsItems: some View {
        // ── GENERAL ──────────────────────────────────────────────
        sectionLabel("General")

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

        // ── CUSTOMIZATION ────────────────────────────────────────
        sectionLabel("Customization")

        // Theme — existing side popover.
        Button { themePopoverShown.toggle() } label: {
            HStack(spacing: 9) {
                Text("🎨").frame(width: 18, alignment: .center)
                Text("Theme")
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

        // Sounds card.
        groupCard(icon: "🔊", title: "Sounds", isOn: Binding(
            get: { vm.soundEnabled }, set: { vm.soundEnabled = $0 }
        )) {
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

        // Feishu card.
        groupCard(icon: "✈️", title: "Feishu", isOn: Binding(
            get: { vm.feishuEnabled }, set: { vm.feishuEnabled = $0 }
        )) {
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

    /// The destructive uninstall row (red, no ellipsis), placed in General.
    private var uninstallRow: some View {
        Button(action: runUninstall) {
            HStack(spacing: 9) {
                Text("🗑️").frame(width: 18, alignment: .center)
                Text("Uninstall Aignals").foregroundStyle(.red)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
```

> The old `soundPicker(_:selection:)` and `feishuField(_:text:)` helpers stay as-is (defined later in the file). The old standalone `Toggle("Play sounds")` and `Toggle("Feishu notifications")` blocks are now GONE — replaced by the two `groupCard` calls. Confirm no orphaned references to the removed inline toggles remain.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Grep for orphans**

Run: `grep -n 'Play sounds\|Feishu notifications\|About Aignals…\|Enable Launch at Login' App/Aignals/Sources/MenuContent.swift`
Expected: NO output (all old copy replaced). If anything prints, remove it.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(ui): General/Customization sections, Sounds+Feishu cards, Feishu Save

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Docs — README + manual checklist

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/manual-test-checklist.md`

- [ ] **Step 1: Update README**

The README "Settings" description (in "The dropdown" section) lists the fold contents. Update the sentence listing the Settings items to reflect the new grouping. Find the paragraph that begins "Below the sessions, a **Settings** button expands the rest:" and replace its list with:

```markdown
Below the sessions, a **Settings** button expands two groups — **General** (Install Claude Code Hooks, Install aignals-hook CLI, Open `~/.aignals/`, Launch at Login, Uninstall) and **Customization** (Theme, a **Sounds** card, and a **Feishu** card). Clicking the dropdown's **Aignals** header (marked with an ⓘ) opens the About window. **Quit** stays outside the fold.
```

- [ ] **Step 2: Append manual-test rows**

In `docs/superpowers/specs/manual-test-checklist.md`, append:

```markdown
## Settings redesign
- [ ] Header shows an ⓘ; clicking the "Aignals" header opens the About window.
- [ ] No "About Aignals…" row remains in Settings.
- [ ] "General" and "Customization" section labels render; every row has a leading icon.
- [ ] Sounds and Feishu render as cards with a switch; body is hidden when the switch is off.
- [ ] Feishu: editing a field does NOT persist until Save; Save is disabled until a field changes.
- [ ] After Save + app relaunch, the saved Feishu values are shown; Save is disabled again.
- [ ] "Send test" uses the current (unsaved) field values.
- [ ] Copy reads `Open ~/.aignals/`, `Launch at Login`, `Uninstall Aignals` (no ellipsis).
- [ ] All four themes: card fill, switch, and section labels read acceptably.
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/superpowers/specs/manual-test-checklist.md
git commit -m "docs: Settings redesign — README grouping + manual checklist rows

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Plan Self-Review

**Spec coverage:**
- General/Customization sections + labels → Task 2 (helper) + Task 5 (use). ✓
- Leading icons on rows → Task 2 (helper) + Task 5 (use). ✓
- Sounds/Feishu group cards w/ switch → Task 3 (helper) + Task 5 (use). ✓
- Clickable header → About, ⓘ affordance, remove About row → Task 4. ✓
- Feishu Save + draft model + Send-test-from-draft → Task 1 (model) + Task 5 (UI). ✓
- Copy changes (`~/.aignals/`, `Launch at Login`, `Uninstall Aignals`) → Task 5. ✓
- `cardFill` fallback (no theme token) → Task 3 (literal `Color.primary.opacity(0.04)`). ✓
- Sounds stays immediate-apply → Task 5 (Sounds card binds `vm.soundEnabled`, pickers unchanged). ✓
- No config/core/pipeline change → none of the tasks touch them. ✓
- Docs → Task 6. ✓

**Placeholder scan:** No TBD/TODO. Task 1 Step 4 reuses the existing `describe(_:)` mapper at a named line (`AppViewModel.swift:602`) — explicit, not a vague "handle it".

**Type consistency:** `feishuURLDraft`/`feishuSecretDraft`/`feishuKeywordDraft`, `seedFeishuDrafts()`, `feishuDraftDirty`, `saveFeishuDrafts()`, `sendFeishuTest()`, `sendFeishuFromDraft(text:)`, `menuButton(_:_:action:)` (iconed), `sectionLabel(_:)`, `groupCard(icon:title:isOn:body:)`, `uninstallRow` — names consistent across Tasks 1–5. The iconed `menuButton(_:_:action:)` is a distinct overload from the existing `menuButton(_:action:)`; both coexist. ✓

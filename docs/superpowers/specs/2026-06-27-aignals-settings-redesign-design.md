# Settings dropdown redesign — design spec

**Date:** 2026-06-27
**Status:** Approved (visual brainstorm v3), ready for implementation plan
**Builds on:** the Feishu notifications feature (`feat/feishu-notifications` branch)

## Summary

Restructure the **Settings fold** of the menu-bar dropdown from a flat list of
buttons + inline toggles into **two labeled sections** — **General** and
**Customization** — each item carrying a leading icon, and the Sounds/Feishu
controls wrapped as **grouped cards** with a header row (icon + title + a macOS
toggle switch) whose body shows the sub-controls only when enabled. The brand
**header** of the dropdown becomes clickable to open the existing About window
(replacing the "About Aignals…" menu item). Feishu gains an explicit **Save**
button (its fields become a local draft, persisted on Save) alongside Send test.

This is a UI/UX refactor — no change to the underlying config model, the Feishu
send pipeline, the sound pipeline, or the hook protocol.

## Goals

- Group settings into **General** (system/install class) and **Customization**
  (user preferences) with small uppercase section labels.
- Give every settings row a **leading icon** for scannability.
- Replace the bare `Toggle(.checkbox)` for Sounds and Feishu with **group cards**:
  a header row (icon + title + a macOS switch-style `Toggle`) and a body that is
  visible only when the group is on.
- Make the dropdown **header clickable** → opens the About window; add an info
  affordance icon (ⓘ) signalling it's tappable. Remove the "About Aignals…" row.
- Add a **Save** button to the Feishu card; Feishu fields become a draft committed
  on Save (not persisted on every keystroke). Send test uses the current draft.
- Tidy copy: `Open ~/.aignals` → `Open ~/.aignals/`; `Enable Launch at Login` →
  `Launch at Login`; `Uninstall Aignals…` → `Uninstall Aignals` (drop the ellipsis).

## Non-goals (YAGNI)

- No change to `AignalsConfig` fields, `FeishuClient`, `FeishuMessage`, or the
  alert-trigger logic (`handleSessionAlerts`).
- No change to the About window's *content* — only its trigger (header vs. menu row).
- No second-level fold/popover for the card bodies — they expand inline under the card.
- No "unsaved changes" badge/confirmation for the Feishu draft beyond the Save button
  itself (can be added later if it proves needed).
- Sounds stays **immediate-apply** (picker writes config on select, with preview) — only
  Feishu's text fields get the draft+Save model.

## Final layout (from visual brainstorm v3)

Dropdown, top to bottom:

```
┌─────────────────────────────────────┐
│ ● Aignals                        ⓘ  │  ← clickable header → About window
├─────────────────────────────────────┤
│ session list … (unchanged)          │
├─────────────────────────────────────┤
│ Settings ▾                          │  ← existing disclosure (unchanged trigger)
│   GENERAL                           │  ← section label
│   🔗 Install Claude Code Hooks…     │  (only if not installed)
│   ⌘  Install aignals-hook CLI…      │  (only if not linked)
│   📂 Open ~/.aignals/               │
│   🚀 Launch at Login                │  (only while off)
│   🗑️ Uninstall Aignals              │  (red)
│                                     │
│   CUSTOMIZATION                     │  ← section label
│   🎨 Theme                       ›  │  (existing side popover)
│   ┌─────────────────────────────┐   │
│   │ 🔊 Sounds            [ ●—— ] │   │  ← card header + switch
│   │   🟡 Permission   [Ping  ▾] │   │  (body shown only when on)
│   │   🟢 Input        [Glass ▾] │   │
│   └─────────────────────────────┘   │
│   ┌─────────────────────────────┐   │
│   │ ✈️ Feishu            [ ●—— ] │   │
│   │   Webhook URL  [__________] │   │
│   │   Secret       [__________] │   │
│   │   Keyword      [__________] │   │
│   │   helper caption…           │   │
│   │   [Send test]        [Save] │   │  ← Send test left, Save right (primary)
│   │   ⚠︎ last error (if any)     │   │
│   └─────────────────────────────┘   │
├─────────────────────────────────────┤
│ ⏻ Quit Aignals                      │
└─────────────────────────────────────┘
```

## Architecture

All changes are in the App target, primarily `App/Aignals/Sources/MenuContent.swift`.
The `settingsItems` `@ViewBuilder` is reorganized; new small view helpers are added;
the `header` becomes a button; `AppViewModel` gains Feishu draft state.

### 1. Clickable header → About (`header`, `MenuContent.swift:75`)

Wrap the existing brand row (`RoundedRectangle` gradient + `Text("AIGNALS")`) in a
`Button` whose action is `openWindow(id: "about")`. Add a trailing **ⓘ** affordance
(`Image(systemName: "info.circle")`, `.secondary`) before/after the count chips to
signal it's clickable. The count chips remain. Use `.buttonStyle(.plain)` and a
`.contentShape(Rectangle())` so the whole header row is the hit target without changing
its look beyond the added icon. Remove the `About Aignals…` row from `settingsItems`.

> The About window itself (`AignalsApp.swift:23 Window(id:"about")`) is unchanged.

### 2. Section labels

Add a small helper:

```swift
private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .semibold)).kerning(0.6)
        .foregroundStyle(style.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
}
```

Emit `sectionLabel("General")` before the install/open/launch/uninstall rows and
`sectionLabel("Customization")` before Theme/Sounds/Feishu.

### 3. Leading icons on rows

Extend the existing row buttons to take a leading icon. Rather than overload the shared
`menuButton`, add an icon-aware variant:

```swift
private func menuButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View
```

that renders `HStack { Text(icon).frame(width:18); Text(title) … }`. Icons (emoji, to
match the existing 🎨/🟡/🟢 style already in this file):
- Install Hooks → 🔗, Install CLI → ⌘, Open ~/.aignals/ → 📂,
  Launch at Login → 🚀, Uninstall → 🗑️.

Keep the existing no-icon `menuButton(_:action:)` for any caller that needs it (e.g.
the Settings disclosure itself, Quit), or give those a blank-width spacer for alignment.

### 4. Group card (Sounds, Feishu)

A reusable card wrapper:

```swift
@ViewBuilder
private func groupCard<Body: View>(
    icon: String, title: String,
    isOn: Binding<Bool>,
    @ViewBuilder body: () -> Body
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 9) {
            Text(icon).frame(width: 18)
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
    .background(RoundedRectangle(cornerRadius: 9).fill(style.cardFill ?? Color.white.opacity(0.04)))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(style.hairline))
    .padding(.horizontal, 4).padding(.vertical, 6)
}
```

- **Sounds card:** `isOn: $vm.soundEnabled`; body = the two existing `soundPicker`
  rows + the existing "Hooks not installed" warning (moved inside the card body).
- **Feishu card:** `isOn: $vm.feishuEnabled`; body = the three draft fields + caption +
  the Send-test/Save action row + the error line (see §5).

> `style.cardFill` may not exist on `ThemeStyle`. If it doesn't, use a literal subtle
> fill (`Color.primary.opacity(0.04)`) consistent across themes — the implementation
> task picks one and the reviewer checks it reads acceptably on all four themes. Do NOT
> invent a new theme token unless a trivial fallback looks wrong on a fixed theme.

The `.switch` toggle style replaces the previous `.checkbox` for these two groups (the
brainstorm's "总开关交互方式" point). Other plain toggles are subsumed by the card.

### 5. Feishu draft + Save (`AppViewModel` + Feishu card body)

Feishu text fields stop writing config on each keystroke. Instead the view-model holds
**draft** strings seeded from config, and a Save commits them.

Add to `AppViewModel` (App target):

```swift
// Draft state for the Feishu card (committed on Save, ADR-new).
var feishuURLDraft: String = ""
var feishuSecretDraft: String = ""
var feishuKeywordDraft: String = ""

/// Seed the drafts from persisted config (call when the card appears / on Save reset).
func seedFeishuDrafts() {
    feishuURLDraft = config.feishuWebhookURL
    feishuSecretDraft = config.feishuSecret
    feishuKeywordDraft = config.feishuKeyword
}

/// True when any draft differs from the persisted value (enables the Save button).
var feishuDraftDirty: Bool {
    feishuURLDraft != config.feishuWebhookURL
    || feishuSecretDraft != config.feishuSecret
    || feishuKeywordDraft != config.feishuKeyword
}

/// Commit drafts → config (one persist).
func saveFeishuDrafts() {
    var c = config
    c.feishuWebhookURL = feishuURLDraft
    c.feishuSecret = feishuSecretDraft
    c.feishuKeyword = feishuKeywordDraft
    config = c
}
```

- Call `seedFeishuDrafts()` once in `init` (after config loads) so the fields populate
  from persisted config on launch. No re-seed after Save is needed — post-save the drafts
  already equal config, so `feishuDraftDirty` is naturally false again.
- The three `feishuField`s bind to the **drafts**, not the config bridges.
- **Send test** (`sendFeishuTest`) must use the **draft** URL/secret/keyword, not the
  persisted config, so the user can test before saving. Update `sendFeishu`/`sendFeishuTest`
  (or add a variant) to read drafts: simplest is to make `sendFeishuTest` build from
  `feishuURLDraft`/`feishuSecretDraft`/`feishuKeywordDraft`. Keep the real transition path
  (`handleSessionAlerts` → `sendFeishu(text:)`) reading from persisted `config` — a draft
  is not yet "live" until saved.
- The old config-bridge setters `feishuWebhookURL`/`feishuSecret`/`feishuKeyword` may be
  removed if no longer referenced, OR kept (read-only use). The plan resolves this by
  grep; remove dead setters to avoid two write paths.

The Feishu card action row:
```swift
HStack {
    Button("Send test") { vm.sendFeishuTest() }
    Spacer()
    Button("Save") { vm.saveFeishuDrafts() }
        .buttonStyle(.borderedProminent)
        .disabled(!vm.feishuDraftDirty)
}
```

The error line (`vm.lastFeishuError`) stays at the bottom of the card body, unchanged.

### 6. Copy changes

- `Open ~/.aignals` → `Open ~/.aignals/`
- `Enable Launch at Login` → `Launch at Login` (button still one-way; label shorter)
- `Uninstall Aignals…` → `Uninstall Aignals`

## Data flow (unchanged downstream)

```
header tap ──▶ openWindow("about")                     [new trigger, same window]
Sounds switch ─▶ vm.soundEnabled (config, immediate)   [unchanged]
sound picker ──▶ vm.permissionSound/inputSound (immediate, preview)  [unchanged]
Feishu switch ─▶ vm.feishuEnabled (config, immediate)  [unchanged]
Feishu fields ─▶ drafts (in-memory)                    [NEW: not persisted until Save]
Save ─────────▶ saveFeishuDrafts() → config persist    [NEW]
Send test ────▶ sendFeishuTest() reads drafts          [CHANGED: was config]
real transition▶ handleSessionAlerts → config values   [unchanged]
```

## Testing

This is App-target SwiftUI/view-model code (not in the unit-test target), so the bulk
is verified by build + manual checklist, consistent with the existing sound/Feishu UI
tasks. The one piece of pure logic — the draft model — is simple enough to verify by
the dirty-state behavior in the manual checklist. (If any draft helper is extracted into
`AignalsCore` it gains a unit test, but the spec keeps it on the view-model.)

Manual checklist additions:
- Header shows ⓘ; clicking the header opens the About window; no "About Aignals…" row remains.
- General/Customization labels render; every row has its leading icon.
- Sounds/Feishu render as cards with a switch; body hidden when off, shown when on.
- Feishu: editing a field does NOT persist until Save; Save is disabled until a field
  changes; after Save, relaunch shows the saved values; Save becomes disabled again.
- Send test uses the *current* (unsaved) field values.
- `Open ~/.aignals/`, `Launch at Login`, `Uninstall Aignals` copy is correct.
- All four themes: card fill + switch + labels read acceptably.

## Migration / compatibility

- No config schema change. Drafts are in-memory only; persisted shape is identical.
- A user who never opens the Feishu card sees no behavior change.
- Because Feishu fields are now Save-gated, a user mid-edit who closes the menu without
  Save loses the unsaved edit (acceptable, matches the explicit-Save decision).

## Open items

None — layout finalized in visual brainstorm v3; About interaction = existing window via
header; section names General/Customization confirmed.

# Aignals — Settings as a standalone window

**Status:** Draft → for approval
**Date:** 2026-06-27
**Branch:** `feat/feishu-notifications`
**Supersedes:** the in-dropdown collapsible-settings layout (redesign #2, commits 0427c24/f731cd9 + the uncommitted `PanelSizer` workaround)

## Problem

The settings UI currently lives inside the `MenuBarExtra(.window)` dropdown as
collapsible General/Customization sections. The `.window` panel is a
system-managed `NSPanel` that does **not** shrink cleanly when content collapses:
its SwiftUI-hosted `contentView` reports `fittingSize == 0`, so we hand-resize the
host `NSWindow` (`PanelSizer` + a `GeometryReader`). That works for *growing* but
on *shrink* the panel does a full-window compositor repaint (the
`NSVisualEffectView` blur recomposites), read by the user as a flicker. Multiple
fixes (animated resize, non-animated single `setFrame`, decoupled state) removed
the per-frame `setFrame` burst but could not remove the shrink repaint — it is a
limitation of the `.window` container, not our code.

**Decision:** stop fighting the dropdown. Move all settings into a real `Window`
scene (like the existing About window), where a normal `NSWindow` resizes
natively. The flicker problem disappears by construction, and the whole
`PanelSizer`/`GeometryReader`/manual-`setFrame` workaround is deleted.

## Goal

A standalone **Aignals Settings** window using a macOS System-Settings-style
left-sidebar + right-content layout, with three sections: **General**,
**Customization**, **About**. The menu-bar dropdown slims to: session list +
"Settings…" + Quit. No behavior changes to any setting; this is a relocation +
container change.

## Architecture

- **New Scene** in `AignalsApp.swift`: `Window("Aignals Settings", id: "settings")`
  hosting `SettingsView(vm:)`, with `.windowResizability(.contentSize)` and a
  sensible default size (~520×420). `Window` (not `WindowGroup`) is inherently
  single-instance: repeated `openWindow(id: "settings")` front the existing window.
- **Removed Scene**: `Window("About Aignals", id: "about")`. About becomes a
  section inside Settings.
- **New file** `App/Aignals/Sources/SettingsView.swift`: the split-view shell plus
  three page subviews (`GeneralSettingsPage`, `CustomizationSettingsPage`,
  `AboutSettingsPage`). Each page is a focused view with one clear responsibility.
- **`MenuContent.swift` slims down**: dropdown keeps header + session list +
  "Settings…" + Quit. All settings rows, the section/collapse machinery, the
  `PanelSizer`/`GeometryReader` resize workaround, and the theme popover are
  deleted from it. The install/uninstall/alert action helpers move to
  `SettingsView` (General page consumes them).
- **`AppViewModel`: zero changes.** `SettingsView` is `@Bindable var vm` and reuses
  every existing property/method (`soundEnabled`, `permissionSound`, `inputSound`,
  `feishuEnabled`, `feishu*Draft`, `feishuDraftDirty`, `saveFeishuDrafts`,
  `sendFeishuTest`, `lastFeishuError`, `theme`, `installClaudeHooks`, `linkHookCLI`,
  `enableLaunchAtLogin`, `revealAignalsHome`, `uninstall`, `claudeHooksInstalled`,
  `hookIsLinked`, `launchAtLogin`).

## Components

### `SettingsSection` (enum)
```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, customization, about
    var id: String { rawValue }
    var title: String { … }          // "General" / "Customization" / "About"
    var symbol: String { … }         // SF Symbol: "gear" / "paintpalette" / "info.circle"
}
```

### `SettingsView`
- `@Bindable var vm: AppViewModel`
- `@State private var selection: SettingsSection = .general` (default General)
- `NavigationSplitView { sidebar } detail: { page(for: selection) }`
  - Sidebar: `List(SettingsSection.allCases, selection: $selection)` rows = `Label(title, systemImage: symbol)`.
  - Detail: `switch selection` → the matching page.
- Style tokens: reuse `ThemeStyle.tokens(for: vm.theme)` like `MenuContent` does, injected via `.environment(\.themeStyle, style)` so pages can read it.
- **Opening to a specific section**: `MenuContent` cannot pass an argument through
  `openWindow(id:)` cleanly, so `selection` is seeded from a shared value on the
  view model is overkill — instead use a lightweight approach: the header opens the
  window AND sets an `@AppStorage`-free shared `@State` is not cross-window.
  **Chosen mechanism:** add a `@State` default of `.general`; the brand header sets
  the desired landing section via a tiny published property on `vm`
  (`vm.settingsLandingSection: SettingsSection`) that `SettingsView` reads
  `.onAppear` and on change. This is the one small VM addition — see "VM addition"
  below. (Supersedes the "zero changes" note for this single field.)

> **VM addition (the only one):** `@MainActor @Observable AppViewModel` gains
> `var settingsLandingSection: SettingsSection = .general`. `MenuContent`'s
> "Settings…" sets it to `.general` then `openWindow`; the header sets it to
> `.about` then `openWindow`. `SettingsView` syncs `selection` from it `.onAppear`
> and via `.onChange(of: vm.settingsLandingSection)`.

### `GeneralSettingsPage`
Vertical `Form`/`VStack`:
- "Install Claude Code Hooks…" button — only if `!vm.claudeHooksInstalled`.
- "Install aignals-hook CLI…" button — only if `!vm.hookIsLinked`.
- "Open ~/.aignals/" button → `vm.revealAignalsHome()`.
- "Launch at Login" button — only if `!vm.launchAtLogin` → `vm.enableLaunchAtLogin()`.
- Spacer / divider, then a red destructive **Uninstall Aignals** at the bottom →
  the confirm-then-act `runUninstall` flow.
- Owns the `runInstall` / `runUninstall` / `alert` helpers (moved verbatim from
  `MenuContent`).

### `CustomizationSettingsPage`
Vertical `Form`/`VStack`:
- **Theme** — inline: the four themes as a selectable row/segment (reuse
  `ThemePicker`'s content inline, or a `Picker`/segmented control bound to
  `vm.theme`). No popover.
- **Sounds** — a `Toggle` bound to `vm.soundEnabled`; when on, the two
  `Picker`s for `vm.permissionSound` / `vm.inputSound`, plus the existing
  "hooks not installed — sounds won't fire" inline warning when
  `!vm.claudeHooksInstalled`.
- **Feishu** — a `Toggle` bound to `vm.feishuEnabled`; when on, the three draft
  `TextField`s (`feishuURLDraft`/`feishuSecretDraft`/`feishuKeywordDraft`), the
  Secret/Keyword caption, the **Send test** + **Save** row (`Save` disabled unless
  `vm.feishuDraftDirty`, `.borderedProminent`), and the `vm.lastFeishuError` row.
  Draft+Save semantics unchanged.

### `AboutSettingsPage`
The current `AboutView` content, **inlined** (not reused as-is). `AboutView` hard-
codes `.frame(width: 320)` and paints its own `VisualEffectBackground`, and reads
the theme from a fresh `ConfigStore` — all of which fight a split-view detail pane.
So `AboutSettingsPage` reproduces just the content stack (logo gradient, "Aignals",
"Version x", tagline, repo `Link`) without the fixed width/background, reading the
theme from the injected `style` like the other pages. The standalone About window
scene is removed. `AboutView.swift` may be deleted once nothing references it.

### `MenuContent` (after slimming)
```
header (brand + ⓘ + count chips) — Button → vm.settingsLandingSection=.about; openWindow("settings")
Divider
[errorBanner if vm.store.hasError]
sessionList   (unchanged)
Divider
⚙ Settings…   — Button → vm.settingsLandingSection=.general; openWindow("settings")
⏻ Quit Aignals (unchanged, ⌘Q)
```
Deleted from `MenuContent`: `settingsItems`, `sectionHeader`, `switchRow`,
`groupedBlock`, `soundPicker`, `feishuField`, `uninstallRow`, `themePopoverShown`,
`generalExpanded`, `customizationExpanded`, `PanelSizer`, the `GeometryReader`
`.background`, and the install/uninstall/alert helpers (moved, not duplicated).
The 1-second `timer`/`tick`, `sessionList`, `errorBanner`, `header` brand styling,
and `SessionRow` stay.

## Data flow

Settings window and dropdown both bind the same `@Bindable vm` (the single
`AppViewModel` owned by `AignalsApp`). Toggling a setting in the window writes the
same VM properties the dropdown used to; persistence paths (config.json, draft
Save) are unchanged. The window observes `vm` and live-updates.

## Error handling

Unchanged. Install/uninstall surface `NSAlert` as before (helpers moved to the
General page). Feishu `Send test`/`Save` surface `vm.lastFeishuError` inline.
`MenuContent`'s `errorBanner` for unreadable `~/.aignals` stays in the dropdown.

## Testing / verification

No XCTest covers these views. Verification is **build clean + visual run**:
1. Build via the App xcodeproj (`xcodebuild -project App/Aignals/Aignals.xcodeproj
   -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData
   build`).
2. Menu shows session list + "Settings…" + Quit only.
3. "Settings…" opens the window on General; the brand header opens it on About.
4. Sidebar switches pages; toggling Sounds/Feishu reveals their sub-controls; the
   window resizes **natively with no flicker** on every interaction (the whole
   point).
5. All actions still work: install hooks/CLI, open home, launch at login,
   uninstall (confirm flow), theme switch, sound pickers, Feishu draft/Save/Send
   test.
6. Re-invoking "Settings…" or the header fronts the single existing window (no
   duplicate windows).

## Out of scope / non-goals

- No change to session list, status icon, hook protocol, config schema, or any
  setting's behavior.
- No new themes, sounds, or Feishu features.
- No collapsible sections (the window is roomy; Sounds/Feishu sub-controls still
  gate on their enable toggle, which is functional, not space-saving).

## Risks

- **Landing-section sync**: `Window` can't take a launch argument, hence the one VM
  field. Risk: if the window is already open, `openWindow` fronts it but `.onAppear`
  won't re-fire — so the `.onChange(of: vm.settingsLandingSection)` handler is what
  switches the page on a second invocation. Both paths needed.
- **NavigationSplitView min width**: must set a sidebar `.navigationSplitViewColumnWidth`
  / detail min so the window isn't too cramped; tune at run.
- **AboutView reuse**: if `AboutView` assumes it's the whole window (e.g. its own
  padding/sizing), it may need light adjustment to sit in the detail pane.
- Low overall: it's a relocation of working controls into a native container,
  deleting a fragile workaround.

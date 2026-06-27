# Aignals — Settings flatten + visual unification (redesign #2)

**Status:** Draft → for approval
**Date:** 2026-06-27
**Branch:** `feat/feishu-notifications`
**File touched:** `App/Aignals/Sources/MenuContent.swift` (only)
**Builds on:** redesign #1 (General/Customization sections, clickable header→About, group cards, Feishu draft+Save)

## Problem

After redesign #1 the `actions` area still has three visual inconsistencies the user
called out:

1. **The "Settings" fold is redundant.** General/Customization already group the
   config items; wrapping them again behind a single "Settings ▸/▾" disclosure is a
   second, pointless layer. The user wants General/Customization to *replace* the
   Settings fold directly.
2. **Mixed fonts & paddings.** Rows use a grab-bag of sizes (system body ~13 for
   menu buttons, 10 for section labels, `.caption`/`.caption2` inside cards) and
   paddings (`h12/v4`, `h12/v2`, `h10/v9`, `h11`). It reads as visually noisy.
3. **Mixed backgrounds.** Plain rows are transparent, but Sounds/Feishu are wrapped
   in filled+stroked cards (`Color.primary.opacity(0.04)` + hairline). The user
   wants every row transparent.

## Chosen design (confirmed via visual brainstorm — "Version B")

A **flat** settings list: no Settings fold, no card backgrounds. General and
Customization become **collapsible section headers**. Sounds/Feishu sub-items are
grouped by a **faint left vertical rule** instead of a card.

### 1. Remove the Settings fold

- Delete `@State settingsExpanded` (line 30) and the `settingsExpanded ? "Settings ▾"
  : "Settings ▸"` disclosure button in `actions` (lines 185–192).
- `actions` becomes: `settingsItems` rendered inline, then `Divider()`, then the
  Quit row. No leading indent on `settingsItems` (drop `.padding(.leading, 8)`).

### 2. General/Customization → collapsible section headers

- Add two `@State` flags, both **expanded by default** (user said "可折叠" = collapsible,
  not "默认收起" = collapsed-by-default):
  ```swift
  @State private var generalExpanded = true
  @State private var customizationExpanded = true
  ```
- Replace the static `sectionLabel(_:)` with a `sectionHeader(_ title:isExpanded:)`
  that renders a clickable row: a small caret (`chevron.down` when expanded,
  `chevron.right` when collapsed) + the uppercase title. Clicking toggles the bound
  flag (with `withAnimation(.easeInOut(duration: 0.15))` so the body slides).
- The General section's rows render only `if generalExpanded`; Customization's only
  `if customizationExpanded`.
- Keep the existing uppercase styling (size 10, semibold, kerning 0.6,
  `style.textSecondary`) for the title text; the caret matches `textSecondary`.

### 3. All rows transparent — remove the card

- Delete the `groupCard(...)` card chrome: no `RoundedRectangle.fill`, no `.overlay`
  stroke, no outer `.padding(.horizontal,4).padding(.vertical,6)`.
- Replace `groupCard` with a `switchRow(icon:title:isOn:)` — a transparent title row
  identical in metrics to the icon `menuButton` (HStack spacing 9, `Text(icon)
  .frame(width: 18)`, title, `Spacer()`, then the `.switch` Toggle). When `isOn`, the
  sub-items render **below** the row (siblings, not nested in a card), wrapped in a
  `groupedBlock { ... }`.

### 4. Version B — faint left vertical rule for sub-items

- A `groupedBlock(@ViewBuilder content:)` helper wraps Sounds'/Feishu's sub-items in:
  ```swift
  HStack(spacing: 0) {
      Rectangle().fill(style.hairline).frame(width: 1)   // faint left rule
      VStack(alignment: .leading, spacing: 4) { content() }
          .padding(.leading, 9)
  }
  .padding(.leading, 21)     // align rule under the icon column
  .padding(.trailing, 12)
  ```
  (Mockup used a 2px rule at `#34363f`; we use a 1px `style.hairline` so it adapts to
  every theme. Visually equivalent — "very faint".)

### 5. Unify font size & padding

One row metric for **every** clickable settings row (General items, Theme, Sounds
title, Feishu title, Quit):

- Font: **`.system(size: 13)`** (the default body-ish size already used by
  `menuButton`). Section headers stay at size 10 (their deliberate uppercase eyebrow).
- Padding: **`.horizontal, 12` / `.vertical, 4`** for every row.
- Icon column: `Text(icon).frame(width: 18, alignment: .center)`, HStack `spacing: 9`.
- Sub-items inside `groupedBlock` (sound pickers, Feishu fields, captions, Send/Save):
  no extra horizontal padding of their own — the block supplies the left inset. Drop
  the per-item `.padding(.horizontal, 12)` from `soundPicker` and `feishuField`;
  vertical `.padding(.vertical, 2)` stays.
- Captions/help text stay `.caption`/`.caption2` (intentionally smaller than rows) but
  align to the block's left edge.

### Resulting `settingsItems` order (unchanged content, flattened chrome)

```
▾ GENERAL
  🔗 Install Claude Code Hooks…        (only if !claudeHooksInstalled)
  ⌘ Install aignals-hook CLI…          (only if !hookIsLinked)
  📂 Open ~/.aignals/
  🚀 Launch at Login                   (only if !launchAtLogin)
  🗑️ Uninstall Aignals                 (red)
▾ CUSTOMIZATION
  🎨 Theme ›                           (side popover, unchanged)
  🔊 Sounds                    [switch]
    │ 🟡 Permission   [picker]
    │ 🟢 Input        [picker]
    │ ⚠︎ hooks-not-installed note (conditional)
  ✈️ Feishu                    [switch]
    │ Webhook URL  [field]
    │ Secret (optional)  [field]
    │ Keyword (optional)  [field]
    │ caption
    │ [Send test]            [Save]
    │ ⚠︎ lastFeishuError (conditional)
```

## Out of scope / unchanged

- **No behavior change.** Draft+Save model, `feishuEnabled`/`soundEnabled` immediate
  toggles, theme popover, install/uninstall flows, session list, header→About — all
  identical. This is **chrome-only**.
- No `AppViewModel.swift` changes. No new ThemeStyle tokens (reuse `hairline`,
  `textSecondary`, `textPrimary`).
- Switches stay on the Sounds/Feishu **title rows** (not moved into the block).
- Panel width stays 320.

## Acceptance

1. No "Settings" disclosure anywhere; General/Customization are the top-level groups
   in the actions area.
2. Clicking a section header collapses/expands just that section, animated; both
   start expanded.
3. No filled/stroked card behind Sounds or Feishu — only a faint 1px left rule under
   their expanded sub-items.
4. Every clickable settings row shares one font size (13) and one padding (h12/v4);
   icons align on the 18pt column.
5. Build is clean via the App xcodeproj; app runs and the menu renders the layout
   above. Sounds toggle + picker, Feishu draft/Save/Send-test, Theme popover, and
   Uninstall all still work.

## Risks

- **Collapse animation jank** with the `List`-based session view above: the actions
  VStack is outside the List, so `withAnimation` on a local `@State` is safe.
- **Left-rule alignment**: the 21pt left pad must line the rule up just inside the
  18pt icon column. Verify visually at run; tweak the constant if off.
- Low overall risk — single file, chrome-only, no logic touched.

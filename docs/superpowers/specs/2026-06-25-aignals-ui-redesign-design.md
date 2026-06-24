# Aignals — UI Redesign + Themes (Design Spec)

**Date:** 2026-06-25
**Status:** Approved (brainstorming complete)
**Scope:** Visual redesign of the menu-bar dropdown and the About window, plus a new user-selectable **Theme** feature with a side pop-out picker.
**Out of scope:** Animations (deferred to a separate pass), the menu-bar status icon itself (macOS template-color constraints), any logic/data-flow changes.

Mockups (reference, committed alongside this spec):
- `docs/superpowers/mockups/aignals-themes-final.html` — the 4 themes
- `docs/superpowers/mockups/aignals-theme-popover.html` — the side pop-out theme picker

---

## 1. Goal

The current dropdown is functional but visually plain — a default SwiftUI `List` with stock controls, no hierarchy, no brand identity. This redesign gives it a polished, modern look built from cards + glowing status dots + a brand header, and adds a **Theme** feature so users can choose between four looks. Functionality is unchanged; this is a presentation-layer redesign.

## 2. The four themes (ADR-0808)

A new `Theme` enum with four cases, each a complete visual style for the dropdown and About window:

| Theme | Case | Background | Notes |
|---|---|---|---|
| Glass Light | `glassLight` | `NSVisualEffectView` light material | Frosted, glowing dots |
| **Glass Dark** | `glassDark` | `NSVisualEffectView` dark material | **DEFAULT**, frosted, glowing dots |
| Terminal | `terminal` | Fixed near-black `#0c0f0a` | Monospace, phosphor-green text, `›` row prefix, square-ish dots |
| Vibrant | `vibrant` | Fixed `#16121f` | Each session row tinted by its state color (red/yellow/green gradient cards) |

**Default = `glassDark`.** Glass Light/Dark use the live system-material blur; Terminal and Vibrant are fixed palettes that do NOT follow the system appearance (by design — they are deliberate looks, not light/dark variants).

The `Theme` enum lives in `AignalsCore` (pure, unit-testable) and exposes the per-theme style values the views read (colors, fonts, materials, row treatment). It is threaded through the SwiftUI view tree via the Environment so a single source of truth re-styles the whole panel when it changes.

## 3. Layout (applies to all themes)

The dropdown keeps its current information architecture and all current behaviors (rename, drag-reorder, pin, per-row mute, gray-remove, error banner, Settings fold, Quit). Only the visual treatment changes:

1. **Brand header** (new): a small conic-gradient logo + `AIGNALS` wordmark on the left; a compact status count on the right (`🔴1 🟡1 🟢1` chips, or `idle` when empty). Replaces the bare "Active Sessions" caption as the top element.
2. **Session rows** become cards: rounded corners, hover highlight, a glowing status dot (colored `.shadow` halo; gray/disconnected has no halo), two-line body (name + subtitle), and trailing controls (🔊/🔇 mute, 📌 pin, and ✕ for disconnected rows). Trailing controls may fade in on hover (final hover behavior is a detail for implementation; keep them discoverable).
3. **Empty state**: a large status glyph + a short "No active sessions — start Claude Code to see it light up" message (replaces the plain text).
4. **Error banner**: the existing "Cannot read ~/.aignals" banner restyled as a tinted red card with a Reveal action.
5. **Footer**: Settings disclosure + Quit, restyled as menu items with icons.

Panel width stays ~300–320px. The session list keeps its current height clamp/scroll behavior.

## 4. Theme picker (ADR-0809)

A new **"🎨 Theme ▸"** row inside the existing Settings fold. Clicking it opens a **side pop-out card** (SwiftUI `.popover`) rather than expanding inline:

- The card lists the four themes, **one per row**. Each row shows a **live mini-swatch** (a small preview of that theme's palette), the theme name, and a **✓** on the currently-selected theme.
- **Pop-out side is automatic** — `.popover` chooses left/right based on available screen space so it never clips off-screen (the menu-bar item can sit anywhere along the top bar).
- **Selecting a theme applies it instantly** (the whole panel re-styles) and **the card stays open**, so the user can try themes back-to-back and compare. The card closes when the user clicks elsewhere / dismisses it.

## 5. Persistence (ADR-0810)

Add a `theme` field to `AignalsConfig`:

- Type: `Theme` (Codable, stored by a stable string raw value, e.g. `"glassLight" | "glassDark" | "terminal" | "vibrant"`).
- **Default = `.glassDark`**, applied both via `AignalsConfig.default` and via `decodeIfPresent(...) ?? .glassDark` in the custom `init(from:)` — exactly mirroring how `soundEnabled` was added so existing `~/.aignals/config.json` files keep working after upgrade (an old config with no `theme` key decodes to Glass Dark).
- Written through the existing `ConfigStore.save` atomic temp-file + `replaceItemAt` path. No new store; reuse `ConfigStore` and the `AppViewModel.config` setter (which already bumps `configVersion` so SwiftUI re-derives).
- `AppViewModel` exposes a `theme` get/set (read `config.theme`; set writes config back) so the picker binds to it the same way the sound toggle binds to `soundEnabled`.

## 6. Components & boundaries

| Unit | Where | Responsibility | Testable |
|---|---|---|---|
| `Theme` enum + style values | `Sources/AignalsCore/Theme.swift` | The four themes and their style tokens (colors, font, material kind, row treatment). Pure. | ✅ SPM unit tests (raw values, Codable round-trip, default) |
| `AignalsConfig.theme` | `Sources/AignalsCore/ConfigStore.swift` | Persist the selected theme with backward-compatible decode. | ✅ SPM (decode old config → glassDark; round-trip) |
| Themed panel styling | `App/Aignals/Sources/MenuContent.swift` (+ small view files as needed) | Apply the current theme's tokens to header/rows/footer/empty/error. | ⚠️ visual — CI build + manual smoke |
| Theme picker popover | `App/Aignals/Sources/` (e.g. `ThemePicker.swift`) | The side pop-out card with swatch rows + ✓; binds to `vm.theme`. | ⚠️ visual — manual smoke (popover can't be XCTest-driven) |
| `AppViewModel.theme` | `App/Aignals/Sources/AppViewModel.swift` | Get/set bridging the picker to `config.theme`. | ⚠️ (view-model, untestable per existing convention) |
| About window restyle | `App/Aignals/Sources/AboutView.swift` | Apply theme styling (large logo, version, links). | ⚠️ visual |
| Background material | `App/Aignals/Sources/` | `NSVisualEffectView` wrapper for the Glass themes; fixed colors for Terminal/Vibrant. | ⚠️ visual |

The split keeps the **theme definitions pure and unit-tested in `AignalsCore`**, while the **SwiftUI application of those tokens** lives in the App target and is verified by CI build + manual smoke (consistent with how Phase-8 UI was verified — no automated UI tests without a driveable harness).

## 7. Verification

- **Unit (SPM, on CI + local Xcode):** `Theme` raw values + Codable round-trip; `AignalsConfig` decodes a `theme`-less JSON to `.glassDark`; round-trips with each theme. These are the automated acceptance gates.
- **Build:** `xcodegen generate` + `xcodebuild` the `.app` green on CI (macos-15) and locally (Xcode 15.4).
- **Manual smoke (local, once built):** open the dropdown in each of the 4 themes; open the Theme picker, confirm it pops to the side, shows 4 swatch rows + ✓ on the active one, applies instantly, stays open; quit/relaunch and confirm the chosen theme persisted (reads `~/.aignals/config.json`); confirm an old config without `theme` lands on Glass Dark.

## 8. Risks / constraints

- **`.popover` placement:** rely on SwiftUI's automatic edge selection; do not hard-code a side. The menu-bar panel is itself a `.window`-style `MenuBarExtra`, so a nested `.popover` is supported, but verify it renders correctly anchored to a row (fallback: a custom overlay card if `.popover` misbehaves inside the menu-bar window).
- **Glass legibility:** the glowing dots + tinted cards must stay legible on both Glass Light and Glass Dark materials; pick halo opacities that read on either. Terminal/Vibrant are fixed so they're controlled.
- **No animation creep:** this spec deliberately excludes animation. The theme switch may be instant (no transition) for now; a later pass adds slide-in/cross-fade.
- **Menu-bar icon unchanged:** the aggregate `StatusIcon` is a template-constrained menu-bar image and is explicitly out of scope.

## 9. ADR summary

- **ADR-0808** — Four fixed themes (Glass Light, Glass Dark, Terminal, Vibrant); default Glass Dark. Terminal/Vibrant do not follow system appearance by design.
- **ADR-0809** — Theme picker is a side pop-out `.popover` card (one theme/row, swatch + ✓), auto side, stays open after selection, applies instantly.
- **ADR-0810** — `theme` persisted in `AignalsConfig` with backward-compatible `decodeIfPresent ?? .glassDark`, via existing `ConfigStore`.

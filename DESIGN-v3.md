# DESIGN-v3.md — Sound alerts + mute, pre-existing session adoption, Launch button, Settings fold (feature-factory ledger)

Locked decision ledger for **Aignals v0.3**. Builds on v1 (multi-status) + v2 (overrides/.window UI).

**Features:**
1. **Sound alerts + mute** — play a system sound when a session transitions to a state that needs the user (🟡 waiting-permission, 🟢 waiting-input), with per-session mute and a global sound toggle.
2. **Adopt pre-existing sessions** — sessions running BEFORE hooks were installed get picked up on their next hook event.
3. **Launch at Login → one-way button** that hides once enabled (like the Install items).
4. **Settings fold** — collapse the config-ish menu items behind a single "Settings" expander.

**Grounding rule (held throughout):** verifiable fact only; design intent only with evidence.

**PARKED (OQ-4):** session-name ↔ terminal-window-title sync. Hook payload has no tty/terminal/window_title; it exposes `session_title` (set via Claude Code `/rename`), and a hook can't reliably set the terminal title (Claude overwrites each spinner tick). Deferred pending a source-of-truth decision.

---

## 1. Bounded Context / Domain

- **BC:** `AignalsCore` (unchanged). Only the sound feature adds domain concepts; #2 is a hook behavior change, #3/#4 are UI.
- **Boundary:**
  - per-session **mute** is a user preference → `SessionOverride.muted` in the app-owned `OverrideStore` (same side-car as name/order/pinned, ADR-12).
  - **global sound on/off** is a global preference → `AignalsConfig.soundEnabled` in `ConfigStore` (same place as launchAtLogin).
  - **playing the sound** is AppKit (`NSSound`/`afplay`) → lives in the UI layer, which observes `store.changes` and decides whether to play. Not pure domain logic.
- **Aggregate root:** unchanged. `Session` still holds only hook-written data. Mute/sound are preference overlays.

## 2. Value objects (v0.3 additions)

- `SessionOverride` gains `muted: Bool` (default false). (ADR-20)
- `AignalsConfig` gains `soundEnabled: Bool` (default true). (ADR-20)

## 3. Invariants

- **INV-13 (sound trigger):** a sound plays ONLY when a session TRANSITIONS INTO 🟡 (waiting_permission) or 🟢 (waiting_input), AND `config.soundEnabled` AND NOT `override(session).muted`. Transition into 🔴 (working) never plays. (ADR-21/24)
- **INV-14 (adopt-on-event):** any UPDATE-class hook event (on-prompt/on-pretool/on-posttool/on-permission/on-permission-denied/on-idle/on-stop) whose session file does NOT exist CREATES it (back-filling project_name from basename(cwd) and the state that event implies). `on-sessionend` on a non-existent file is a no-op (never create-then-delete). (ADR-25)
- **INV-15 (Launch button hides):** "Enable Launch at Login" is a one-way button that disappears once launch-at-login is enabled (re-derived via the existing `installVersion`-style observable refresh). (ADR-26)
- **INV-16 (settings fold):** config-class items live behind a "Settings" expander; the always-visible menu is just the session list + a "Settings" button + Quit. (ADR-27)

## 4. Lifecycle note

The state machine gains a NEW entry (INV-14): besides `SessionStart → 🟢`, an unknown (pre-existing) session can enter via any update event, taking the state that event implies (on-prompt → 🔴, on-stop → 🟢, etc.). A session discovered this way counts as a "startup/adoption" load for sound purposes — it does NOT play a sound (ADR-22).

## 5. ADR ledger (continues v2's numbering)

- **ADR-20:** per-session mute = `SessionOverride.muted` (OverrideStore); global sound = `AignalsConfig.soundEnabled` (ConfigStore). *Reuse the two v2 preference layers; aligns with name/launchAtLogin.*
- **ADR-21:** sound triggers only on transition INTO 🟡/🟢; never 🔴. *Alert only when it's the user's turn.*
- **ADR-22:** THROTTLE — app-startup loads AND pre-existing-session adoption do NOT play; a given session plays at most once per 3 seconds. *Prevents a startup sound-storm and permission-flicker spam.*
- **ADR-23:** 🟡 and 🟢 use DIFFERENT macOS system sounds (e.g. 🟡=Ping/urgent, 🟢=Glass/soft, via NSSound or afplay). *Hear which kind of attention is needed.*
- **ADR-24:** the play decision (`soundEnabled && !muted && transition-into-🟡/🟢 && not-a-startup-load`) lives in the UI layer observing `store.changes`. *Playing sound is AppKit, not pure domain logic.*
- **ADR-25:** adopt-on-event (INV-14). *Hooks DO fire on an already-running session's next event after install, but SessionStart does NOT re-fire — so update subcommands must create the file if absent.*
- **ADR-26:** Launch at Login becomes a one-way "Enable Launch at Login" button that hides once enabled (like the Install items; disabling is done in System Settings, or later re-exposed inside the Settings fold). *User asked for a button matching the Install items, not a checkbox.*
- **ADR-27:** config-class items (Install hooks/CLI, Open ~/.aignals, About, Launch at Login) fold behind a "Settings" expander; always-visible = session list + Settings button + Quit. *Reduce the all-at-once information dump.*

## 6. Open Questions

- **OQ-4:** session-name ↔ terminal-window-title sync (parked, see top). Only viable direction is reading `session_title` as display name; pushing an app-set name to the terminal isn't possible.
- **OQ-5:** scan `~/.claude/projects/*/*.jsonl` at app launch to discover historical sessions. Liveness only guessable by mtime — unreliable; deferred. INV-14 (adopt-on-event) covers the reliable case.

## 7. Task DAG + acceptance gates

```
W1 (SessionOverride.muted + AignalsConfig.soundEnabled — pure logic)
W2 (aignals-hook adopt-on-event — pure shell)
        ↓  (W1, W2 independent — run in parallel)
W3 (UI: sound playback + mute controls + Launch button + Settings fold)  depends_on W1, W2
```

| Task | depends_on | Spec | Acceptance gate |
|---|---|---|---|
| **W1** | — | In `Sources/AignalsCore`: add `muted: Bool` (default false) to `SessionOverride` (Codable, keep existing fields) + an `OverrideStore.setMuted(_:for:)` mutator (persists atomically like the others). Add `soundEnabled: Bool` (default true) to `AignalsConfig` (Codable) so `ConfigStore` round-trips it (existing atomic save). Pure logic, SPM-testable. | `swift test`: `muted` round-trips through OverrideStore reload (default false); `setMuted` toggles + persists; `soundEnabled` round-trips through ConfigStore (default true when absent); full suite green (no regressions to existing OverrideStore/ConfigStore tests). |
| **W2** | — | In `CLI/aignals-hook/aignals-hook`: make the UPDATE-class subcommands create the session file if it doesn't exist, instead of no-op'ing. Today `cmd_on_pretool`/`cmd_set_state` (and the `current_action` writer) early-return when the file is absent (`[ -f "$file" ] || exit 0`). Change them so that on a missing file they CREATE it: write schema_version, session_id, tool, pid (from payload or $PPID), project_name=basename(cwd from payload, fallback $PWD), cwd, started_at=now, updated_at=now, and `state` = the state that subcommand implies (on-prompt/on-pretool/on-posttool/on-permission-denied → working; on-permission → waiting_permission; on-idle/on-stop → waiting_input). `on-sessionend` (cmd_remove) MUST stay a no-op on a missing file (never create-then-delete). Keep INV-8 millisecond updated_at + the reorder guard + atomic writes. Keep every-path-exit-0. | `bats Tests/HookTests/aignals-hook.bats` all green incl. NEW cases: `on-prompt` on a NON-existent file creates it with state=working (adoption, ADR-25/INV-14); `on-stop` on a non-existent file creates it with state=waiting_input; `on-permission` on a non-existent file creates state=waiting_permission; `on-sessionend` on a non-existent file creates NOTHING (no file appears); existing same-second / reorder cases still pass. |
| **W3** | W1, W2 | UI rewrite (files under `App/Aignals/Sources/`; read the CURRENT MenuContent/AppViewModel which were rewritten in v2/the audit fixes). (a) SOUND: observe `store.changes`; when a session transitions INTO waiting_permission or waiting_input, play a macOS system sound (different sound per state, ADR-23) — but ONLY if `config.soundEnabled` AND not `overrideStore.override(id)?.muted`, AND it is not a startup/adoption load, AND not within 3s of the last sound for that session (ADR-22 throttle; track last-played time + a per-session last-state map in the view model; skip sounds during the initial seed and for sessions first seen via adoption). (b) per-row MUTE: add a mute toggle button to each session row writing `OverrideStore.setMuted`; a muted row shows a muted indicator. (c) GLOBAL sound: a control (inside the Settings fold) bound to `AignalsConfig.soundEnabled`. (d) LAUNCH BUTTON: replace the `Toggle("Launch at Login")` with a one-way `menuButton("Enable Launch at Login")` shown only when `!vm.launchAtLogin`, calling the existing launch-at-login enable path and bumping the observable version so it hides immediately (ADR-26). (e) SETTINGS FOLD: collapse Install Claude Code Hooks, Install aignals-hook CLI, Open ~/.aignals, About Aignals, Enable Launch at Login, and the global sound toggle behind a single "Settings" disclosure/expander button; the always-visible menu is the session list + the "Settings" button + Quit (ADR-27/INV-16). Keep the menu-bar label unchanged. Build. | `(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build` → `** BUILD SUCCEEDED **`. Manual smoke (UI not SPM-testable): a session going 🔴→🟡 plays the permission sound; →🟢 plays the input sound; →🔴 is silent; muting a row silences just it; global sound off silences all; app launch with several sessions plays NOTHING; the config items are hidden until "Settings" is expanded; "Enable Launch at Login" disappears after one click. |

## 8. Global commands

- `TEST_CMD` = `swift test`
- `BATS_CMD` = `bats Tests/HookTests/aignals-hook.bats`
- `LINT_CMD` = `swift build`
- `BUILD_CMD` = `(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build`

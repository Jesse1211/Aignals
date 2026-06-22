# DESIGN-v2.md — Per-session meta, rename, reorder, disconnect (feature-factory ledger)

Locked decision ledger for **Aignals v2**. Builds on v1 (multi-status signals, `DESIGN-multistatus.md`).

**Feature in one line:** A minimal `.window`-style dropdown where each session is one row carrying
its meta — colored state dot (incl. a new gray *disconnected*), a **user-editable name**, what it's
doing, and a **live-ticking** elapsed time — and rows can be **reordered by drag**. Plus: when a
session dies passively it turns **gray** (stays, user dismisses it); when the user `/exit`s it is
**auto-removed**.

**Grounding rule (held throughout):** claims about current behavior are verifiable facts; design
intent only with evidence. **Scope cut:** `filter` was considered and dropped (keep it minimal).

**⚠️ BUILD ORDER CONSTRAINT:** v2 MUST be built AFTER the v1 multi-status build delivers. V2's
tasks modify the very files v1 is changing (`SessionState`, `PIDSweeper`, `MenuContent`,
`AignalsApp`). All file:line references below are "as of v1-delivered trunk" — re-verify at build time.

---

## 1. Bounded Context / Domain

- **BC:** `AignalsCore` (unchanged). v2 extends the language with user-preference + disconnect concepts.
- **New boundary (the core v2 decision):** user-chosen data (custom **name**, **order**) must NOT live
  in the hook-owned session file — `aignals-hook` rewrites that file on every event and only knows
  `session_id`, so it would clobber a custom name. User preferences live in an **app-owned**
  `OverrideStore` (`~/.aignals/overrides.json`), keyed by `session_id`, merged onto the Session at
  read time. (ADR-12, INV-9)
- **Aggregate root:** `Session` UNCHANGED — it still holds only hook-written data. Preferences are a
  side-car overlay applied on read; the effective display name is `override.name ?? projectName`
  (derived, not stored). (ADR-18)

## 2. Value objects / entities (v2 additions)

- `SessionOverride` = **Value Object**: `{ name: String?, order: Int? }`, keyed by `session_id`. No
  independent lifecycle — a user annotation on a Session; cleaned when the Session is truly deleted.
- `OverrideStore` = repository persisting `[session_id: SessionOverride]` to `~/.aignals/overrides.json`
  (atomic write, malformed → empty), analogous to v1's `ConfigStore`. Not an aggregate root.
- `SessionState` gains a 4th case `.disconnected` (gray). Value object, as in v1. (ADR-13)

## 3. Lifecycle additions (disconnect)

```
   (v1 states: working 🔴 / waitingPermission 🟡 / waitingInput 🟢)
                          │
   passive death (terminal closed / kill / crash — NO hook fires)
                          │  PIDSweeper poll: kill(pid,0) fails
                          ▼
                   🔘 disconnected (gray) ── user clicks ✕ ──► removed
                          ▲
   active /exit ─► SessionEnd hook ─► file deleted ─► removed (NOT gray)
```

**Evidence (Claude Code hook docs, verified in v1 design):** passive exits fire NO hook; only clean
exits (`/exit`, `/clear`, logout) fire `SessionEnd`. So gray can ONLY be entered by **polling**
(PIDSweeper liveness), never by a hook event. (ADR-14, INV-12)

## 4. Invariants (v2)

- **INV-9:** user preferences (name/order) are NEVER written to a session file — only to OverrideStore.
- **INV-10:** when a session is truly deleted (SessionEnd, or user dismisses a gray light), its override
  is cleaned (no orphan accumulation).
- **INV-11:** ordering — sessions with an `override.order` sort by it; those without sort after, by
  `startedAt`. Order is stable for the user.
- **INV-12:** `.disconnected` is entered ONLY by PIDSweeper polling (pid dead), never by a hook event.
  A subsequent hook event for that session naturally overwrites gray back to a live state (no special
  recovery logic needed — the timestamped write corrects it).

## 5. ADR ledger (continues v1's numbering)

- **ADR-12:** User preferences (name+order) live in app-owned `OverrideStore` (`~/.aignals/overrides.json`),
  keyed by session_id, merged onto Session at read time. *hook rewrites session files and would clobber
  them; preferences must be side-car (INV-9).*
- **ADR-13:** `SessionState` gains `.disconnected` (gray). *New v2 state.*
- **ADR-14:** Gray entered ONLY via PIDSweeper liveness: pid dead → set state `.disconnected` (do NOT
  delete the file — a behavior change from v1 where pid-dead deleted); `/exit` → `SessionEnd` → delete.
  *Passive death has no hook; polling is the only signal.*
- **ADR-15:** Gray lights are dismissed by the user (a remove ✕ on the row); dismissing/deleting a
  session also clears its override. *Gray never auto-disappears; avoid orphans (INV-10).*
- **ADR-16:** New sessions insert at the TOP (newest on top); the user may drag to reorder, persisted
  as `order` in OverrideStore. *Matches the vision; INV-11.*
- **ADR-17:** Migrate the menu UI from `.menu` to `.window` style; rewrite the dropdown as a custom
  SwiftUI view. *tick/rename/swap all need rich interaction that `.menu` (modal NSMenu event loop —
  SwiftUI timers don't fire, no text input, no drag) cannot provide. Verified in v1.*
- **ADR-18:** Effective display name = `override.name ?? projectName` (derived, not stored).
  *Keeps the Session aggregate uncontaminated by preferences.*

## 6. Open Questions

- **OQ-2:** `.window`-style dismiss-on-outside-click / focus behavior — verify at implementation; may
  need tuning (menu windows behave differently from `.menu`).
- **OQ-3:** Drag-reorder mechanism — SwiftUI `.onMove` vs a custom drag. Decide at implementation.

## 7. Task DAG + acceptance gates

```
V1 (OverrideStore + overrides.json)
 │
 ├──► V3 (.window dropdown rewrite)   ◄── also depends on V2
 │
V2 (.disconnected state + PIDSweeper poll → gray)
 └──► V3
```

| Task | depends_on | Spec | Acceptance gate |
|---|---|---|---|
| **V1** | — | In `Sources/AignalsCore`: `SessionOverride` value object `{name:String?, order:Int?}` (Equatable, Sendable, Codable) + `OverrideStore` persisting `[String: SessionOverride]` to `~/.aignals/overrides.json` via `Paths` (atomic temp+replace; malformed → empty `[:]`; honors AIGNALS_HOME). API: `setName(_:for:)`, `setOrder(_:for:)`, `remove(for:)`, `override(for:) -> SessionOverride?`, and `prune(keepingIDs:)` to drop orphans. Pure logic, SPM-testable. | `swift test --filter OverrideStoreTests`: round-trips name+order; `remove`/`prune` drop entries; malformed file → empty defaults (no crash); writes atomic; honors AIGNALS_HOME (INV-9/INV-10). |
| **V2** | — | `SessionState` gains `.disconnected` (it must parse/serialize the string `"disconnected"` for symmetry, BUT NOTE: `.disconnected` is set by the APP (PIDSweeper), never written by `aignals-hook` — the hook never knows a session died passively, so NO new hook subcommand is added here, INV-12). Change `PIDSweeper`: when `kill(pid,0)` shows a pid dead, instead of removing the session from the store, set its in-memory `state` to `.disconnected` (keep it present). The `SessionEnd`/file-delete path is unchanged (still removes). `StatusCounts` may optionally surface a disconnected count, but the menu-bar label spec stays `🔴x 🟡y 🟢z` (gray is shown in the dropdown, not necessarily the label) — keep the label unchanged unless trivially additive. | `swift test --filter PIDSweeperTests` (rewritten): a session whose pid is dead becomes `state == .disconnected` AND is still present in the store (NOT removed); a live-pid session is untouched; the SessionEnd/delete path still removes (ADR-14/INV-12). |
| **V3** | V1, V2 | UI rewrite (files under `App/Aignals/Sources/`). `AignalsApp.swift`: change `.menuBarExtraStyle(.menu)` → `.window`. Rewrite `MenuContent` as a custom SwiftUI view: a minimal vertical list, one row per session = [state color dot incl. gray] + [editable name field showing `override.name ?? projectName`, committing via `OverrideStore.setName`] + [what it's doing subtitle] + [elapsed time that **ticks live every 1s** while open — works now because `.window` is a real SwiftUI view, not a modal NSMenu] + [a remove ✕ button, shown for `.disconnected` rows, calling delete+`OverrideStore.remove`]. Rows are **drag-reorderable**, persisting `order` via `OverrideStore.setOrder`; new sessions appear at the top (INV-11/ADR-16). Keep the menu-bar label (`StatusIcon` count image) unchanged. Keep existing actions (Install hooks/CLI, Open, About, Launch at Login, Quit) present, restyled for `.window`. Minimal aesthetic — no extra info. | `BUILD_CMD` → `** BUILD SUCCEEDED **`. Manual smoke (no SPM test for UI): open dropdown → elapsed ticks live every second; rename a row → persists across reopen (overrides.json updated); drag reorder → persists; a gray (disconnected) row shows the ✕ and removing it deletes the session + its override. |

## 8. Global commands

- `TEST_CMD` = `swift test`
- `BATS_CMD` = `bats Tests/HookTests/aignals-hook.bats`
- `LINT_CMD` = `swift build`
- `BUILD_CMD` = `(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build`

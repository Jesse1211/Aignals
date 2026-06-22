# DESIGN.md — Multi-Status Signals (feature-factory ledger)

Locked decision ledger for the **multi-status signal** feature. This is the unambiguous
contract the hands-off build consumes — no human in the build loop after this file is locked.

**Feature in one line:** Each Claude Code session gets its own lifecycle *state*
(working / waiting-permission / waiting-input); the menu bar shows a compact count
`🔴x 🟡y 🟢z` of how many sessions are in each state; the dropdown shows per-session detail.

**Grounding rule (held throughout design):** "not built" ≠ "not supported" ≠ "design
assumes the opposite." Claims about current behavior are verifiable facts; design intent is
only asserted with evidence (code/comment/schema/API semantics).

---

## 1. Bounded Context / Domain

- **BC:** `AignalsCore` (existing). The feature deepens this observation domain's language; it
  does not introduce a new BC. (ADR-1)
- **Boundary:**
  - **Owned (inside the line, modeled freely):** `Session` aggregate (+ new `state`),
    `SessionState` value object, `StatusCounts` value object, `SessionStore`
    (collection repository + derived counts), the state-transition rules.
  - **Referenced only (across the line, never reached into):**
    - `~/.aignals/sessions/*.json` files — **the protocol**. `aignals-hook` *writes*,
      `AignalsCore` *reads*. Core never writes these files. (ADR-2)
    - `aignals-hook` (bash CLI) — an independent producer in another process/language.
      Core consumes its output files; it does not call or depend on its implementation.
    - Claude Code — outermost event source; feeds events to `aignals-hook` via hooks.
    - UI layer (`StatusIcon`/`MenuContent`/`AignalsApp`) — consumes Core, holds no domain logic.
- **Aggregate root:** `Session` (unchanged root, gains `state`). One session file = one
  `Session` instance; the file is its persistence + transaction boundary. `StatusCounts`
  is **not** a root — it is derived by `SessionStore`. `SessionStore` is the repository +
  derived-count host, not a domain root. (ADR-3)
- **Entity vs Value Object:**
  - `Session` = **Entity** (identity = `session_id`; survives state changes).
  - `SessionState` = **Value Object** (enum; no identity; compared by value).
  - `StatusCounts` = **Value Object** (`{working, waitingPermission, waitingInput}`; immutable; by value).
  - `CurrentAction` = Value Object (already is). (ADR-4)
- **References:** `Session` holds **no domain-aggregate references** — only its own ID +
  value objects, plus a weak OS-process ref (`pid`, read-only liveness via `kill(pid,0)`).
  The feature adds no new cross-aggregate reference.

## 2. Ubiquitous Language

| Term | Meaning | File schema value |
|---|---|---|
| Session | A Claude Code session instance, id = `session_id` | file `<session_id>.json` |
| **working** | Claude is actively working (generating / running a tool); user should wait | `"state":"working"` 🔴 |
| **waitingPermission** | Claude is blocked on a permission prompt; user must click Allow | `"state":"waiting_permission"` 🟡 |
| **waitingInput** | Claude finished a turn / just started; waiting for the user's next message | `"state":"waiting_input"` 🟢 |
| StatusCounts | Per-state session counts `{working, waitingPermission, waitingInput}` | in-memory only, derived |

- Swift uses camelCase (`.waitingPermission`); JSON uses snake_case (`"waiting_permission"`),
  matching the existing `current_action` style and easier bash emission.
- **🟢 is named `waitingInput`, NEVER `idle`** — "idle" historically meant "no sessions"
  (`AggregateStatus.idle`), a different concept. (SF-1 → ADR-9)

## 3. Lifecycle (state machine — evidence-corrected against Claude Code hook docs)

```
   SessionStart ─────────────► 🟢 waitingInput
                                     │ UserPromptSubmit
                                     ▼
   ┌─────────────────────────► 🔴 working ◄──────────────┐
   │ PostToolUse (allow)            │  │                  │
   │ PermissionDenied (deny)        │  │ Stop /           │
   │                                │  │ Notification:    │  (turn finished)
   🟡 waitingPermission ◄───────────┘  │ idle_prompt      │
       Notification:permission_prompt   │                 │
                                        ▼                 │
                                   🟢 waitingInput ────────┘
   [any state] SessionEnd ─► file deleted ─► signal removed
```

| From | To | Hook |
|---|---|---|
| (none) | 🟢 waitingInput | `SessionStart` |
| 🟢 → 🔴 working | | `UserPromptSubmit` |
| 🔴 → 🟡 waitingPermission | | `Notification:permission_prompt` |
| 🟡 → 🔴 working | | `PostToolUse` (allow) / `PermissionDenied` (deny) |
| 🔴 → 🟢 waitingInput | | `Stop` / `Notification:idle_prompt` |
| any → removed | | `SessionEnd` |

**Evidence (Claude Code hooks docs, verified 2026-06):**
- Tool lifecycle order is `PreToolUse → PermissionRequest → PostToolUse` (allow) or
  `→ PermissionDenied` (deny). There is **no** hook at the exact "user clicked Allow" moment;
  the 🟡→🔴 transition is inferred from `PostToolUse`/`PermissionDenied`. (ADR-6)
- Hooks are synchronous (Claude blocks on the command), BUT **inter-event ordering across
  different hook events is undocumented** — must defend against reordering. (→ ADR-7)

## 4. Invariants

- **INV-1:** a session is in exactly one state at a time (single `state` value).
- **INV-2:** `state` is a required field of schema v2; files lacking it are treated as dirty
  and ignored (cannot occur in practice — no pre-release hook exists). (ADR-10)
- **INV-3:** state changes only via legal transitions (§3); reordering defended by INV-8.
- **INV-4:** `working + waitingPermission + waitingInput == number of active sessions`
  (counts never desync from the `sessions` array). Counts are derived.
- **INV-5:** a state group whose count is 0 is hidden in the menu bar. (ADR-11)
- **INV-6:** deleting a session file removes the session from all counts.
- **INV-7:** a state change rewrites the file (jq field update + atomic write), it does not
  delete-and-recreate (avoids flicker).
- **INV-8:** every write carries a monotonic `updated_at`; a state overwrite is accepted ONLY
  if its `updated_at` is newer than the stored one — stale (reordered) events are dropped. (ADR-7)

## 5. ADR ledger

- **ADR-1:** Feature stays in `AignalsCore` BC. *Same observation domain, self-consistent language.*
- **ADR-2:** State semantics live in the file schema (`state` field); `aignals-hook` writes,
  `AignalsCore` reads. *File is the protocol; bash + swift share one contract.*
- **ADR-3:** `Session` (aggregate root) gains `state`; `StatusCounts` is a derived value object.
  *State is intrinsic to a session; counts are derived.*
- **ADR-4:** `SessionState` and `StatusCounts` are value objects (enum / immutable struct).
  *No identity; cross-language they travel as plain strings/numbers.*
- **ADR-5:** v1 ships three states (working/waitingPermission/waitingInput); gray "disconnected"
  is deferred to v2. *YAGNI; all three have clean hooks, gray has no reliable hook.*
- **ADR-6:** State machine per §3, evidence-corrected: 🟡→🔴 via `PostToolUse` (allow) /
  `PermissionDenied` (deny), since no hook fires at the click moment. *Per Claude Code hook docs.*
- **ADR-7:** INV-8 — every write carries `updated_at`; stale events dropped. *Inter-event hook
  ordering is undocumented; assume worst, defend with monotonic timestamps.*
- **ADR-8:** Yellow stays lit indefinitely until allow/deny/session-end (SF-2); rapid
  yellow↔red flicker is expected and NOT suppressed. *Yellow = "go click Allow"; correct behavior.*
- **ADR-9:** Delete `AggregateStatus`; replace with `StatusCounts {working, waitingPermission,
  waitingInput}` + a separate `hasError: Bool`. `SessionStore.changes` stream emits `StatusCounts`.
  Rewrite tests depending on the old enum. *Unifies the status concept (SF-1).* **Note for build:**
  the two extra duties `AggregateStatus` carried must be re-homed: (1) `.error` → `hasError: Bool`;
  (2) `changes: AsyncStream<AggregateStatus>` → `AsyncStream<StatusCounts>`.
- **ADR-10:** `schema_version = 2`, `state` required; no backward compatibility. *v0.1.0 unreleased.*
- **ADR-11:** Menu bar renders `🔴x 🟡y 🟢z`; a group with count 0 is hidden. *User-specified display.*

## 6. Open Questions

- **OQ-1:** Cleanup of "stuck" lights for abruptly-killed sessions (terminal closed / `kill`,
  no `SessionEnd` hook). v1 does NOT actively design for this; the existing `PIDSweeper` liveness
  + 24h mtime backstop may incidentally clear them, but the feature does not depend on it.
  Real solution (with gray "disconnected" state) is v2.

## 7. Task DAG + acceptance gates

```
T1 (schema contract + SessionState)
 ├──► T2 (aignals-hook write side + bats)
 └──► T3 (Session.state + StatusCounts + SessionStore rework + tests)
            ├──► T4 (StatusIcon count rendering)
            ├──► T5 (MenuContent + AignalsApp wiring)
            └──► T6 (HookInstaller multi-event registration)
```

| Task | depends_on | Spec | Acceptance gate |
|---|---|---|---|
| **T1** | — | `SessionState` value object (enum + snake_case JSON parse, unknown → nil/dropped); bump `schema_version` to 2; `state` required; define `updated_at` monotonic convention | `swift build` green; `SessionStateTests` cover the 3 state strings round-trip + unknown-value handling (INV-1) |
| **T2** | T1 | `aignals-hook` subcommands write correct state + `updated_at`. **Existing (change behavior):** `on-sessionstart`→writes `state:waiting_input`, `on-pretool`→`state:working`+action, `on-stop`→`state:waiting_input` (NO LONGER deletes — see note), `on-sessionend`→delete file. **New subcommands to add:** `on-prompt` (UserPromptSubmit)→`working`, `on-permission` (Notification:permission_prompt)→`waiting_permission`, `on-posttool` (PostToolUse)→`working`, `on-permission-denied` (PermissionDenied)→`working`, `on-idle` (Notification:idle_prompt)→`waiting_input`. Each write stamps `updated_at`; overwrite only if the incoming event is newer (INV-8). **Behavior change note:** under the old model `on-stop` deleted the file (green=gone); under the new model `Stop`/idle means `waiting_input` (🟢 lit, session still present) and only `SessionEnd` deletes. | `bats Tests/HookTests/aignals-hook.bats` all green; new cases: each subcommand writes the right state (ADR-6); `on-stop` leaves the file present with `state:waiting_input` (not deleted); a write carrying an older `updated_at` than the stored one is dropped (INV-8/ADR-7) |
| **T3** | T1 | `Session` gains `state`; `StatusCounts` value object; `SessionStore`: remove `aggregateStatus`, add `statusCounts` + `hasError`, `changes` emits `StatusCounts`; INV-8 defense (drop stale-timestamp updates); rewrite tests depending on the old enum | `swift test` all green incl. rewritten tests; counts == active session count (INV-4); a stale-timestamp event does not overwrite a newer state (INV-8); error state preserved via `hasError` (ADR-9) |
| **T4** | T3 | `StatusIcon` renders `🔴x 🟡y 🟢z`; a 0-count group is not drawn | `StatusIconTests`: given a `StatusCounts`, produces a non-empty image; a 0-count group is omitted (INV-5/ADR-11) |
| **T5** | T3 | `MenuContent` rows show per-session state color dot; `AignalsApp` label binds `StatusCounts`; error state adapted | `BUILD_CMD` → `** BUILD SUCCEEDED **` (UI has no unit tests; CI/build gate) |
| **T6** | T3 | `HookInstaller` registers all new events (UserPromptSubmit, Notification, PostToolUse, etc.); `isInstalled` adapted | `HookInstallerTests`: after install, settings.json contains all new event commands; idempotent; preserves user's pre-existing hooks |

## 8. Global commands

- `TEST_CMD` = `swift test`
- `BATS_CMD` = `bats Tests/HookTests/aignals-hook.bats`
- `LINT_CMD` = `swift build` (no separate linter; build doubles as typecheck)
- `BUILD_CMD` = `(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build`

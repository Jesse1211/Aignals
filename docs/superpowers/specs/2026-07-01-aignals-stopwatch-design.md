# Aignals — Work Stopwatch (Design)

**Date:** 2026-07-01
**Status:** Approved (brainstorming complete)
**Scope:** Standalone menubar feature that tracks actual daily work time. Fully independent of session monitoring — MUST NOT couple to any session logic. Depends on the Daily Quote feature only for `sendCurrentQuoteToFeishu()` (built there, Task 9.5).

## Goal

Track how much a user actually works each day. Start = clock in, Stop = break, Resume = back to work, End = clock out (or auto-end after local midnight). Each End (and each stop/midnight cut) seals the elapsed segment to a per-day work log. A Stat window shows history by day, expandable to per-segment detail.

## Non-Goals

- Not a countdown/timer (it is a stopwatch).
- No editing/deleting of logged history (work records are facts; read-only).
- No YouTube (deferred), no session coupling.

## State Machine

Three states:
- **idle** — not started today, or already ended.
- **running** — clocked in, accumulating.
- **stopped** — on break (paused, frozen).

Actions and legal transitions:
- **Start** (idle → running): begin a new segment now.
- **Stop** (running → stopped): seal the current segment to the work log; freeze.
- **Resume** (stopped → running): begin a new segment now.
- **End** (running or stopped → idle): if running, seal the current segment; day is done.
- **Midnight auto-end / cross-midnight recovery**: see below.

Buttons show only the legal actions for the current state (not disabled-greyed):
- idle → `Start`
- running → `Stop` `End`
- stopped → `Resume` `End`
- `Stat` is always present.

A "segment" = one continuous Start→(Stop | End | midnight-cut) span of work. Breaks (stopped intervals) are NOT segments and never enter the work log.

## Wall-Clock Recovery & Midnight Cut (shared logic)

The running state survives app quit / restart / sleep and resumes by real wall-clock time (time while the app was closed **counts**). The engine reconstructs elapsed from `accumulatedSeconds + (now - currentSegmentStart)`.

**Midnight cut** — a single rule used by BOTH the live midnight auto-end and cross-midnight recovery:

- If, at evaluation time (`now`), the current running segment's `currentSegmentStart` is on an earlier local day than `now`, the segment is **cut at 23:59:59 of its start day** and sealed to that day's work log.
- **Days fully spanned while closed produce NO records** (e.g. Fri 23:00 start, reopened Mon → only Fri gets a 23:00–23:59:59 segment; Sat/Sun get nothing).
- After the cut, the current day starts fresh at 0 in the **stopped** state (the user must manually Start again). We do NOT auto-continue into the new day.

Live behavior (app open): when the clock crosses local midnight while running, the same cut fires — seal yesterday's segment at 23:59:59, drop to stopped/0 for today.

Rationale: "12am auto-end" and "closed across midnight" are the same operation — seal the start day at 23:59:59, skip fully-spanned days, reset today.

## Persistence (two files, separated by responsibility)

### `~/.aignals/stopwatch-state.json` — volatile running state
```json
{
  "version": 1,
  "state": "running",              // idle | running | stopped
  "day": "2026-07-01",             // local day the accumulation belongs to
  "accumulatedSeconds": 5400,      // sealed-into-today time not yet ended
  "currentSegmentStart": "2026-07-01T10:45:00Z"  // null when not running
}
```
- Written on Start / Stop / Resume / End / midnight-cut.
- `accumulatedSeconds` holds today's completed-but-not-ended segments' sum so a stopped→resume→display is correct without re-reading the worklog.
- Missing/corrupt → treat as idle, fresh day.

### `~/.aignals/worklog.json` — sealed history
```json
{
  "version": 1,
  "days": {
    "2026-07-01": {
      "totalSeconds": 9900,
      "segments": [
        { "start": "2026-07-01T09:00:00Z", "end": "2026-07-01T10:30:00Z", "seconds": 5400 },
        { "start": "2026-07-01T10:45:00Z", "end": "2026-07-01T12:00:00Z", "seconds": 4500 }
      ]
    }
  }
}
```
- Key = **local date** `YYYY-MM-DD` (same timezone basis as the midnight rule).
- A segment is appended the moment it ends (Stop / End / midnight-cut). Running never writes here.
- `totalSeconds` = sum of that day's segments (redundant, for cheap Stat reads).
- `start`/`end` stored as UTC ISO-8601; displayed in local time.
- Atomic write (temp + `replaceItemAt`), missing/corrupt → empty.

## UI

### Menubar dropdown — stopwatch region
- A `hh:mm:ss` display of today's elapsed work (`accumulatedSeconds + (now - currentSegmentStart)` when running; frozen `accumulatedSeconds` when stopped; `00:00:00` when idle).
- Driven by `MenuContent`'s existing 1-second `Timer.publish` tick (reused display signal only — stopwatch DATA is independent of sessions).
- Action buttons per state (above) + a `Stat` button.

### Stat window
- Dedicated `Window(id: "stat")` opened via `openWindow` (NOT a `.sheet` — the `.window` MenuBarExtra panel dismisses sheets on focus loss; matches the Settings/Projector pattern).
- A by-day list, newest first: each row `date + total` (e.g. `2026-07-01   7h 30m`).
- Click a day to expand its segments: `09:00–10:30 (1h 30m)` in local time.
- Read-only (no delete). Shows only sealed segments — the currently-running segment is NOT counted until it ends.
- Empty state: "No work logged yet."

## Feishu on Start (reuses Quote feature's hook)

- On **idle → Start only** (the first clock-in of the day), call `AppViewModel.sendCurrentQuoteToFeishu()` (built in the Quote feature, Task 9.5).
- **Resume does NOT send** (returning from a break should not re-notify).
- That method already guards: no-op when Feishu is disabled/unconfigured or today's quote is `—`. So Start always works; the send is best-effort and silent on failure.

## Upgrade / No Data Loss

- User data lives in `~/.aignals/` (home dir); the app binary is separate. Upgrades replace only `Aignals.app` and never touch `~/.aignals/`.
- Load reads the latest from disk; writes use atomic `replaceItemAt`. No blind in-memory overwrite clobbers external changes.
- JSON is back-compatible: `decodeIfPresent ?? default` for new fields; each file carries a `version`. Adding fields never fails to decode old files.
- Only Uninstall deletes data, and its "Keep my saved data (work log & quotes)" checkbox already preserves `worklog.json` (and `quotes.json`). No FSEvents live-reload — unnecessary for this low-frequency single-instance data.

## Architecture — Core units (unit-testable, zero session coupling)

- **`StopwatchEngine`** — pure state machine + wall-clock math + midnight cut, with an **injected clock/calendar**. Given (current persisted state, action or "evaluate now", now) it returns (new state, zero-or-more segments to seal). All the error-prone logic (12am cut, cross-midnight recovery, multi-day span) lives here and is fully unit-tested with a fake clock.
- **`StopwatchStateStore`** — read/write `stopwatch-state.json` (atomic, corrupt→idle).
- **`WorklogStore`** — read/write `worklog.json`; append a segment to a local day, maintain `totalSeconds`, expose days newest-first for Stat.
- **`WorktimeFormatter`** — seconds → `hh:mm:ss` and → `7h 30m`.

App-layer wiring (`AppViewModel` + menubar region + Stat window) coordinates these and reuses the 1-second tick and `sendCurrentQuoteToFeishu()`.

## Testing & Acceptance

Dev agent implements; an INDEPENDENT test agent verifies each gate.

### Unit tests (Core)
- **StopwatchEngine** (fake clock): start→running; stop seals a segment; resume starts a new segment; end seals + idle; running elapsed = accumulated + wall delta; **midnight cut** seals start-day at 23:59:59 and resets today to stopped/0; **multi-day span** seals only the start day, no records for spanned days; recovery from a running state after quit continues by wall clock.
- **WorklogStore**: append segment to a day; totalSeconds accumulates; days newest-first; corrupt→empty; atomic round-trip.
- **StopwatchStateStore**: round-trip; corrupt/missing→idle.
- **WorktimeFormatter**: `0→00:00:00`, `9900→02:45:00`, `9900→"2h 45m"`, `<1m` cases.

### Manual integration checklist
- Start shows running `hh:mm:ss` ticking; Stop freezes; Resume continues; End resets to idle and appends to worklog.
- Buttons match state (idle=Start; running=Stop/End; stopped=Resume/End).
- Quit while running, reopen later same day → time continued by wall clock.
- Cross local midnight while running (or reopen next day) → yesterday sealed at 23:59:59, today starts at 0 stopped.
- Stat window lists days newest-first with totals; expanding shows local-time segments; empty state before any log.
- With Feishu configured + a quote loaded, the first Start of the day posts the quote; Resume does not.
- `worklog.json` / `stopwatch-state.json` exist under `~/.aignals/` with the documented shapes; an upgrade (replace the .app) preserves them.

### Acceptance gate
Test agent verifies line-by-line: all unit tests green + every manual checklist item passes.

## Key Constraints

- **Decoupling (hard):** stopwatch code shares NO logic with session monitoring; only the 1-second UI tick signal is shared.
- All error-prone time logic in `StopwatchEngine` behind an injected clock — no `Date()` calls scattered in the engine.
- Follow existing patterns: `~/.aignals/` data dir, atomic writes, dedicated `Window` for the Stat view.
- Depends on the Quote feature's `sendCurrentQuoteToFeishu()` — the Quote feature must be implemented first (or at least that method must exist).

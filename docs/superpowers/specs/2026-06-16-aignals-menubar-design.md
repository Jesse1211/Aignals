# Aignals — macOS Menu Bar Indicator: Design Spec

**Date:** 2026-06-16
**Status:** Approved (brainstorming complete)
**Scope:** First release (v0.1) — single-purpose, single-user, English only

---

## 1. Summary

Aignals is a native macOS menu bar app that visualizes AI coding agent activity in real time. A red dot means at least one agent session is running; a green dot means everything is idle. State is driven by the agent's own lifecycle hooks writing JSON files into `~/.aignals/sessions/`. The app watches that directory via FSEvents and renders the aggregate state.

The first integration target is Claude Code via its `~/.claude/settings.json` hooks, but the file-based protocol is intentionally open: any tool that can write a JSON file can drive the indicator.

## 2. Goals & Non-Goals

### Goals
- Glanceable status — red = busy, green = idle — from the menu bar.
- Per-session detail in the dropdown: project name, current action, elapsed time.
- Zero-friction install path for Claude Code users.
- Open, file-based protocol so other tools can integrate without code changes to Aignals.
- Survive agent crashes (orphaned `running` state) gracefully.

### Non-Goals (YAGNI, deferred or never)
- Notification Center notifications ("session finished").
- Session history, statistics, or time tracking.
- Custom icon colors / themes.
- Multi-device sync.
- Auto-update (Sparkle). Users update via `brew upgrade` or re-download.
- Apple Developer notarization (self-signed only for v0.1).
- Internationalization (English only for v0.1).

## 3. Architecture Overview

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  Claude Code (or other)  │         │       Aignals.app        │
│                          │         │   (SwiftUI MenuBarExtra) │
│  ~/.claude/settings.json │         │                          │
│   ├─ SessionStart hook ──┼──┐      │  ┌────────────────────┐  │
│   ├─ PreToolUse  hook ───┼──┤      │  │ SessionStore       │  │
│   ├─ Stop        hook ───┼──┤      │  │  (@MainActor,      │  │
│   └─ SessionEnd  hook ───┼──┤      │  │   single source)   │  │
└──────────────────────────┘  │      │  └─────────┬──────────┘  │
                              ▼      │            │             │
                  ┌─────────────────┐│  ┌─────────┴──────────┐  │
                  │ ~/.aignals/     ││  │ FSEventsWatcher    │  │
                  │  sessions/      │┼─►│  (file changes)    │  │
                  │   <id>.json     ││  └─────────┬──────────┘  │
                  │   <id>.json     ││            │             │
                  │   ...           ││  ┌─────────┴──────────┐  │
                  └─────────────────┘│  │ PIDSweeper         │  │
                                     │  │  (every 5s)        │  │
                                     │  └─────────┬──────────┘  │
                                     │            │             │
                                     │  ┌─────────┴──────────┐  │
                                     │  │ MenuBarView        │  │
                                     │  │  (icon + dropdown) │  │
                                     │  └────────────────────┘  │
                                     └──────────────────────────┘
```

Three roles:

1. **Producer (hook side):** Claude Code lifecycle hooks invoke a small shell CLI (`aignals-hook`) that atomically writes / updates / removes `~/.aignals/sessions/<session_id>.json`.
2. **Protocol (filesystem):** The directory's contents *are* the state. Aignals knows nothing about Claude Code internals.
3. **Consumer (app side):** Aignals watches the directory, parses each JSON file into a `Session`, and renders the aggregate state plus a per-session dropdown.

Implementation: native macOS app, **SwiftUI `MenuBarExtra`**, minimum macOS 13 (Ventura). Image drawing for the colored status dot drops to AppKit `NSImage` to bypass template tinting.

## 4. State File Schema & Protocol

### Directory layout

```
~/.aignals/
├── sessions/                    # One directory = single aggregation source
│   ├── <session_id>.json        # One file = one active session
│   └── ...
└── config.json                  # User preferences (launch-at-login, dismissed prompts)
```

Both `~/.aignals/` and `~/.aignals/sessions/` are created with mode `0700` (user only). `aignals-hook` and the app both ensure this on first access; if directories already exist with looser permissions, they are left as-is (the user may have made an informed choice).

### Session file schema (`sessions/<session_id>.json`)

```json
{
  "schema_version": 1,
  "session_id": "claude-code-7f3a1b",
  "tool": "claude-code",
  "pid": 48217,
  "project_name": "Aignals",
  "cwd": "/Users/jesseliu/Desktop/Chore/Aignals",
  "started_at": "2026-06-16T14:52:08Z",
  "current_action": {
    "tool": "Edit",
    "target": "main.swift",
    "updated_at": "2026-06-16T14:54:31Z"
  }
}
```

### Fields

| Field | Required | Purpose |
|---|---|---|
| `schema_version` | ✅ | Always `1` for v0.1. Files with unknown versions are ignored. |
| `session_id` | ✅ | Must equal the file's basename (without `.json`). For Claude Code, comes from the `session_id` field of the hook stdin payload. |
| `tool` | ✅ | Identifies the producer (`"claude-code"`, `"cursor"`, free string). |
| `pid` | ⬜ | Optional. When present, `PIDSweeper` uses it to detect orphans. `aignals-hook` writes `$PPID` (the Claude Code process that invoked the hook) at SessionStart. Producers without a meaningful PID may omit the field, in which case orphan cleanup falls back to the mtime backstop. |
| `project_name` | ✅ | First line shown in the dropdown. Hook typically uses `basename "$PWD"`. |
| `cwd` | ⬜ | Tooltip / detail only. |
| `started_at` | ✅ | ISO 8601 UTC. Drives the "2m" elapsed indicator. |
| `current_action` | ⬜ | May be absent. `tool` + `target` are free strings (not constrained to Claude's tool names). |

### Lifecycle protocol

```
SessionStart  →  atomically write sessions/<id>.json (pid + started_at, no current_action)
PreToolUse    →  atomically update current_action
Stop          →  rm sessions/<id>.json
SessionEnd    →  rm sessions/<id>.json  (same as Stop)
```

**Atomic write** = write `sessions/<id>.json.tmp` → `mv` to the final name. Required so FSEvents never observes a half-written file. Documented as a hard requirement for any producer.

### Openness

Any tool that writes files following this schema can drive Aignals. The repository ships `examples/`:

- `examples/claude-code/` — drop-in `settings.json` hook snippets + a sample shell wrapper.
- `examples/generic/bash/` — minimal example for arbitrary scripts (CI, build pipelines, etc.).

### Orphan handling

`PIDSweeper` runs every 5 seconds and, for each file in `sessions/`:

- If the file has a `pid`:
  - `kill(pid, 0)` returns success → process is alive, leave the file.
  - `kill` returns `ESRCH` → process is dead, delete the file and refresh the UI.
  - `kill` returns `EPERM` (process exists but isn't ours) → treat as alive.
- If the file has no `pid` (or the field is null): fall through to the mtime rule.
- **Mtime backstop:** any file whose mtime is older than 24 hours is deleted regardless of pid state. Covers stale files left by tools that don't write a pid, recycled pids, and crash modes the pid check can't catch.

## 5. Hook-Side Contract (Claude Code Integration)

### `aignals-hook` CLI

A small POSIX shell script bundled with the app. Subcommands map 1:1 to Claude Code hook event types. The CLI reads the hook payload from **stdin** (Claude Code's documented mechanism) as a JSON object containing at minimum `session_id`, `cwd`, `hook_event_name`, and (for `PreToolUse`) `tool_name` + `tool_input`. The CLI uses `jq` to extract relevant fields; users never write `jq` in their `settings.json`.

```bash
aignals-hook on-sessionstart    # writes sessions/<id>.json
aignals-hook on-pretool         # updates current_action
aignals-hook on-stop            # removes sessions/<id>.json
aignals-hook on-sessionend      # removes sessions/<id>.json
```

### Field extraction (`on-pretool`)

Maps `tool_name` + `tool_input` from the stdin payload into `current_action`:

| `tool_name` | `current_action.tool` | `current_action.target` (extracted from `tool_input`) |
|---|---|---|
| `Bash` | `Bash` | `.command` (truncated to 80 chars) |
| `Edit` / `Write` / `MultiEdit` | `Edit` / `Write` / `MultiEdit` | `.file_path` |
| `Read` | `Read` | `.file_path` |
| `Grep` | `Grep` | `.pattern` |
| `Glob` | `Glob` | `.pattern` |
| `WebFetch` | `WebFetch` | `.url` |
| `WebSearch` | `WebSearch` | `.query` |
| anything else | the raw tool name | `""` (empty target) |

Internally each subcommand writes via the `tmp → mv` pattern. The CLI depends only on `bash`, `jq`, `mv`, `rm`, `mkdir`, `date`. macOS ships all of these except `jq`, which is required (the CLI checks and prints a one-line install hint on first miss).

**Base directory override:** the CLI honors `AIGNALS_HOME` (defaults to `~/.aignals`) so tests can redirect writes to a temp dir. The app uses the same default and the same override (via `Paths`).

### User's `~/.claude/settings.json` snippet

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "aignals-hook on-sessionstart" }
      ]}
    ],
    "PreToolUse": [
      { "hooks": [
        { "type": "command", "command": "aignals-hook on-pretool" }
      ]}
    ],
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "aignals-hook on-stop" }
      ]}
    ],
    "SessionEnd": [
      { "hooks": [
        { "type": "command", "command": "aignals-hook on-sessionend" }
      ]}
    ]
  }
}
```

`matcher` is intentionally omitted so each hook fires for every event of its type. (Claude Code's `matcher` filters by sub-type — e.g. tool name for `PreToolUse`, `compact` for `SessionStart` — and accepts no wildcard.)

Both `Stop` and `SessionEnd` are installed so the indicator clears regardless of how the session terminates.

### Installation flow

Menu item: **"Install Claude Code Hooks…"**

- Reads `~/.claude/settings.json` (creates if absent).
- Merges the Aignals hook entries into the existing `hooks.*` arrays without overwriting unrelated entries.
- Writes atomically (`.tmp` + `mv`).
- Reports the outcome via a native alert.

On first launch, if `aignals-hook` is not detected in `settings.json`, Aignals shows the install prompt exactly once (see §7).

## 6. App Architecture

```
Aignals.app  (SwiftUI MenuBarExtra)
│
├── AignalsApp.swift                 entry point; declares MenuBarExtra; starts services
│
├── Model/
│   └── Session.swift                Codable struct mirroring the schema in §4
│
├── Services/
│   ├── Paths.swift                  resolves base directories (overridable for tests)
│   ├── SessionStore.swift           single source of truth; @Observable; holds [Session]
│   ├── FSEventsWatcher.swift        watches ~/.aignals/sessions/, calls SessionStore
│   ├── PIDSweeper.swift             5s timer; kill(pid, 0); mtime backstop; FS-access check
│   └── LaunchAtLogin.swift          SMAppService wrapper
│
├── Views/
│   ├── StatusIcon.swift             renders the colored dot NSImage from aggregateStatus
│   └── MenuContent.swift            dropdown: session list + preferences + Quit
│
└── Hook/
    └── InstallHooksCommand.swift    merges Aignals hooks into ~/.claude/settings.json
```

### Responsibilities

| Module | Does | Does not |
|---|---|---|
| `Paths` | Resolve `~/.aignals/sessions/` and config paths; accept an override base for tests | Watch / read state |
| `Session` | Decode/validate one JSON file | Know where the store is |
| `SessionStore` | Maintain `[Session]`; expose `aggregateStatus` (`.idle` / `.running` / `.error`); accept `setFSAccessError(_:)` from sweeper/watcher | Read files directly; draw UI |
| `FSEventsWatcher` | Forward file change events to the store | Parse JSON contents |
| `PIDSweeper` | Detect dead pids and stale files; tell store to remove; on every tick verify the sessions dir is readable and call `setFSAccessError` on the store accordingly | Read individual file contents |
| `StatusIcon` | Render the `NSImage` (colored dot, `isTemplate = false`) | Touch business logic |
| `MenuContent` | Render the dropdown from `SessionStore.sessions` | Read anything else |
| `InstallHooksCommand` | One-shot merge of hook snippet into `~/.claude/settings.json` | Watch files |
| `LaunchAtLogin` | `SMAppService.mainApp.register / unregister` | Anything else |

### Data flow (one round trip)

1. Claude `SessionStart` → `aignals-hook on-sessionstart` → atomic write of `sessions/abc.json`.
2. FSEvents fires `FSEventsWatcher.onChange("sessions/abc.json")`.
3. `SessionStore.upsert(path:)` reads, decodes, inserts.
4. `@Observable` triggers re-render: `StatusIcon` flips to red; `MenuContent` shows the new row.
5. On `Stop` / `SessionEnd` → file removed → `SessionStore.remove(id:)` → array empty → `aggregateStatus = .idle` → icon flips green.

### Aggregate status rule

```swift
enum AggregateStatus { case idle, running, error }

var aggregateStatus: AggregateStatus {
    if hasFSAccessError { return .error }
    return sessions.isEmpty ? .idle : .running
}
```

"Any session present" = running. An empty `current_action` does **not** count as idle: the session itself is still alive, it just isn't using a tool at that exact moment.

### Threading

- FSEvents callbacks run on their own dispatch queue; `SessionStore` writes hop to `@MainActor`.
- `PIDSweeper` uses `Timer.scheduledTimer` on the main run loop.
- Single-threaded model end-to-end inside `SessionStore`; no locks needed.

## 7. UI Detail

### Menu bar icon

Fixed 18×18 pt. Three states:

| State | Visual | Color |
|---|---|---|
| `.running` (any session exists) | filled circle | `NSColor.systemRed` |
| `.idle` (no sessions, app healthy) | filled circle | `NSColor.systemGreen` |
| `.error` (cannot access `~/.aignals/`) | filled circle with hollow inner outline | `NSColor.systemGray` |

Drawn via `NSImage(size:flipped:drawingHandler:)`. `isTemplate = false` so the system does not force a tint. Diameter 10 pt, centered. Pre-generated once per state and assigned to `statusItem.button.image` on change.

### Dropdown — active state

```
┌─────────────────────────────────────────┐
│  Active Sessions                        │
├─────────────────────────────────────────┤
│  ● Aignals                              │
│     Editing main.swift · 2m             │
├─────────────────────────────────────────┤
│  ● dotfiles                             │
│     Running Bash · 14s                  │
├─────────────────────────────────────────┤
│  Launch at Login              [toggle]  │
│  Install Claude Code Hooks…             │
│  Open ~/.aignals                        │
│  ─────────────────────────────────      │
│  About Aignals…                         │
│  Quit Aignals                    ⌘Q     │
└─────────────────────────────────────────┘
```

### Dropdown — empty state

```
┌─────────────────────────────────────────┐
│  No active sessions                     │
├─────────────────────────────────────────┤
│  Launch at Login              [toggle]  │
│  Install Claude Code Hooks…             │
│  Open ~/.aignals                        │
│  ─────────────────────────────────      │
│  About Aignals…                         │
│  Quit Aignals                    ⌘Q     │
└─────────────────────────────────────────┘
```

### Session row formatting

- **Line 1:** small red dot + `project_name` (SwiftUI `.body`).
- **Line 2:** subtitle, `.caption`, secondary color.
  - With `current_action`: `"{verb} {target} · {elapsed}"`.
    - Verb mapping from `current_action.tool`:
      - `Edit` / `Write` → `"Editing"`
      - `Bash` → `"Running"`
      - `Read` → `"Reading"`
      - `Glob` / `Grep` → `"Searching"`
      - everything else → the raw `tool` string, title-cased
  - Without `current_action`: `"Active · {elapsed}"`.
- **`elapsed`:** `started_at` → now. `<60s` shows seconds, `<60m` shows minutes, `<24h` shows hours, otherwise days. A single `Timer.publish(every: 30)` re-renders elapsed labels every 30 seconds while the menu is observable. No special handling when the menu is closed.

### Error display

If `~/.aignals/sessions/` is unreadable, icon goes gray and the top of the menu shows `⚠ Cannot read ~/.aignals — click to open`, which reveals the path in Finder so the user can fix permissions.

### About window

Minimal: version number, GitHub link, one-line description. Single `Window("About Aignals")`. No custom design.

### First-launch hook install prompt

On first launch, if `~/.claude/settings.json` does not reference `aignals-hook`, show this prompt once:

```
┌───────────────────────────────────────────┐
│  Aignals is running — but the indicator   │
│  needs hooks to know when you're working. │
│                                           │
│  Install hooks into Claude Code now?      │
│                                           │
│           [ Later ]   [ Install ]         │
└───────────────────────────────────────────┘
```

Choosing **Later** sets `config.json.dismissed_install_prompt = true`. The prompt never auto-shows again; the user can still trigger installation manually via the menu item.

## 8. Error Handling

Aignals is an observer, not a critical path. Any failure must (a) never break Claude Code, then (b) surface what is meaningful to the user.

| Layer | Failure | Behavior |
|---|---|---|
| Hook | `~/.aignals/sessions/` missing | `aignals-hook` `mkdir -p`s; no error |
| Hook | `jq` missing | stderr install hint, exit 0 (Claude Code must not fail because of the indicator) |
| Hook | Write fails (disk full, permissions) | stderr one-liner, exit 0 |
| App | JSON parse fails | Skip the file, log via `os.Logger`, do not render |
| App | `schema_version != 1` | Skip the file, log |
| App | `~/.claude/settings.json` read/write fails during install | Native alert with the path; user can install manually |
| App | FSEvents fails to start | Icon `.error`; menu shows the warning row |
| App | PIDSweeper finds a dead pid | Delete file, refresh UI, no notification (routine cleanup) |

## 9. Testing

Coverage targets the protocol contract and every documented edge case. Three layers:

### 9.1 Unit tests

| Unit | Approach |
|---|---|
| `Session` (Codable) | Good JSON, missing required fields, unknown `schema_version`, extra unknown fields (ignored), `current_action` absent/present |
| `SessionStore` | `upsert` / `remove` directly; assert `sessions` ordering by `started_at`, `aggregateStatus` transitions across all three states |
| `PIDSweeper` | Inject `(pid_t) -> PIDState` closure to simulate alive / ESRCH / EPERM / missing-pid + mtime backstop |

### 9.2 Integration tests (Swift, real filesystem, no UI)

| Component | Approach |
|---|---|
| `FSEventsWatcher` | Temp directory + real FSEvents; create / modify / delete files; await callback with 2s timeout |
| `InstallHooksCommand` | Temp `settings.json` fixtures: empty file, existing unrelated hooks, already-installed Aignals entries (idempotent merge), malformed JSON (rejected with clear error) |

### 9.3 CLI tests (`bats` over the `aignals-hook` shell script)

Pipe canned stdin payloads, assert resulting file state on a temp `~/.aignals/sessions/`.

### 9.4 End-to-end tests (automatable)

E2E here means **the full producer → filesystem → consumer round trip on a real filesystem**, without a visible menu bar (which CI cannot render). A test harness:

1. Boots a `SessionStore` + `FSEventsWatcher` + `PIDSweeper` against a temp directory (the test passes a `Paths` override so `~/.aignals` is redirected).
2. Invokes `aignals-hook` as a subprocess with constructed stdin payloads exactly matching Claude Code's documented hook schema, and with `AIGNALS_HOME` set to the temp directory so the CLI also writes there.
3. Awaits the next state change on the store (XCTest expectation with a 2 s timeout) and asserts `aggregateStatus` + `sessions` contents.

**Cases the E2E suite MUST cover (every row a discrete test):**

| # | Scenario | Expected end state |
|---|---|---|
| 1 | SessionStart for one session | `aggregateStatus == .running`, exactly one session present |
| 2 | SessionStart, then Stop | `.idle`, sessions empty |
| 3 | SessionStart, then SessionEnd (no Stop) | `.idle`, sessions empty |
| 4 | Two parallel SessionStarts, then Stop the first | `.running`, one session remains (the second) |
| 5 | SessionStart, several PreToolUse events for different tools | each `current_action` reflects the latest tool/target mapping per §5 table |
| 6 | PreToolUse with unknown `tool_name` | `current_action.tool` = raw name, `target = ""` |
| 7 | SessionStart, then producer dies without writing Stop (orphan pid) | within one sweep tick after process death, file is removed and store reports `.idle` |
| 8 | Session with `pid` omitted, mtime forced to 25h ago | mtime backstop removes within one sweep tick |
| 9 | Malformed JSON file written into `sessions/` | file ignored, no crash, no entry; logged |
| 10 | `schema_version = 2` file written | ignored, no entry |
| 11 | Half-written file (write then truncate before rename) | watcher sees only the final atomic rename; no transient entry |
| 12 | `~/.aignals/sessions/` made unreadable (chmod 000) after start | `aggregateStatus == .error` within one sweep tick; recovers after chmod restored |
| 13 | InstallHooks merge against fixture `settings.json` with existing PreToolUse hook | Aignals entry appended; existing entry preserved; running twice is a no-op |
| 14 | Hook script with `jq` missing on `PATH` | hook exits 0, prints install hint, does not raise to Claude Code |

**All 14 must pass on CI.** The suite is the acceptance gate for the protocol.

### 9.5 Manual verification (uncovered by automation)

Only the visual surface — menu bar icon color/shape, dropdown rendering, About window, launch-at-login system integration. Documented as a checklist in `docs/superpowers/specs/manual-test-checklist.md` (created with the plan).

## 10. Distribution

| Item | Detail |
|---|---|
| Build | Xcode project; `xcodebuild` in CI produces `Aignals.app` |
| Package | `create-dmg` produces `Aignals.dmg` (with the standard drag-to-Applications layout) plus a `.zip` fallback |
| Signing | Self-signed (`codesign --sign -`). README documents the first-launch right-click → Open Gatekeeper workaround |
| Bundled CLI | `aignals-hook` script lives inside the app bundle at `Contents/Resources/aignals-hook`. First launch offers to symlink it into the user's PATH at `~/.local/bin/aignals-hook` (created if missing, no sudo required). If `~/.local/bin` is not on `PATH`, the prompt explains how to add it to `~/.zshrc`. Users who prefer a system-wide location can decline and `sudo ln -s` to `/usr/local/bin` manually. |
| Releases | Git tag `v0.x.y` → CI uploads dmg, zip, and a checksum file to GitHub Releases |
| Homebrew | A separate `homebrew-aignals` tap; cask points to the GitHub Release dmg. `brew install --cask aignals` after tapping |
| Auto-update | Not in v0.1. Users update via `brew upgrade` or by downloading again |
| Launch at login | `SMAppService.mainApp.register()`; menu toggle persists state to `config.json` |

## 11. Privacy

- No network connections, ever.
- Reads and writes only `~/.aignals/` and (when the user explicitly triggers Install Hooks) `~/.claude/settings.json`.
- No telemetry. The README states this explicitly.

## 12. Open Questions

None blocking v0.1. Items deferred to later releases live in §2 (Non-Goals).

# Aignals

A free, open-source macOS menu bar indicator that visualizes AI coding agent activity in real time — driven by the agent's own lifecycle hooks writing to a lightweight status file. Each Claude Code session gets its own colored light; the menu bar shows a compact count and the dropdown shows per-session detail.

## Install

```bash
brew tap Jesse1211/aignals
brew install --cask aignals
```

Or download `Aignals-0.2.1.dmg` from the [latest release](https://github.com/Jesse1211/Aignals/releases/latest). On first launch, right-click → Open to bypass Gatekeeper (the build is self-signed).

After installing the app, run **Install Claude Code Hooks…** from the menu (or accept the first-launch prompt) to wire it up.

## What the menu bar shows

The menu bar label is a compact count of how many sessions are in each state — e.g. `🔴2 🟡1 🟢3`. A state group with a count of `0` is hidden.

| Color | State | What it means | What you should do |
|-------|-------|---------------|--------------------|
| 🔴 Red | `working` | Claude is actively running (generating or running a tool) | Wait |
| 🟡 Yellow | `waiting_permission` | Claude is blocked on a permission prompt | Go click **Allow** |
| 🟢 Green | `waiting_input` | Claude finished its turn / a session just started | It's your turn — type the next message |
| ⚪️ Gray | `disconnected` | The session's process died (terminal closed / killed) without a clean `/exit` | Dismiss it with the ✕ when you're done |

## The dropdown (click the menu bar icon)

Clicking the icon opens a panel with **one row per session**, sorted **pinned-first, then newest on top**. Each row shows:

| Element | Meaning |
|---------|---------|
| **Colored dot** | That session's current state (red/yellow/green/gray, as above) |
| **Name** | The project name — **click to rename it**. Custom names persist in `~/.aignals/overrides.json` and survive hook updates |
| **Subtitle** | What the session is doing right now, e.g. `Editing MenuContent.swift`, `Running npm test`, `Waiting for input` — followed by the elapsed time |
| **Elapsed time** | Ticks **live every second** while the panel is open (e.g. `5s` → `6s` → `1m`) |
| **📌 Pin button** | Pin a session to keep it on top regardless of state changes; click again to unpin |
| **🔇 Mute button** | Silence sound alerts for just this session; click again to unmute |
| **✕ Remove** | Shown only on **gray (disconnected)** rows — removes the dead session and its saved preferences |

Rows can be **drag-reordered**; the order persists. Below the sessions, a **Settings** button expands the rest: Install Claude Code Hooks, Install aignals-hook CLI, Open `~/.aignals`, About, a global sound toggle, and Enable Launch at Login. **Quit** stays outside the fold.

## Sound alerts

When a session transitions into a state that needs you — 🟡 (waiting for permission) or 🟢 (waiting for input) — Aignals plays a short macOS system sound (a different sound for each, so you can tell which kind of attention is needed). Transitions into 🔴 (working) are silent. Sounds are throttled (at most once per session every few seconds, and never on app launch). Mute a single session with its 🔇 button, or turn all sound off with the global toggle under **Settings**.

## How it works

Claude Code fires lifecycle hooks at key moments. Each hook runs the bundled `aignals-hook` shell script, which atomically writes/updates/removes a per-session JSON file under `~/.aignals/sessions/<session_id>.json`. Aignals watches that directory with FSEvents and renders the lights. The file *is* the protocol — any tool that writes a conforming JSON file can drive the indicator, not just Claude Code.

The hook events map to states like this:

| Hook event | `aignals-hook` subcommand | Resulting state |
|------------|---------------------------|-----------------|
| SessionStart | `on-sessionstart` | 🟢 `waiting_input` (file created) |
| UserPromptSubmit | `on-prompt` | 🔴 `working` |
| PreToolUse | `on-pretool` | 🔴 `working` (+ current action) |
| Notification (permission_prompt) | `on-permission` | 🟡 `waiting_permission` |
| PostToolUse | `on-posttool` | 🔴 `working` (after Allow) |
| PermissionDenied | `on-permission-denied` | 🔴 `working` (after Deny) |
| Stop / Notification (idle_prompt) | `on-stop` / `on-idle` | 🟢 `waiting_input` |
| SessionEnd | `on-sessionend` | file deleted (light disappears) |

A session whose process dies *without* a clean `/exit` fires no hook; Aignals' background liveness check (`PIDSweeper`) detects the dead PID and turns that light **gray** instead of removing it.

## Testing it manually

You don't need a live Claude Code session to exercise the UI — you can drive the status files yourself by invoking `aignals-hook` the same way Claude Code does (a JSON payload on stdin). Each write needs a `session_id` and an `updated_at` timestamp that is **monotonically newer** than the previous write for that session (stale writes are dropped, by design).

Set a shortcut to the script:

```bash
HOOK="$(brew --prefix)/Caskroom/aignals/*/Aignals.app/Contents/Resources/aignals-hook"
# (or, from a source checkout:)
HOOK=/path/to/Aignals/CLI/aignals-hook/aignals-hook
```

Drive a single session through its full lifecycle (watch the menu bar dot change at each step):

```bash
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# 🟢 create a session (green, waiting for input)
echo '{"session_id":"demo","cwd":"/tmp/demo","updated_at":"'$(ts)'"}' | "$HOOK" on-sessionstart

# 🔴 it starts working
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-prompt

# 🔴 working on a specific file (shows "Editing main.swift" in the dropdown)
echo '{"session_id":"demo","tool_name":"Edit","tool_input":{"file_path":"main.swift"},"updated_at":"'$(ts)'"}' | "$HOOK" on-pretool

# 🟡 blocked on a permission prompt
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-permission

# 🔴 you clicked Allow, it continues
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-posttool

# 🟢 finished — your turn again
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-stop

# remove the session (light disappears)
echo '{"session_id":"demo"}' | "$HOOK" on-sessionend
```

Notes:

- **`on-sessionstart` creates** a session. Update subcommands (`on-prompt`, `on-pretool`, `on-permission`, `on-stop`, etc.) also **create** the session file if it doesn't exist yet — this is how Aignals adopts a session that was already running before the hooks were installed (it appears on its next activity). Only `on-sessionend` no-ops on a missing file.
- Use a **different `session_id`** to add another light. Open several to see the menu-bar count, e.g. `🔴1 🟡1 🟢2`.
- Inspect or clear the current sessions:

  ```bash
  for f in ~/.aignals/sessions/*.json; do jq -r '"\(.session_id): \(.state)"' "$f"; done   # list
  find ~/.aignals/sessions -name '*.json' -delete                                          # clear all
  ```

- The in-dropdown features (rename, drag-reorder, pin, live tick) are mouse interactions in the panel — open the dropdown and try them.

## Uninstall

**Easiest:** open the menu → **Settings → Uninstall Aignals…**. It removes Aignals' Claude Code hooks (leaving your other hooks intact), the `aignals-hook` CLI link, and all data in `~/.aignals`, then asks you to drag `Aignals.app` to the Trash to finish.

To do it by hand instead — Aignals stores everything in two places: hook entries in `~/.claude/settings.json`, and its own data under `~/.aignals/`. To remove it completely:

1. **Quit the app** — click the menu bar icon → **Quit Aignals**.

2. **Remove the hooks from `~/.claude/settings.json`.** This deletes only Aignals' hook entries and leaves your other hooks untouched (requires `jq`):

   ```bash
   cp ~/.claude/settings.json ~/.claude/settings.json.bak   # backup first
   jq '
     .hooks |= with_entries(
       .value |= map(select(
         (.hooks // []) | any(.command? // "" | test("aignals-hook")) | not
       ))
     )
     | .hooks |= with_entries(select(.value | length > 0))
   ' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
     && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
   ```

3. **Remove the CLI symlink** (if you ran *Install aignals-hook CLI…*):

   ```bash
   rm -f ~/.local/bin/aignals-hook
   ```

4. **Remove Aignals' data** (session files, config, custom names/order):

   ```bash
   rm -rf ~/.aignals
   ```

5. **Remove the app:**

   ```bash
   brew uninstall --cask aignals          # if installed via Homebrew
   # or, if you dragged it in manually:
   rm -rf /Applications/Aignals.app
   ```

The Homebrew cask's `zap` stanza also covers `~/.aignals` and the preferences plist, so `brew uninstall --zap --cask aignals` does steps 4–5 in one go (you still do steps 2–3 by hand).

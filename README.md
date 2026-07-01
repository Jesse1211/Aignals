English | [中文](README.zh.md)

# Aignals

**A traffic light for your vibe coding sessions.**

Aignals is a free, open-source macOS menu bar app that turns your AI coding agent's activity into a simple traffic light. When you're vibe coding with Claude Code, you don't want to babysit the terminal — Aignals watches for you. Each Claude Code session gets its own colored light, driven by the agent's own lifecycle hooks writing to a lightweight status file. The menu bar shows a compact count; the dropdown shows per-session detail.

- 🔴 **Red** — a session is working (wait)
- 🟡 **Yellow** — a session needs a permission click (go click Allow)
- 🟢 **Green** — your turn (the session finished / is waiting on you)
- ⚪️ **Gray** — the session disconnected (its process died)

Glance at the menu bar, know exactly which of your vibe coding sessions needs you.

## Install

```bash
brew tap Jesse1211/aignals
brew install --cask aignals
```

Or download the latest `.dmg` from the [latest release](https://github.com/Jesse1211/Aignals/releases/latest). On first launch, right-click → Open to bypass Gatekeeper (the build is self-signed).

After installing the app, run **Install Claude Code Hooks…** from the menu (or accept the first-launch prompt) to wire it up.

To update:

```bash
brew update
brew upgrade --cask aignals
```

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

Rows can be **drag-reordered**; the order persists. Below the sessions, a **Settings** button expands two groups — **General** (Install Claude Code Hooks, Install aignals-hook CLI, Open `~/.aignals/`, Launch at Login, Uninstall) and **Customization** (Theme, a **Sounds** card, and a **Feishu** card). Clicking the dropdown's **Aignals** header (marked with an ⓘ) opens the About window. **Quit** stays outside the fold.

## Themes

Aignals ships with **4 themes** — Glass Light, Glass Dark, Terminal, and Vibrant — switchable under **Settings → Customization → Theme**. A live preview pops as you pick, so you can match the panel to your desktop and mood.

## Sound alerts

When a session transitions into a state that needs you — 🟡 (waiting for permission) or 🟢 (waiting for input) — Aignals plays a short macOS system sound so you can tell which kind of attention is needed. Transitions into 🔴 (working) are silent.

Under **Settings → Play sounds**, each of the two states has its own sound picker: choose any stock macOS system sound (Ping, Glass, Funk, Tink, Pop, Hero, Submarine, Blow) or **None** to silence that state. Selecting a sound previews it immediately. The defaults are Ping for 🟡 and Glass for 🟢. Sounds are throttled (at most once per session every few seconds, and never on app launch). Mute a single session with its 🔇 button, or turn all sound off with the **Play sounds** toggle.

> Sounds fire on real session transitions, which need the Claude Code hooks installed. If they aren't, the sound pickers show a one-line reminder with an install shortcut (previewing a sound still works without the hooks).

## Feishu notifications

Aignals can also push a message to **Feishu (飞书/Lark)** on the same 🟡/🟢
transitions, independent of sound. To set it up:

1. In a Feishu group: **More (···) → Settings → Group Bots → Add Bot → Custom Bot**. Name it (e.g. "Aignals") and add it.
2. Copy the generated **webhook URL** (`https://open.feishu.cn/open-apis/bot/v2/hook/…`; Lark international uses `open.larksuite.com`).
3. (Optional) Under the bot's **Security Settings**, pick one:
   - **Signature** — copy the **secret** into Aignals' *Secret* field (most secure).
   - **Custom keywords** — set a keyword and enter the SAME word in Aignals' *Keyword* field. Tip: use `Aignals` (every message already starts with it).
4. In Aignals: **Settings → Feishu notifications** → paste the webhook URL (and secret/keyword if used) → **Send test message** to confirm.

Sends are best-effort; if one fails, Settings shows a one-line reason under the toggle.

## Daily Quote

The dropdown includes a **Daily Quote** card to give your vibe coding session a little lift. It pulls a quote from [API Ninjas](https://api-ninjas.com/), lets you pick a **category**, **refresh** for a new one, and **save** the ones you like (saved quotes persist in `~/.aignals/quotes.json`). Set your own API Ninjas key in Settings to use it.

## Work Stopwatch

A built-in **Work Stopwatch** lets you **clock in / clock out** to track focused work time. Each session is added to a **daily work log**, and a dedicated **Stat window** summarizes your logged hours. Data lives in `~/.aignals/worklog.json`.

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

**Easiest:** open the menu → **Settings → Uninstall Aignals…**. It removes Aignals' Claude Code hooks (leaving your other hooks intact), the `aignals-hook` CLI link, and all data in `~/.aignals`, then asks you to drag `Aignals.app` to the Trash to finish. The dialog has a **"Keep my saved data (work log & quotes)"** checkbox — when checked, it preserves `~/.aignals/quotes.json` (and `worklog.json`) and removes everything else.

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

4. **Remove Aignals' data** (session files, `config.json`, `overrides.json` custom names/order, `quotes.json` saved quotes):

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

# Aignals — Manual Test Checklist (v0.1)

Run before tagging a release. Each item must be verified on a fresh macOS 13+ machine.

## Menu bar icon
- [ ] Green dot visible at launch with empty `~/.aignals/sessions/`.
- [ ] Dot turns red within 1 s of dropping a valid session file into the dir.
- [ ] Dot turns green within 1 s after that file is deleted.
- [ ] Dot turns gray with a ring when `~/.aignals/sessions/` is `chmod 000`'d.
- [ ] Dot is visible in both light and dark menu bar themes.

## Dropdown
- [ ] Empty state shows "No active sessions".
- [ ] Active state shows one row per session with `project_name` and a subtitle.
- [ ] Subtitle reflects verb mapping (`Editing`, `Running`, `Reading`, `Searching`).
- [ ] Elapsed indicator updates roughly every 30 s when menu is open.
- [ ] "Open ~/.aignals" reveals the directory in Finder.
- [ ] "Quit Aignals" terminates the process.

## First-launch flow (Phase 9)
- [ ] On first launch with no `aignals-hook` in `~/.claude/settings.json`, the install prompt appears.
- [ ] Choosing "Later" never shows the prompt again.
- [ ] Choosing "Install" merges entries into `settings.json` and refreshes detection.

## Launch at Login (Phase 10)
- [ ] Toggle in dropdown enables/disables `SMAppService` registration.
- [ ] After enabling and rebooting, Aignals starts automatically.

## Status sounds (v0.3.0)
- [ ] Settings → "Play sounds" on shows the 🟡 Permission / 🟢 Input pickers; off hides them.
- [ ] Selecting a sound in each picker previews it audibly; "None" is silent.
- [ ] The selected sounds persist across relaunch (written to `~/.aignals/config.json`).
- [ ] A real transition into 🟡 plays the selected Permission sound, into 🟢 the selected Input sound; 🔴 working and ⚫ disconnected stay silent.

## Feishu notifications
- [ ] Settings shows "Feishu notifications" toggle; fields appear only when on.
- [ ] Webhook URL / Secret / Keyword persist across app relaunch (config.json).
- [ ] "Send test message" with a valid webhook delivers a message to the group.
- [ ] Invalid webhook → red error line appears under the toggle; valid send clears it.
- [ ] Real 🟢 transition delivers a message naming the session; rename is honored.
- [ ] Sound OFF + Feishu ON: a transition still sends Feishu (throttle moved out of sound branch).
- [ ] Per-session 🔇 mute suppresses BOTH sound and Feishu for that session.
- [ ] Keyword-mode bot: with Keyword set, messages are accepted (not dropped by Feishu).

## Settings redesign
- [ ] Header shows an ⓘ; clicking the "Aignals" header opens the About window.
- [ ] No "About Aignals…" row remains in Settings.
- [ ] "General" and "Customization" section labels render; every row has a leading icon.
- [ ] Sounds and Feishu render as cards with a switch; body is hidden when the switch is off.
- [ ] Feishu: editing a field does NOT persist until Save; Save is disabled until a field changes.
- [ ] After Save + app relaunch, the saved Feishu values are shown; Save is disabled again.
- [ ] "Send test" uses the current (unsaved) field values.
- [ ] Copy reads `Open ~/.aignals/`, `Launch at Login`, `Uninstall Aignals` (no ellipsis).
- [ ] All four themes: card fill, switch, and section labels read acceptably.

## Daily Quote
- [ ] Menu bar shows the traffic-light icon plus a truncated quote; hovering shows the full text tooltip.
- [ ] Opening the dropdown shows the full quote + author at top with refresh / save / projector buttons.
- [ ] Refresh (⟳) fetches a new quote (spinner shows briefly).
- [ ] Save (♥) stores the current quote; the heart fills; saving the same quote again does nothing (dedup).
- [ ] Projector (📖) opens the Saved Quotes window; saved quotes appear newest-first with saved time; swipe-delete removes one.
- [ ] With no network, the quote shows "—" and Save is disabled.
- [ ] Settings → Daily Quote: toggling off hides the menubar quote text (icon only); changing truncation length shortens/lengthens it.
- [ ] `~/.aignals/quotes.json` exists after saving and contains `{"version":1,"quotes":[…]}`.
- [ ] Uninstall with "Keep my saved data" checked preserves `~/.aignals/quotes.json`; unchecked removes all of `~/.aignals`.

## Work Stopwatch
- [ ] Start shows a running hh:mm:ss that ticks; Stop freezes it; Resume continues; End resets to 00:00:00 and appends the session to the work log.
- [ ] Buttons match state: idle shows only Start; running shows Stop + End; stopped shows Resume + End; Stat (chart) button always present.
- [ ] Quit the app while running, reopen later the same day → elapsed time continued by wall clock (closed time counted).
- [ ] Cross local midnight while running (or reopen the next day) → yesterday's segment sealed at 23:59:59, today starts at 00:00:00 stopped.
- [ ] Multi-day gap (start, leave app closed across a full day, reopen) → only the start day is logged; fully-spanned days have no record.
- [ ] Stat (Work Stats) window lists days newest-first with totals; expanding a day shows its segments in local time; shows "No work logged yet." before any log.
- [ ] With Feishu configured and a quote loaded, the FIRST Start of the day posts today's quote to Feishu; Resume does NOT post.
- [ ] `~/.aignals/worklog.json` and `~/.aignals/stopwatch-state.json` exist with the documented shapes; replacing Aignals.app (upgrade) preserves them.

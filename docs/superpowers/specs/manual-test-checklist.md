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

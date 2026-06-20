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

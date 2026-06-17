# Aignals — Session Status & Resume Guide

**Last updated:** 2026-06-17
**Branch:** `main`

---

## What's done

- [`docs/superpowers/specs/2026-06-16-aignals-menubar-design.md`](specs/2026-06-16-aignals-menubar-design.md) — full design spec (12 sections, two self-review passes).
- [`docs/superpowers/plans/2026-06-17-aignals-v0.1-master.md`](plans/2026-06-17-aignals-v0.1-master.md) — master plan with parallelism map.
- [`docs/superpowers/plans/2026-06-17-aignals-phase-00..11-*.md`](plans/) — 12 phase plans, two self-review passes.
- **Phase 0 (scaffolding) committed.** Four commits:
  - `phase-00: scaffold directory layout`
  - `phase-00: add SPM manifest with library + test targets [unverified]`
  - `phase-00: scaffold Aignals app via XcodeGen`
  - `phase-00: add CI workflow (swift test + bats + xcodebuild)`

The `[unverified]` suffix marks commits whose tests couldn't run locally because Xcode.app isn't installed (only Apple Command Line Tools). All Phase 0 deliverables are in the tree; only the test-runtime verification was deferred.

## Why Phase 1+ stopped

`swift test` and `xcodebuild` both need Xcode.app. Apple Command Line Tools alone ship neither XCTest's runtime nor `xcodebuild`. This is a macOS toolchain reality, not a project bug.

| Action | Needs Xcode.app? |
|---|---|
| Write Swift source | no |
| `swift build` | no |
| `swift test` (XCTest) | **yes** |
| `xcodebuild` (build `.app`) | yes |
| `xcodegen generate` (write `.xcodeproj` YAML→XML) | no |
| `bats` / shell tests for `aignals-hook` | no |

Only Phase 6 (the bash CLI + bats) can be implemented + verified without Xcode. Everything else is gated on installing Xcode.

## How to resume in the next session

1. **Install Xcode** (App Store or `xcodes install 15.4`), then wire it up:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -version          # expect: Xcode 15.x or 16.x
   sudo xcode-select -p         # expect: /Applications/Xcode.app/Contents/Developer
   ```

2. **Re-verify the Phase 0 `[unverified]` commit:**
   ```bash
   cd /Users/jesseliu/Desktop/Chore/Aignals
   swift build                                  # should pass
   swift test                                   # the placeholder tests should pass
   (cd App/Aignals && xcodegen generate)
   xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build
   ```
   If everything is green, the `[unverified]` work is now verified. Either amend the commit message or add a follow-up note in this file.

3. **Dispatch the remaining phases** per the master plan's parallelism map:
   - Wave 1 (parallel): Phase 1 (`Paths`), Phase 2 (`Session` model), Phase 6 (`aignals-hook` CLI + bats).
   - Wave 2: Phase 3 (`SessionStore`) — depends on Phase 2.
   - Wave 3 (parallel): Phase 4 (`FSEventsWatcher`), Phase 5 (`PIDSweeper`) — depend on Phase 3.
   - Wave 4: Phase 7 (E2E integration — the 14-case suite from spec §9.4).
   - Wave 5: Phase 8 (UI), then Phase 9 (Install Hooks) + Phase 10 (Config) in parallel.
   - Wave 6: Phase 11 (packaging + release).

   The recommended dispatch tool: `Agent` with `subagent_type: general-purpose`. Each subagent prompt should include the spec path, the master plan path, the specific phase plan path, and the constraints: no `git add -A`, no `--no-verify`, conventional commits with `phase-NN:` prefix, run `git status --short` after each commit, STOP and report on any test failure.

4. **Acceptance gate:** all 14 E2E cases (spec §9.4) must pass before tagging `v0.1.0`.

## Locked architectural decisions

(Summarised here; the canonical record is the spec.)

1. Native macOS app, not an xbar plugin.
2. State transport = JSON file per session in `~/.aignals/sessions/`, watched via FSEvents (atomic `tmp + mv` writes).
3. One file per session; menu shows per-session detail.
4. Subtitle shows current action + elapsed (verb mapping per `tool_name`).
5. Icon = solid colored circle (red / green / gray), no animation.
6. PID liveness check + 24h mtime backstop for orphan cleanup. Open protocol so non-Claude tools can drive the indicator.
7. Distribution = self-signed `.app` + DMG + Homebrew Cask. No Apple notarization in v0.1. `SMAppService` for Launch-at-Login.
8. SwiftUI `MenuBarExtra` (macOS 13+). Custom `NSImage` for the colored dot (`isTemplate = false`).
9. Out of scope for v0.1: notifications, history, themes, auto-update, i18n.

## Build dependencies (already installed locally)

- `swift` 5.10 (via Command Line Tools)
- `xcodegen` 2.45.4 (Homebrew)
- `jq` 1.8.1 (Homebrew)
- `bats-core` 1.13.0 (Homebrew)

Still needed for verification: `Xcode.app` ≥ 15.

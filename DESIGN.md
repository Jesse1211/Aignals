# DESIGN.md — Phase 8: Menu Bar UI (feature-factory ledger)

Derived from `docs/superpowers/plans/2026-06-17-aignals-phase-08-ui.md` and spec §7.
This is the locked decision ledger the hands-off build consumes. No human in the build loop.

## Bounded context / domain

- **BC:** `Presentation` — the menu bar UI. New, thin. Owns nothing in the domain model; it only *renders* the `Sessions` aggregate (owned by `AignalsCore`) and *references* it read-only.
- **Boundary:** UI may read `SessionStore.sessions` / `aggregateStatus` and call its public mutators via the watcher/sweeper. It must NOT reimplement liveness, decoding, or aggregation — those live in `AignalsCore` (already built & green).
- **Aggregate root:** unchanged — `SessionStore` (`@MainActor @Observable`). UI holds it, does not replace it.
- **Value objects (pure, testable in SPM):** `StatusIcon` (status → NSImage), `ElapsedFormatter` (seconds → "14s/2m/3h/2d"), `VerbMapper` (tool → display verb). These move into `AignalsCore` so SPM unit tests cover them without Xcode.
- **Invariants:**
  - I1: status image is always 18×18 and `isTemplate == false` (keeps its own color across light/dark menu bar).
  - I2: three and only three aggregate states render distinctly: running=red, idle=green, error=gray+ring.
  - I3: UI never mutates domain state except through `SessionStore` public API.

## ADR ledger

- **ADR-0801:** Pure rendering/formatting logic (`StatusIcon`, `ElapsedFormatter`, `VerbMapper`) lives in `Sources/AignalsCore`, not the app target. *Rationale:* this Mac has only CLT; only SPM targets get `swift test`. Putting logic in Core makes the gates locally + CI verifiable. App target consumes via the `AignalsCore` product.
- **ADR-0802:** UI source files live under `App/Aignals/Sources/` (already the `project.yml` `sources` path), NOT a new `App/Aignals/UI/` dir. *Rationale:* avoids a `project.yml` change + xcodegen regen for every file; the dir is already wired. (Supersedes the plan's `UI/` paths.)
- **ADR-0803:** Status states map running→systemRed, idle→systemGreen, error→systemGray with a hollow ring. `isTemplate=false`. (Implements I1, I2.)
- **ADR-0804:** Elapsed is coarse single-unit (`s`/`m`/`h`/`d`), refreshed via a 30s timer while the menu is open. No live per-second tick — menu bar dropdowns don't need it and it avoids a wakeup tax.
- **ADR-0805:** "Install Claude Code Hooks…" button is a Phase-9 no-op stub now (present, does nothing). Per OQ-81, do not implement install logic in Phase 8.
- **ADR-0806:** Trunk for this build is **`ci/github-actions`** (where CI runs). All task PRs target and ff-merge into it. Merge to `main` is a separate later step, out of scope.
- **ADR-0807:** App/UI tasks cannot be locally `xcodebuild`-verified (no Xcode.app). Their acceptance gate is: `swift build` (Core compiles) + `xcodegen generate` succeeds + **CI green on the pushed branch** (`gh run watch`), where CI runs `xcodebuild` on `macos-15`. (Implements the "independent Tester still runs the real gate" rule via CI.)

## Open questions (do not resolve in build)

- **OQ-81:** Hook-install flow is Phase 9. Phase 8 leaves the button as a labeled no-op. Build agents: do not touch hook installation.
- **OQ-82:** About window GitHub URL — use the real repo `https://github.com/Jesse1211/Aignals` (not the `YOUR-USERNAME` placeholder in the plan).

## Global commands

- `TEST_CMD` (Core/logic tasks): `swift build && swift test --filter <SuiteName>` — if XCTest runtime is unavailable locally, fall back to `swift build` locally + rely on CI for `swift test`.
- `LINT_CMD`: none configured; use `swift build` as the typecheck gate.
- `XCODEGEN`: `(cd App/Aignals && xcodegen generate)`
- CI gate (UI tasks): push branch, then
  `RID=$(gh run list --branch <branch> --limit 1 --json databaseId -q '.[0].databaseId'); gh run watch "$RID" --exit-status` and on failure `gh run view "$RID" --log-failed`.

## Task DAG

| id | title | depends_on | gate |
|----|-------|-----------|------|
| T1 | StatusIcon in AignalsCore + tests | — | `swift build` green; `StatusIconTests` pass (local if XCTest available, else CI). Asserts 18×18, isTemplate=false for idle/running/error. |
| T2 | ElapsedFormatter in AignalsCore + tests | — | `swift build` green; `ElapsedFormatterTests` pass. 14→"14s",125→"2m",10805→"3h",172810→"2d". |
| T3 | VerbMapper in AignalsCore + tests | — | `swift build` green; `VerbMapperTests` pass. Edit/Write→Editing, Bash→Running, Read→Reading, Glob/Grep→Searching, unknown title-cased. |
| T4 | AppViewModel (wires Paths/Store/Watcher/Sweeper, seeds disk) | T1,T2,T3 | `swift build` green; `xcodegen generate` succeeds. File at `App/Aignals/Sources/AppViewModel.swift`. |
| T5 | MenuContent view (session rows, empty/error states, 30s tick) | T4 | `xcodegen generate` succeeds; `App/Aignals/Sources/MenuContent.swift` references only confirmed Session/Store APIs (sessionID, projectName, startedAt, currentAction.tool/target). |
| T6 | Wire AignalsApp → AppViewModel + StatusIcon label | T5 | `xcodegen generate` succeeds + **CI green** on pushed branch (xcodebuild BUILD SUCCEEDED). |
| T7 | About window + menu item (real repo URL per OQ-82) | T6 | `xcodegen generate` succeeds + **CI green** on pushed branch. |
| T8 | Manual-test checklist doc | — | file `docs/superpowers/specs/manual-test-checklist.md` exists with the menu-bar + dropdown sections. |

T1–T3 and T8 are independent (parallel). T4 waits on T1–T3. T5→T6→T7 serialize. Each UI task that pushes triggers CI.

## Acceptance (Phase 8 done)

- `StatusIconTests`, `ElapsedFormatterTests`, `VerbMapperTests` green.
- `xcodegen generate` clean; CI green on `ci/github-actions` head (xcodebuild builds the `.app`).
- Manual smoke (drop session json → red dot; delete → green) documented in checklist for post-Xcode verification.

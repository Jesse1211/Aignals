# In-App Update via Sparkle — Design

**Date:** 2026-07-05
**Status:** Approved design, pending spec review

## Context

Aignals ships through two channels: a Homebrew cask and manual `.dmg` downloads
from GitHub Releases. Today a user has no in-app way to know a newer version
exists — they must remember to run `brew upgrade` or check the releases page.
This is easy to miss (the local Release build on the maintainer's own machine
was two versions behind at design time).

Goal: surface the latest version inside the app and offer a one-click path to
it, so users don't have to go check Homebrew or GitHub themselves. Direct-download
users get a true one-click auto-update; Homebrew users are guided to `brew upgrade`
so Homebrew's records don't drift out of sync.

We use **Sparkle**, the de-facto macOS auto-update framework. The update feed
(`appcast.xml`) and the update packages both live on GitHub — appcast on the
existing GitHub Pages site (`https://jesse1211.github.io/Aignals/`), packages as
the `.dmg` release assets already produced by `release.yml`. **No server required.**

**Load-bearing assumption: the app is non-sandboxed.** Sparkle's replace-and-
relaunch installer needs no XPC installer service or special entitlements in this
case. If the app were ever sandboxed, Sparkle would additionally require
`SUEnableInstallerLauncherService` plus mach-lookup temporary-exception
entitlements — out of scope as long as Aignals stays non-sandboxed.

## Architecture

Three units with clear boundaries, separating testable pure logic from
untestable Sparkle IO:

### `UpdateChecker` (pure logic, unit-tested)
No Sparkle SDK. Given version strings and install source, it decides what the UI
should show. Outputs a single state enum:

```
enum UpdateState {
    case checking
    case upToDate
    case available(version: String, source: InstallSource)
    case failed
}

enum InstallSource { case direct, homebrew }
```

Responsibilities:
- Semantic version comparison (current `CFBundleShortVersionString` vs. latest
  from appcast).
- Install-source detection (see Data Flow).
- Mapping (current, latest, source) → `UpdateState`.

### `UpdaterService` (Sparkle wrapper, `@MainActor`, implements `SPUUpdaterDelegate`)
Wraps Sparkle's `SPUUpdater` and acts as its delegate. **Critical distinction
between the two Sparkle check APIs:**

- **Silent probe (drives our badge/state):** `SPUUpdater.checkForUpdateInformation()`.
  This is Sparkle's *probing* check — it does **not** present any Sparkle UI and
  does **not** offer to install. It fires the delegate callbacks
  `updater(_:didFindValidUpdate:)` and `updaterDidNotFindUpdate(_:)`, which we
  implement to feed the current version + install source into `UpdateChecker`
  and publish the resulting `UpdateState`. This is what the Settings badge and
  the About-page state read from. **`checkForUpdates()` / `checkForUpdatesInBackground()`
  are NOT used for this — they route through the user driver and present
  Sparkle's own UI.**
- **Actual install (`startUpdate()`, direct users only):** calls
  `checkForUpdates()` — *here* we deliberately want Sparkle's standard
  download → verify → replace → relaunch UI (progress + confirm). We reuse it
  rather than reimplementing a progress bar.

**Disable Sparkle's built-in scheduler.** Set `SUEnableAutomaticChecks = false`
(see Info.plist) and instead drive our own periodic `checkForUpdateInformation()`
probes. Otherwise Sparkle's automatic scheduler would pop its *own* reminder UI,
competing with our badge — two surfaces for the same event. We own the cadence.

Exposes: `checkForUpdateInformation()` (manual + our periodic probe),
`startUpdate()` (direct install), published `latestVersion` / `UpdateState`.

### UI layer (state-driven)
- **Settings-button badge** in the dropdown (`MenuContent.swift:293`, the
  `⚙ Settings…` button): a small red dot when `.available`, with a
  "Update available" help tooltip. No badge otherwise. This is the guidance
  signal pointing users toward the update. (Badge only on the Settings button —
  the brand-header ⓘ stays clean to avoid duplication.)
- **About-page update section** (`SettingsView.swift:214` `aboutPage`, below the
  existing `Version X.Y.Z` line) — see UI Presentation.

## Data Flow

1. **On launch + periodically**: `UpdaterService` calls
   `checkForUpdateInformation()` (our own cadence, since Sparkle's scheduler is
   disabled). Sparkle fetches the appcast from `SUFeedURL` and fires the delegate
   callback. `UpdaterService` passes latest + current version + install source to
   `UpdateChecker`, which computes `UpdateState` and publishes it to the UI. No
   Sparkle UI appears during this probe.
2. **Manual check**: About-page "Check for Updates" → same
   `checkForUpdateInformation()` probe, but surfaces `.failed` explicitly
   (network errors) rather than staying silent.
3. **Install (direct users)**: "Update Now" → `startUpdate()` → `checkForUpdates()`,
   which presents Sparkle's standard update dialog and runs the
   download/verify/replace/relaunch.

### Install-source detection (`InstallSource`, pure function)
Judged in reliability order:
1. App bundle path is inside the Homebrew Caskroom, or is a symlink pointing into
   the Caskroom → `.homebrew`.
2. Fallback: app in `/Applications` with a brew Caskroom record present → `.homebrew`.
3. Otherwise (including undetectable) → **`.direct`** (conservative default).

Rationale for the default: manual `.dmg` users are the ones who most need
one-click updates. If a Homebrew user is misjudged as `.direct`, Sparkle still
updates correctly — the only downside is Homebrew's version record drifting,
which is a tolerable degradation, not a breakage.

## UI Presentation

The About-page update section renders by `UpdateState`:

```
.checking            →  spinner "Checking…"
.upToDate            →  "You're on the latest version." + [Check for Updates]
.available(.direct)  →  "vX.Y.Z is available." + [Update Now]
                        (→ Sparkle download/verify/replace/relaunch)
.available(.homebrew)→  "vX.Y.Z is available. Update via Homebrew:"
                        + read-only `brew upgrade --cask aignals` + [Copy]
.failed              →  "Couldn't check for updates." + [Retry]
```

Reuse: the existing `appVersion` (SettingsView.swift:209) keeps showing the
current version. The `.direct` update dialog reuses Sparkle's standard UI (no
custom progress bar). Release notes from the GitHub release are surfaced in
Sparkle's update dialog via an HTML description in the appcast entry.

## CI / appcast / keys

Zero-server publishing pipeline on GitHub.

### One-time manual setup (maintainer)
Done at design time:
- Generated an EdDSA key pair with Sparkle's `generate_keys` (from the Sparkle
  release tarball).
- **Public key** added to `App/Aignals/Resources/Info.plist` as `SUPublicEDKey`,
  alongside `SUFeedURL` (`https://jesse1211.github.io/Aignals/appcast.xml`).
- **Private key** exported and stored as GitHub Actions secret
  `SPARKLE_PRIVATE_KEY`; local export file deleted.

**Info.plist Sparkle behavior keys (to finalize during implementation):**
- `SUEnableAutomaticChecks = false` — we disable Sparkle's built-in scheduler
  and drive our own silent `checkForUpdateInformation()` probes, so only our
  badge surfaces "update available" (no competing Sparkle reminder popup).
  *(Currently set to `true` in the file; implementation flips it to `false`.)*
- `SUAutomaticallyUpdate = false` — never auto-install silently; direct users
  click "Update Now", Homebrew users are guided to `brew`.
- `SUScheduledCheckInterval` — not required (scheduler disabled); our probe
  cadence lives in `UpdaterService`.

### App dependency
Sparkle is distributed as an **external** SwiftPM package
(`https://github.com/sparkle-project/Sparkle`, a binary framework). In
`App/Aignals/project.yml`, declare it under xcodegen's top-level `packages:` as
a remote package (url + version), then add it to the app target's `dependencies`
as `- package: Sparkle`. This differs from the existing local `AignalsCore`
package reference — external remote package, not a local path. (`AignalsCore` in
`Package.swift` does not need Sparkle; only the app target links it.)

### `release.yml` additions (after existing package steps)
Existing: build `.app` → package `.dmg`/`.zip` → upload to GitHub Release.
Add:
1. **Re-sign embedded Sparkle helpers.** Sparkle 2.x ships XPC services + helper
   tools inside its framework, signed with Hardened Runtime. Because CI packages
   the app manually (not a plain Xcode Archive), verify/re-codesign the embedded
   framework (`codesign --deep`/per-binary with `-o runtime`) so those nested
   signatures stay valid — otherwise auto-install fails at runtime.
2. **Sign the update archive** with `SPARKLE_PRIVATE_KEY` via Sparkle's
   `sign_update`, producing the EdDSA signature. `sign_update` works on either
   `.dmg` or `.zip`; pick one (the `.dmg`, matching the cask) and sign *that*.
3. Generate/update the **appcast.xml** entry: version, EdDSA signature, HTML
   release notes, and an `enclosure url` that points to the **exact byte-for-byte
   file that was signed** (the uploaded GitHub Releases asset). **Do not re-zip
   or re-DMG after signing** — re-packaging invalidates the signature (the single
   most common Sparkle validation failure).
4. Publish appcast.xml to GitHub Pages by writing `docs/appcast.xml` and pushing
   (the site is served from `docs/`, confirmed via `docs/index.html`). Note:
   GitHub Pages' CDN may serve a stale appcast for a few minutes after push.

### Code-signing consistency (self-signed app)
The app is self-signed / non-notarized ("right-click → Open" per README).
Sparkle's EdDSA check is independent of Apple code signing, so downloads verify.
But Sparkle also enforces **code-signature consistency**: the new bundle's
signing identity must match the old one's, and a signing/EdDSA key cannot be
*removed* across versions. **Every release must be signed the same way** (keep
the same ad-hoc/self-signed identity consistently) or the install is rejected.
This is load-bearing and must not regress.

### Homebrew cask
The cask (`homebrew/aignals.rb`, and the copy generated by `release.yml`) must
declare **`auto_updates true`**, the Homebrew convention for an app that updates
itself via Sparkle. It signals that the app can self-update, so Homebrew doesn't
treat its own version record as authoritative. (Our source-detection still routes
brew users to `brew upgrade` in-app; `auto_updates true` is the cask-metadata
counterpart.)

## Testing & Verification

### Unit tests (`UpdateChecker`, pure logic)
- Version comparison: lower → available, equal/higher → up-to-date.
- `InstallSource`: Caskroom path → `.homebrew`; `/Applications` direct or
  undetectable → `.direct`.
- State mapping: input combinations → correct `UpdateState`
  (`.upToDate` / `.available(.direct)` / `.available(.homebrew)` / `.failed`).

### Manual verification (Sparkle IO, not automatable)
Walk through once with a test release (temporarily lower the app version):
1. **Signing**: CI signs the test `.dmg` with `SPARKLE_PRIVATE_KEY` and generates
   appcast.xml.
2. **Reachability**: `curl https://jesse1211.github.io/Aignals/appcast.xml`
   returns the correct version + signature. (Allow a few minutes for GitHub
   Pages' CDN to refresh after the push — a transiently stale feed is not a
   failure.)
3. **Verify + update on a CLEAN machine**: install a lower-version app →
   trigger check → see "available" → click Update Now → Sparkle verifies with
   `SUPublicEDKey` → downloads/replaces/relaunches. **Do this on a clean machine,
   not the dev box** — a non-notarized self-signed update can hit Gatekeeper/
   quarantine on first relaunch on some macOS versions; that's the exact path
   that must be confirmed to actually relaunch.
4. **Source branch**: a brew-installed app shows the `brew upgrade` guidance
   instead of the auto-update button.

## Out of Scope (YAGNI)
- Delta/partial updates.
- Beta/pre-release channels.
- In-app changelog browsing beyond Sparkle's release-notes dialog.
- Rollback / downgrade.

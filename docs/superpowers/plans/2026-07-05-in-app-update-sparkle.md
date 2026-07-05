# In-App Update via Sparkle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the latest Aignals version inside the app and offer a one-click update — Sparkle auto-update for direct-download users, `brew upgrade` guidance for Homebrew users.

**Architecture:** Pure version/source logic lives in `AignalsCore` (`UpdateChecker`, unit-tested with no Sparkle dependency). The Sparkle SDK is confined to the app target via an `UpdaterService` that implements `SPUUpdaterDelegate` and drives our own silent probes (Sparkle's built-in scheduler is disabled). UI reads published `UpdateState` to render a Settings-button badge and an About-page update section. CI signs each release with an EdDSA key and publishes an appcast to GitHub Pages.

**Tech Stack:** Swift / SwiftUI, Sparkle 2.x (external SwiftPM package, app target only), xcodegen, GitHub Actions, GitHub Pages, Homebrew cask.

## Global Constraints

- **AignalsCore must NOT depend on Sparkle.** Only the app target links Sparkle. `UpdateChecker` is pure logic in `Sources/AignalsCore/`.
- **Silent probe API:** use `SPUUpdater.checkForUpdateInformation()` + `SPUUpdaterDelegate` for badge/state. Use `checkForUpdates()` ONLY for the user-clicked "Update Now" install.
- **Sparkle's own scheduler is disabled:** `SUEnableAutomaticChecks = false`, `SUAutomaticallyUpdate = false` (already set in `App/Aignals/Resources/Info.plist`). We drive periodic probes ourselves.
- **Feed URL:** `https://jesse1211.github.io/Aignals/appcast.xml` (`SUFeedURL`, already set).
- **Public key:** `SUPublicEDKey` already set in Info.plist. Private key is GitHub Actions secret `SPARKLE_PRIVATE_KEY`.
- **Code-signing consistency:** every release is ad-hoc signed (`codesign --sign -`), same identity across versions — do not regress, or Sparkle rejects the install.
- **appcast enclosure must point to the exact signed file** (byte-for-byte). Never re-package after signing.
- **Source-detection default is `.direct`** when undetectable (manual users need one-click most; a misjudged brew user still updates fine).
- App is **non-sandboxed** (load-bearing — no XPC installer entitlements needed).

---

### Task 1: `UpdateChecker` pure logic in AignalsCore

**Files:**
- Create: `Sources/AignalsCore/UpdateChecker.swift`
- Test: `Tests/AignalsCoreTests/UpdateCheckerTests.swift`

**Interfaces:**
- Produces: `enum InstallSource { case direct, homebrew }`; `enum UpdateState: Equatable { case idle, checking, upToDate, available(version: String, source: InstallSource), failed }`; `struct UpdateChecker` with `static func compare(current: String, latest: String) -> Bool` (true = latest is newer), `static func detectSource(bundlePath: String) -> InstallSource`, `static func state(current: String, latest: String?, source: InstallSource) -> UpdateState`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AignalsCore

final class UpdateCheckerTests: XCTestCase {
    // --- version comparison ---
    func test_compare_detects_newer() {
        XCTAssertTrue(UpdateChecker.compare(current: "0.5.1", latest: "0.5.2"))
        XCTAssertTrue(UpdateChecker.compare(current: "0.5.1", latest: "0.6.0"))
        XCTAssertTrue(UpdateChecker.compare(current: "0.9.9", latest: "1.0.0"))
    }
    func test_compare_equal_or_older_is_not_newer() {
        XCTAssertFalse(UpdateChecker.compare(current: "0.5.1", latest: "0.5.1"))
        XCTAssertFalse(UpdateChecker.compare(current: "0.5.2", latest: "0.5.1"))
        XCTAssertFalse(UpdateChecker.compare(current: "1.0.0", latest: "0.9.9"))
    }
    func test_compare_handles_uneven_component_counts() {
        XCTAssertTrue(UpdateChecker.compare(current: "0.5", latest: "0.5.1"))
        XCTAssertFalse(UpdateChecker.compare(current: "0.5.0", latest: "0.5"))
    }

    // --- install source ---
    func test_detectSource_caskroom_path_is_homebrew() {
        let p = "/opt/homebrew/Caskroom/aignals/0.5.1/Aignals.app"
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: p), .homebrew)
    }
    func test_detectSource_intel_caskroom_is_homebrew() {
        let p = "/usr/local/Caskroom/aignals/0.5.1/Aignals.app"
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: p), .homebrew)
    }
    func test_detectSource_applications_is_direct() {
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: "/Applications/Aignals.app"), .direct)
    }
    func test_detectSource_unknown_defaults_direct() {
        XCTAssertEqual(UpdateChecker.detectSource(bundlePath: "/Users/x/Desktop/Aignals.app"), .direct)
    }

    // --- state mapping ---
    func test_state_nil_latest_is_failed() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: nil, source: .direct), .failed)
    }
    func test_state_same_version_is_upToDate() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: "0.5.1", source: .direct), .upToDate)
    }
    func test_state_newer_direct_is_available_direct() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: "0.6.0", source: .direct),
                       .available(version: "0.6.0", source: .direct))
    }
    func test_state_newer_homebrew_is_available_homebrew() {
        XCTAssertEqual(UpdateChecker.state(current: "0.5.1", latest: "0.6.0", source: .homebrew),
                       .available(version: "0.6.0", source: .homebrew))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateCheckerTests`
Expected: FAIL — `cannot find 'UpdateChecker' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum InstallSource: Equatable, Sendable { case direct, homebrew }

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String, source: InstallSource)
    case failed
}

/// Pure version/source logic. No Sparkle, no I/O — fully unit-testable.
public struct UpdateChecker {
    /// True when `latest` is strictly newer than `current` (numeric, dot-separated).
    public static func compare(current: String, latest: String) -> Bool {
        let a = current.split(separator: ".").map { Int($0) ?? 0 }
        let b = latest.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if y != x { return y > x }
        }
        return false
    }

    /// Homebrew cask installs live under a `/Caskroom/` path (or symlink into one).
    public static func detectSource(bundlePath: String) -> InstallSource {
        bundlePath.contains("/Caskroom/") ? .homebrew : .direct
    }

    public static func state(current: String, latest: String?, source: InstallSource) -> UpdateState {
        guard let latest else { return .failed }
        return compare(current: current, latest: latest)
            ? .available(version: latest, source: source)
            : .upToDate
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdateCheckerTests`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/UpdateChecker.swift Tests/AignalsCoreTests/UpdateCheckerTests.swift
git commit -m "feat(update): pure UpdateChecker version/source logic"
```

---

### Task 2: Add Sparkle dependency to the app target

**Files:**
- Modify: `App/Aignals/project.yml` (add `packages:` entry + app target `dependencies`)

**Interfaces:**
- Produces: Sparkle SDK (`import Sparkle`) linkable from `App/Aignals/Sources/`.

- [ ] **Step 1: Add Sparkle to xcodegen packages**

In `App/Aignals/project.yml`, extend the `packages:` block (currently only `AignalsCore`):

```yaml
packages:
  AignalsCore:
    path: ../../
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

- [ ] **Step 2: Link Sparkle into the app target**

In the same file, add to the `Aignals` target's `dependencies` (after the AignalsCore entry):

```yaml
    dependencies:
      - package: AignalsCore
        product: AignalsCore
      - package: Sparkle
        product: Sparkle
```

- [ ] **Step 3: Regenerate the Xcode project and verify Sparkle resolves**

Run: `cd App/Aignals && xcodegen generate && cd -`
Then confirm the package is referenced:
Run: `grep -c "sparkle-project/Sparkle" App/Aignals/Aignals.xcodeproj/project.pbxproj`
Expected: a non-zero count (Sparkle package reference present).

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/project.yml
git commit -m "build(update): add Sparkle SwiftPM dependency to app target"
```

---

### Task 3: `UpdaterService` — Sparkle wrapper + delegate

**Files:**
- Create: `App/Aignals/Sources/UpdaterService.swift`

**Interfaces:**
- Consumes: `UpdateChecker`, `UpdateState`, `InstallSource` from AignalsCore (Task 1).
- Produces: `@MainActor @Observable final class UpdaterService` (matches the codebase's `@Observable AppViewModel` pattern, not `ObservableObject`) with `private(set) var state: UpdateState`; `func probe()` (silent, updates `state`); `func startUpdate()` (direct install via Sparkle UI); `init()` wiring `SPUUpdater` with self as `SPUUpdaterDelegate` and a `SPUStandardUserDriver`.

- [ ] **Step 1: Write the implementation**

`UpdaterService` cannot be unit-tested (it drives Sparkle IO — verified manually in Task 7). Write it directly, using `UpdateChecker` for all decisions so the logic stays covered by Task 1's tests. It is `@Observable` (Swift macro) so SwiftUI re-renders when `state` changes — matching how `AppViewModel` is written. `@Observable` requires a class; `SPUUpdaterDelegate` needs `NSObject` conformance, so we apply `@Observable` to an `NSObject` subclass.

```swift
import Foundation
import Observation
import Sparkle
import AignalsCore

/// Confines the Sparkle SDK to the app target. Drives our own silent probes
/// (Sparkle's built-in scheduler is disabled via Info.plist) and publishes an
/// UpdateState the UI reads. Only startUpdate() presents Sparkle's own UI.
@MainActor @Observable
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private(set) var state: UpdateState = .idle

    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private let driver: SPUStandardUserDriver

    override init() {
        driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                             userDriver: driver, delegate: nil)
        super.init()
        updater.delegate = self
        try? updater.start()
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    private var source: InstallSource {
        UpdateChecker.detectSource(bundlePath: Bundle.main.bundlePath)
    }

    /// Silent probe — no Sparkle UI. Feeds the badge/About state.
    func probe() {
        state = .checking
        updater.checkForUpdateInformation()
    }

    /// User clicked "Update Now" (direct installs) — presents Sparkle's dialog.
    func startUpdate() {
        updater.checkForUpdates()
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.state = UpdateChecker.state(current: self.currentVersion,
                                             latest: item.displayVersionString,
                                             source: self.source)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.state = .upToDate }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            // A "no update found" abort is not a failure; anything else is.
            if (error as NSError).code == Int(Sparkle.SUError.noUpdateError.rawValue) {
                self.state = .upToDate
            } else {
                self.state = .failed
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles via the app build**

Run: `cd App/Aignals && xcodegen generate && cd -`
Run:
```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Expected: BUILD SUCCEEDED. If `SUError.noUpdateError` naming differs in the pinned Sparkle version, adjust the error-code check to Sparkle's actual `SUError` case (compile error will name it).

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/UpdaterService.swift
git commit -m "feat(update): UpdaterService Sparkle wrapper with silent probe"
```

---

### Task 4: Wire UpdaterService into the app + periodic probe

**Files:**
- Modify: `App/Aignals/Sources/AignalsApp.swift` (the `@main struct AignalsApp: App`)

**Interfaces:**
- Consumes: `UpdaterService` (Task 3).
- Produces: `updater` passed by parameter into `MenuContent` and `SettingsView` (Tasks 5, 6) — matching how `vm` is already passed (`MenuContent(vm:)`, `SettingsView(vm:)`), NOT via `@EnvironmentObject`.

- [ ] **Step 1: Own the UpdaterService**

In `AignalsApp`, alongside `@State private var vm = AppViewModel()`, add:

```swift
@State private var updater = UpdaterService()
```

- [ ] **Step 2: Pass it to the two views that show update UI, and probe periodically**

Update the `MenuContent` and `SettingsView` construction to pass `updater`, and add a probe loop mirroring the existing quote-polling `.task`. In the `MenuBarExtra` content:

```swift
MenuContent(vm: vm, updater: updater)
    .task {
        while !Task.isCancelled {
            vm.fetchQuoteIfNeeded()
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        }
    }
    .task {
        // Probe on launch, then every 6 hours (Sparkle's own scheduler is off).
        while !Task.isCancelled {
            updater.probe()
            try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
        }
    }
```

And the settings window:

```swift
Window("Aignals Settings", id: "settings") {
    SettingsView(vm: vm, updater: updater)
}
```

(Tasks 5 and 6 add the matching `updater` init parameter to `MenuContent` and `SettingsView` respectively; do this task's edits together with them if building incrementally, or stub the parameter now.)

- [ ] **Step 3: Verify the app builds**

Run:
```bash
cd App/Aignals && xcodegen generate && cd -
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/
git commit -m "feat(update): own UpdaterService, probe on launch + every 6h"
```

---

### Task 5: Settings-button "update available" badge

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift` (the `⚙ Settings…` button at line ~293)

**Interfaces:**
- Consumes: `UpdaterService.state` (Task 3/4) as an init parameter (matches the existing `vm` parameter).

- [ ] **Step 1: Add an `updater` property + init parameter to MenuContent**

`MenuContent` currently takes `vm`. Add a stored `updater` alongside it (same access pattern). Find the property declaration for `vm` (e.g. `let vm: AppViewModel` or `@Bindable var vm`) and add next to it:

```swift
let updater: UpdaterService
```

If `MenuContent` has an explicit memberwise usage `MenuContent(vm: vm)`, the added stored property makes `MenuContent(vm:updater:)` the call site (already updated in Task 4). No custom init needed for a struct with stored properties.

- [ ] **Step 2: Overlay a red dot on the Settings button when an update is available**

Find the `menuButton("⚙", "Settings…") { ... }` call (~line 293). Wrap/overlay it so a dot shows when `state` is `.available`. Add a computed helper on the view:

```swift
private var updateAvailable: Bool {
    if case .available = updater.state { return true }
    return false
}
```

Attach to the Settings button:

```swift
.overlay(alignment: .topTrailing) {
    if updateAvailable {
        Circle().fill(.red).frame(width: 7, height: 7).offset(x: 2, y: -2)
    }
}
.help(updateAvailable ? "Update available" : "Settings")
```

- [ ] **Step 3: Verify the app builds**

Run:
```bash
cd App/Aignals && xcodegen generate && cd -
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(update): red-dot badge on Settings button when update available"
```

---

### Task 6: About-page update section

**Files:**
- Modify: `App/Aignals/Sources/SettingsView.swift` (`aboutPage`, ~line 214, below the `Version X.Y.Z` text at ~line 221)

**Interfaces:**
- Consumes: `UpdaterService` (`state`, `probe()`, `startUpdate()`) as an init parameter; `UpdateState`, `InstallSource` from AignalsCore.

- [ ] **Step 1: Add an `updater` property + init parameter to SettingsView**

`SettingsView` currently takes `vm`. Add next to the `vm` property:

```swift
let updater: UpdaterService
```

This makes the call site `SettingsView(vm:updater:)` (already updated in Task 4).

- [ ] **Step 2: Render an update section by state, below the Version line**

Add this view and place `updateSection` right after `Text("Version \(appVersion)")` in `aboutPage`:

```swift
@ViewBuilder private var updateSection: some View {
    switch updater.state {
    case .idle, .checking:
        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
    case .upToDate:
        VStack(alignment: .leading, spacing: 6) {
            Text("You're on the latest version.").foregroundStyle(.secondary)
            Button("Check for Updates") { updater.probe() }
        }
    case .available(let version, .direct):
        VStack(alignment: .leading, spacing: 6) {
            Text("v\(version) is available.")
            Button("Update Now") { updater.startUpdate() }
        }
    case .available(let version, .homebrew):
        VStack(alignment: .leading, spacing: 6) {
            Text("v\(version) is available. Update via Homebrew:")
            HStack {
                Text("brew upgrade --cask aignals")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew upgrade --cask aignals", forType: .string)
                }
            }
        }
    case .failed:
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't check for updates.").foregroundStyle(.secondary)
            Button("Retry") { updater.probe() }
        }
    }
}
```

- [ ] **Step 3: Verify the app builds**

Run:
```bash
cd App/Aignals && xcodegen generate && cd -
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/SettingsView.swift
git commit -m "feat(update): About-page update section (direct/homebrew/failed states)"
```

---

### Task 7: CI — sign updates, generate appcast, publish to Pages, cask auto_updates

**Files:**
- Modify: `.github/workflows/release.yml` (Self-sign step ~line 57; add appcast steps after Package ~line 76; cask heredoc ~line 120)
- Modify: `homebrew/aignals.rb` (add `auto_updates true`)

**Interfaces:**
- Consumes: secret `SPARKLE_PRIVATE_KEY`; the `.dmg` produced by the Package step.
- Produces: `docs/appcast.xml` on the default branch (served at the feed URL); signed release assets.

- [ ] **Step 1: Confirm the embedded Sparkle helpers get signed**

The existing Self-sign step (`codesign --force --deep --sign -`) recurses into the app bundle, which includes Sparkle's `Autoupdate`/XPC helpers. Harden the verify to catch a broken nested signature. Replace the Self-sign step body with:

```bash
APP="./build/Build/Products/Release/Aignals.app"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

- [ ] **Step 2: Add a "Sign update + generate appcast" step after the Package step**

Insert after the `Package zip + dmg` step (~line 76), before `Upload workflow artifacts`. This uses Sparkle's `generate_appcast`, which both signs and writes the appcast for every archive in a directory:

```yaml
      - name: Sign update + generate appcast
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
            echo "::error::SPARKLE_PRIVATE_KEY not set — cannot sign the update."
            exit 1
          fi
          # Fetch Sparkle's CLI tools (generate_appcast, sign_update).
          SPARKLE_VER="2.6.4"
          curl -L -o sparkle.tar.xz \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VER}/Sparkle-${SPARKLE_VER}.tar.xz"
          mkdir -p sparkle && tar -xf sparkle.tar.xz -C sparkle
          # generate_appcast signs each archive in dist/ and (re)writes appcast.xml.
          # Feed URL base ensures enclosure URLs point at the GitHub Releases asset.
          printf '%s' "$SPARKLE_PRIVATE_KEY" > sparkle_key
          ./sparkle/bin/generate_appcast \
            --ed-key-file sparkle_key \
            --download-url-prefix "https://github.com/Jesse1211/Aignals/releases/download/${{ github.ref_name }}/" \
            dist/
          rm -f sparkle_key
          # generate_appcast wrote dist/appcast.xml — stage it for Pages.
          mkdir -p docs
          cp dist/appcast.xml docs/appcast.xml
          echo "appcast enclosure(s):"; grep -o 'url="[^"]*"' dist/appcast.xml || true
```

Note: `generate_appcast` signs the archives in place and points enclosures at `--download-url-prefix` + filename — the exact assets uploaded to the release. No re-packaging occurs, so signatures stay valid.

- [ ] **Step 3: Publish appcast.xml to GitHub Pages (commit docs/appcast.xml)**

Add after the `Publish GitHub Release` step:

```yaml
      - name: Publish appcast to GitHub Pages
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git fetch origin main
          git checkout main
          cp dist/appcast.xml docs/appcast.xml
          git add docs/appcast.xml
          git commit -m "chore(release): update appcast for ${{ github.ref_name }}" || echo "no appcast change"
          git push origin main
```

- [ ] **Step 4: Add `auto_updates true` to both cask sources**

In `homebrew/aignals.rb`, add after the `app "Aignals.app"` line:

```ruby
  auto_updates true
```

In `.github/workflows/release.yml`, in the generated cask heredoc (~line 129), add the same line after `app "Aignals.app"`:

```ruby
            app "Aignals.app"
            auto_updates true
```

- [ ] **Step 5: Lint the workflow and cask**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo YAML-OK`
Expected: `YAML-OK`.
Run: `grep -n "auto_updates true" homebrew/aignals.rb .github/workflows/release.yml`
Expected: a match in each file.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml homebrew/aignals.rb
git commit -m "ci(update): sign updates, publish appcast to Pages, cask auto_updates"
```

---

## Manual Verification (post-implementation, maintainer)

Not automatable — walk through once after cutting a test release:

1. **Cut a test tag** with the app version temporarily lowered, let `release.yml` run.
2. **Signing**: CI's "Sign update + generate appcast" step succeeds; `dist/appcast.xml` has an `edSignature` and an enclosure URL pointing at the release asset.
3. **Reachability**: `curl https://jesse1211.github.io/Aignals/appcast.xml` returns the new version + signature (allow a few minutes for the Pages CDN to refresh — a transiently stale feed is not a failure).
4. **Verify + update on a CLEAN machine** (not the dev box): install a lower-version `.dmg` → open About → see "vX.Y.Z is available" → click **Update Now** → Sparkle verifies with `SUPublicEDKey`, downloads, replaces, relaunches. Confirm the non-notarized self-signed app actually relaunches without a Gatekeeper block.
5. **Source branch**: install via `brew install --cask aignals` → About page shows the `brew upgrade` guidance + Copy button, NOT the Update Now button.

## Self-Review Notes

- Spec coverage: UpdateChecker (Task 1) ✓, Sparkle dep confined to app target (Task 2) ✓, silent-probe delegate + disabled scheduler (Task 3) ✓, launch/periodic probe (Task 4) ✓, badge (Task 5) ✓, About states incl. homebrew/direct/failed (Task 6) ✓, CI signing + appcast + Pages + re-sign helpers + cask auto_updates + enclosure-exact-file (Task 7) ✓, manual clean-machine verification ✓.
- Type consistency: `UpdateState`/`InstallSource` names and `.available(version:source:)` shape identical across Tasks 1, 3, 5, 6.
- Sparkle version pins (`2.6.0` package floor, `2.6.4` CLI) are placeholders to confirm against the latest 2.x at implementation time; keep the SwiftPM floor ≤ the CLI version.

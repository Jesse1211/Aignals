# Configurable Status Sounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose the alert sound for the 🟡 waiting-permission and 🟢 waiting-input states from a set of macOS system sounds (plus a silent "None"), audible on selection; 🔴 working and ⚫ disconnected stay silent.

**Architecture:** A pure `AlertSound` enum in `AignalsCore` (curated system-sound names + `.none`) backs two new global fields on `AignalsConfig` (`permissionSound`, `inputSound`), decoded with the same backward-compatible pattern as `theme`. The playback path in `AppViewModel` reads those fields instead of hard-coded names. Two `Picker`s in the Settings fold bind to ViewModel bridge properties that preview the chosen sound on selection.

**Tech Stack:** Swift 5.10, SwiftPM (`AignalsCore` library + `AignalsCoreTests`), SwiftUI/AppKit (`App/Aignals/Sources/`), XCTest. Build/test loop: `swift test` for Core; `(cd App/Aignals && xcodegen generate)` → `xcodebuild ... -scheme Aignals -configuration Debug` for the app.

## Global Constraints

- **Swift tools version 5.9 / strict concurrency.** New `AignalsCore` types must be `Sendable`. (Theme is `enum ... : Sendable`.)
- **`AignalsCore` is pure** — no SwiftUI/AppKit imports. `AlertSound` lives there; only Foundation.
- **Backward compatibility** — new `config.json` keys MUST decode to the prior hard-coded defaults (Ping/Glass) when absent, via `decodeIfPresent(...) ?? default`. Never break an existing config.
- **ADR-21 preserved** — `.working` and `.disconnected` never produce a sound. Do not add a case for them.
- **No new bundle assets** — system sounds only, resolved by `NSSound(named:)` with an `/System/Library/Sounds/<Name>.aiff` afplay fallback (existing `play(_:)`).
- **TDD + frequent commits** — failing test first, minimal impl, commit per task.

---

### Task 1: `AlertSound` enum (pure, in AignalsCore)

**Files:**
- Create: `Sources/AignalsCore/AlertSound.swift`
- Test: `Tests/AignalsCoreTests/AlertSoundTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum AlertSound: String, Codable, CaseIterable, Sendable { case none, ping, glass, funk, tink, pop, hero, submarine, blow }`
  - `public var displayName: String`
  - `public var systemSoundName: String?` — `nil` for `.none`; otherwise the capitalized macOS system-sound name (e.g. `"Ping"`).

- [ ] **Step 1: Write the failing test**

Create `Tests/AignalsCoreTests/AlertSoundTests.swift`:

```swift
import XCTest
@testable import AignalsCore

final class AlertSoundTests: XCTestCase {
    func testNoneHasNoSystemSound() {
        XCTAssertNil(AlertSound.none.systemSoundName)
    }

    func testKnownDefaultsMapToPingAndGlass() {
        XCTAssertEqual(AlertSound.ping.systemSoundName, "Ping")
        XCTAssertEqual(AlertSound.glass.systemSoundName, "Glass")
    }

    func testAllCasesHaveNonEmptyDisplayName() {
        for s in AlertSound.allCases {
            XCTAssertFalse(s.displayName.isEmpty, "\(s) has empty displayName")
        }
    }

    func testNonNoneCasesResolveToRealSystemSoundFiles() {
        for s in AlertSound.allCases where s != .none {
            let name = try! XCTUnwrap(s.systemSoundName, "\(s) must have a name")
            let path = "/System/Library/Sounds/\(name).aiff"
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "missing system sound file: \(path)")
        }
    }

    func testRawValueRoundTrip() throws {
        for s in AlertSound.allCases {
            let data = try JSONEncoder().encode(s)
            let back = try JSONDecoder().decode(AlertSound.self, from: data)
            XCTAssertEqual(back, s)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AlertSoundTests`
Expected: FAIL — "cannot find 'AlertSound' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Sources/AignalsCore/AlertSound.swift`:

```swift
import Foundation

/// A user-selectable alert sound for a waiting state (ADR-28/29). Pure data so
/// it lives in `AignalsCore` and is unit-tested; the App target maps the cases
/// to playback. `.none` is silent (`systemSoundName == nil`). Every other case
/// names a stock macOS system sound resolvable by `NSSound(named:)` and present
/// at `/System/Library/Sounds/<Name>.aiff`.
public enum AlertSound: String, Codable, CaseIterable, Sendable {
    case none
    case ping
    case glass
    case funk
    case tink
    case pop
    case hero
    case submarine
    case blow

    /// Human-readable label shown in the picker.
    public var displayName: String {
        switch self {
        case .none:      return "None"
        case .ping:      return "Ping"
        case .glass:     return "Glass"
        case .funk:      return "Funk"
        case .tink:      return "Tink"
        case .pop:       return "Pop"
        case .hero:      return "Hero"
        case .submarine: return "Submarine"
        case .blow:      return "Blow"
        }
    }

    /// The macOS system-sound name to play, or `nil` for `.none` (silent).
    public var systemSoundName: String? {
        switch self {
        case .none:      return nil
        case .ping:      return "Ping"
        case .glass:     return "Glass"
        case .funk:      return "Funk"
        case .tink:      return "Tink"
        case .pop:       return "Pop"
        case .hero:      return "Hero"
        case .submarine: return "Submarine"
        case .blow:      return "Blow"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AlertSoundTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/AlertSound.swift Tests/AignalsCoreTests/AlertSoundTests.swift
git commit -m "feat(core): add AlertSound enum (system sounds + None)"
```

---

### Task 2: Add `permissionSound` / `inputSound` to `AignalsConfig`

**Files:**
- Modify: `Sources/AignalsCore/ConfigStore.swift` (the `AignalsConfig` struct, lines 3–36)
- Test: `Tests/AignalsCoreTests/ConfigStoreTests.swift` (append cases)

**Interfaces:**
- Consumes: `AlertSound` from Task 1.
- Produces:
  - `AignalsConfig.permissionSound: AlertSound` (default `.ping`)
  - `AignalsConfig.inputSound: AlertSound` (default `.glass`)
  - Both decode to their defaults when the JSON key is absent.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AignalsCoreTests/ConfigStoreTests.swift` (before the final closing brace):

```swift
    func testSoundsDefaultToPingAndGlass() throws {
        let store = ConfigStore(paths: try tmpHome())
        XCTAssertEqual(store.config.permissionSound, .ping)
        XCTAssertEqual(store.config.inputSound, .glass)
    }

    func testSoundsRoundtrip() throws {
        let paths = try tmpHome()
        let store = ConfigStore(paths: paths)
        var c = store.config
        c.permissionSound = .funk
        c.inputSound = .none
        store.save(c)

        let reload = ConfigStore(paths: paths)
        XCTAssertEqual(reload.config.permissionSound, .funk)
        XCTAssertEqual(reload.config.inputSound, .none)
    }

    func testSoundsDecodeDefaultsWhenAbsent() throws {
        let paths = try tmpHome()
        // Legacy config.json without the sound keys must keep Ping/Glass.
        try Data(#"{"launchAtLogin":false,"dismissedInstallPrompt":false,"soundEnabled":true,"theme":"glassDark"}"#.utf8)
            .write(to: paths.configFile)
        let store = ConfigStore(paths: paths)
        XCTAssertEqual(store.config.permissionSound, .ping)
        XCTAssertEqual(store.config.inputSound, .glass)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL — `value of type 'AignalsConfig' has no member 'permissionSound'`.

- [ ] **Step 3: Modify `AignalsConfig`**

In `Sources/AignalsCore/ConfigStore.swift`, add the two stored properties after `theme` (after line 11):

```swift
    /// Alert sound for 🟡 waiting-permission transitions (ADR-28/31). Decodes to
    /// `.ping` when absent so existing config.json keeps the old default.
    public var permissionSound: AlertSound
    /// Alert sound for 🟢 waiting-input transitions (ADR-28/31). Decodes to
    /// `.glass` when absent so existing config.json keeps the old default.
    public var inputSound: AlertSound
```

Update the `init` signature and body (replace the existing `init`, lines 13–18):

```swift
    public init(launchAtLogin: Bool, dismissedInstallPrompt: Bool, soundEnabled: Bool = true, theme: Theme = .glassDark, permissionSound: AlertSound = .ping, inputSound: AlertSound = .glass) {
        self.launchAtLogin = launchAtLogin
        self.dismissedInstallPrompt = dismissedInstallPrompt
        self.soundEnabled = soundEnabled
        self.theme = theme
        self.permissionSound = permissionSound
        self.inputSound = inputSound
    }
```

Update `default` (line 20):

```swift
    public static let `default` = AignalsConfig(launchAtLogin: false, dismissedInstallPrompt: false, soundEnabled: true, theme: .glassDark, permissionSound: .ping, inputSound: .glass)
```

Add the two `CodingKeys` (inside the enum at lines 22–27):

```swift
        case permissionSound
        case inputSound
```

Add the two decode lines at the end of `init(from:)` (after the `theme` line, line 34):

```swift
        self.permissionSound = try container.decodeIfPresent(AlertSound.self, forKey: .permissionSound) ?? .ping
        self.inputSound = try container.decodeIfPresent(AlertSound.self, forKey: .inputSound) ?? .glass
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS (all existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/ConfigStore.swift Tests/AignalsCoreTests/ConfigStoreTests.swift
git commit -m "feat(core): persist permissionSound/inputSound in AignalsConfig"
```

---

### Task 3: Read config in the playback path

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift` — `handleSessionSounds()` call site (line 292), `sound(forTransitionInto:)` (lines 314–320)

**Interfaces:**
- Consumes: `config.permissionSound` / `config.inputSound` (Task 2), `AlertSound.systemSoundName` (Task 1).
- Produces: `sound(forTransitionInto:)` becomes an **instance** method returning the configured system-sound name (or `nil`).

This task has no unit test (XCTest can't assert audio / drive `MenuBarExtra`; same as the existing sound code — see spec "Testing"). Verify by compile + the manual QA in Task 5.

- [ ] **Step 1: Change `sound(forTransitionInto:)` to read config**

In `App/Aignals/Sources/AppViewModel.swift`, replace the method at lines 314–320:

```swift
    /// The macOS system sound name for a transition INTO `state`, or `nil` for
    /// states that never alert (ADR-21: working/disconnected are silent) and for
    /// a state whose configured sound is `.none`. The 🟡/🟢 sounds are
    /// user-selectable via `config.permissionSound` / `config.inputSound`
    /// (ADR-28); defaults are Ping/Glass.
    private func sound(forTransitionInto state: SessionState) -> String? {
        switch state {
        case .waitingPermission: return config.permissionSound.systemSoundName
        case .waitingInput:      return config.inputSound.systemSoundName
        case .working, .disconnected: return nil
        }
    }
```

- [ ] **Step 2: Update the call site**

In `handleSessionSounds()`, line 292, change `Self.sound(forTransitionInto:` to the instance call:

```swift
            guard let sound = sound(forTransitionInto: session.state) else { continue }
```

- [ ] **Step 3: Build the app to verify it compiles**

Run:
```bash
(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): play the configured per-state sound (defaults Ping/Glass)"
```

---

### Task 4: ViewModel bridge properties + preview-on-select

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift` — add bridge properties in the `extension` block near `theme` (after line 490), and a `preview` helper near `play(_:)`

**Interfaces:**
- Consumes: `config.permissionSound`/`config.inputSound` (Task 2), the existing `private static func play(_ name: String)` (lines 324–335), `AlertSound.systemSoundName` (Task 1).
- Produces:
  - `var permissionSound: AlertSound { get set }`
  - `var inputSound: AlertSound { get set }`
  - Setting either writes config (bumps `configVersion`) and, if the new value is not `.none`, plays it once for immediate feedback.

No unit test (audio + UI binding — manual QA in Task 5).

- [ ] **Step 1: Add the bridge properties**

In `App/Aignals/Sources/AppViewModel.swift`, after the `theme` property (after line 490, inside the same `extension AppViewModel`), add:

```swift
    /// Alert sound for 🟡 waiting-permission (ADR-28/31). Reads/writes
    /// `config.permissionSound` through the config setter (bumps `configVersion`);
    /// previews the new sound once so the choice is audible.
    var permissionSound: AlertSound {
        get { config.permissionSound }
        set {
            var c = config; c.permissionSound = newValue; config = c
            Self.preview(newValue)
        }
    }

    /// Alert sound for 🟢 waiting-input (ADR-28/31). Same pattern as
    /// `permissionSound`, backed by `config.inputSound`.
    var inputSound: AlertSound {
        get { config.inputSound }
        set {
            var c = config; c.inputSound = newValue; config = c
            Self.preview(newValue)
        }
    }

    /// Play `sound` once for selection feedback. `.none` is silent.
    private static func preview(_ sound: AlertSound) {
        if let name = sound.systemSoundName { play(name) }
    }
```

(`play(_:)` is `private static` and already in this file, so `preview` can call it. No visibility change needed.)

- [ ] **Step 2: Build the app to verify it compiles**

Run:
```bash
(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): AppViewModel.permissionSound/inputSound with preview-on-select"
```

---

### Task 5: Settings UI — two sound `Picker`s

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift` — insert under the "Play sounds" toggle (after line 248)

**Interfaces:**
- Consumes: `vm.soundEnabled`, `vm.permissionSound`, `vm.inputSound` (Task 4), `AlertSound.allCases` + `displayName` (Task 1).
- Produces: UI only (no downstream consumer).

No unit test (MenuBarExtra UI — manual QA below).

- [ ] **Step 1: Add the two pickers**

In `App/Aignals/Sources/MenuContent.swift`, immediately after the "Play sounds" `Toggle` block (after line 248, before the Launch-at-Login `if` at line 252), insert:

```swift
        // Per-state sound pickers (ADR-28): shown only when sound is on. Each
        // binds to the ViewModel bridge, which previews the choice on selection.
        if vm.soundEnabled {
            Picker("🟡 Permission", selection: Binding(
                get: { vm.permissionSound },
                set: { vm.permissionSound = $0 }
            )) {
                ForEach(AlertSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            Picker("🟢 Input", selection: Binding(
                get: { vm.inputSound },
                set: { vm.inputSound = $0 }
            )) {
                ForEach(AlertSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
```

If `MenuContent.swift` does not already `import AignalsCore`, add it at the top (it references `SessionState` already, so the import is present — verify and only add if missing).

- [ ] **Step 2: Build the app to verify it compiles**

Run:
```bash
(cd App/Aignals && xcodegen generate) && xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual QA (run the app)**

```bash
open DerivedData/Build/Products/Debug/Aignals.app
```
Verify in the menu-bar dropdown → Settings:
1. "Play sounds" on → two pickers appear; turn it off → pickers disappear.
2. Pick each sound in 🟡 Permission and 🟢 Input → the sound plays immediately on selection; "None" plays nothing.
3. Selection persists: quit the app, reopen, the pickers show the last choices (written to `~/.aignals/config.json`).
4. (Optional, end-to-end) drive a real session into 🟡 then 🟢 and confirm the *selected* sounds play, respecting the 3s throttle and per-row mute.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(ui): add per-state sound pickers in Settings"
```

---

### Task 6: Run the full suite + update the manual checklist

**Files:**
- Modify: `docs/superpowers/specs/manual-test-checklist.md` (add a sound-picker line)

- [ ] **Step 1: Run the full Core test suite**

Run: `swift test`
Expected: all pass (existing + `AlertSoundTests` + 3 new `ConfigStoreTests`).

- [ ] **Step 2: Add a checklist entry**

Append to `docs/superpowers/specs/manual-test-checklist.md` a bullet:

```markdown
- [ ] Settings → 🟡 Permission / 🟢 Input sound pickers: each selection previews
      audibly, "None" is silent, the choice persists across relaunch, and a real
      🟡/🟢 transition plays the selected sound (working/disconnected stay silent).
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/manual-test-checklist.md
git commit -m "docs: add status-sound picker to manual test checklist"
```

---

## Self-Review

**1. Spec coverage:**
- AlertSound enum (spec §1) → Task 1. ✅
- Config fields + backward-compat decode (spec §2) → Task 2. ✅
- Playback reads config, working/disconnected silent (spec §3) → Task 3. ✅
- ViewModel bridge + preview-on-select (spec §4) → Task 4. ✅
- Two Settings pickers, shown only when soundEnabled (spec §5) → Task 5. ✅
- Tests: AlertSoundTests + ConfigStore extensions (spec "Testing") → Tasks 1, 2; full-suite + manual checklist → Task 6. ✅
- ADR-28..31 honored: per-state 🟡/🟢 only, system sounds, global, backward-compat + preview. ✅

**2. Placeholder scan:** No TBD/TODO; every code step has full code; manual-QA steps are explicit because the targets (audio, MenuBarExtra) are genuinely not XCTest-drivable, consistent with the existing sound/theme code.

**3. Type consistency:** `AlertSound` / `systemSoundName` / `displayName` used identically across Tasks 1–5. `permissionSound`/`inputSound` names match between config (Task 2), playback (Task 3), bridge (Task 4), and UI (Task 5). `sound(forTransitionInto:)` consistently becomes an instance method (Task 3) with its sole call site updated. `play(_:)`/`preview` kept `private static`.

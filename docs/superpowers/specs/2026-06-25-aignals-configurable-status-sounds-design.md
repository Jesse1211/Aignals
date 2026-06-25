# Aignals — Configurable Status Sounds (design)

**Date:** 2026-06-25
**Status:** approved
**Ships in:** v0.3.0 (alongside the UI redesign + themes)

## Summary

Make the alert sound for the 🟡 *waiting-permission* and 🟢 *waiting-input* states
**user-selectable from a set of macOS system sounds**, with a "None" (silent)
option, audible on selection. The 🔴 *working* and ⚫ *disconnected* states stay
silent (unchanged — ADR-21). The currently hard-coded `Ping` / `Glass` names
become the **defaults**.

Everything else about the sound subsystem is unchanged: the per-session throttle,
startup/adoption silence, per-row mute, and the global `soundEnabled` toggle all
keep working exactly as today.

## Scope

In scope:
- A pure `AlertSound` enum in `AignalsCore` (a curated list of macOS system sounds + `.none`).
- Two new global config fields `permissionSound` / `inputSound` on `AignalsConfig`,
  with the same backward-compatible decode pattern as `theme`.
- Reading those fields in the playback path instead of the hard-coded names.
- Two `Picker`s in the Settings fold (shown only when `soundEnabled` is on), each
  previewing the chosen sound on selection.

Explicitly out of scope (decided during brainstorming):
- **No sound for 🔴 working** — keeps ADR-21; a session starting work should not beep.
- **No per-session sound** — the choice is global; per-session *mute* is unchanged.
- **No bundled audio assets** — system sounds only, zero new files in the bundle.

## Architecture

### 1. Data layer — `Sources/AignalsCore/AlertSound.swift` (new, pure)

```swift
public enum AlertSound: String, Codable, CaseIterable, Sendable {
    case none, ping, glass, funk, tink, pop, hero, submarine, blow

    public var displayName: String { ... }   // "None", "Ping", "Glass", ...

    /// The macOS system-sound name (resolvable by NSSound / present at
    /// /System/Library/Sounds/<Name>.aiff), or nil for `.none` (silent).
    public var systemSoundName: String? {
        switch self {
        case .none: return nil
        case .ping: return "Ping"
        case .glass: return "Glass"
        case .funk: return "Funk"
        case .tink: return "Tink"
        case .pop: return "Pop"
        case .hero: return "Hero"
        case .submarine: return "Submarine"
        case .blow: return "Blow"
        }
    }
}
```

`.none` mapping to `nil` is load-bearing: it reuses the playback path's existing
`guard let sound = …` short-circuit, so "None" simply means that state never beeps.

### 2. Config — `Sources/AignalsCore/ConfigStore.swift`

Add two fields to `AignalsConfig`, mirroring `theme` exactly:

```swift
public var permissionSound: AlertSound   // default .ping
public var inputSound: AlertSound        // default .glass
```

- `init` gets defaulted params (`permissionSound: .ping`, `inputSound: .glass`).
- `default` sets `.ping` / `.glass`.
- `CodingKeys` gains `permissionSound`, `inputSound`.
- Custom `init(from:)` decodes both with
  `decodeIfPresent(AlertSound.self, forKey:) ?? .ping / .glass` so existing
  `config.json` files upgrade to the prior behavior (Ping/Glass) with no key present.

No change to `ConfigStore.save` (atomic temp+replace already covers new fields).

### 3. Playback — `App/Aignals/Sources/AppViewModel.swift`

`sound(forTransitionInto:)` changes from a hard-coded `static` switch to reading
config (drops `static`, since it now needs `self.config`):

```swift
private func sound(forTransitionInto state: SessionState) -> String? {
    switch state {
    case .waitingPermission: return config.permissionSound.systemSoundName
    case .waitingInput:       return config.inputSound.systemSoundName
    case .working, .disconnected: return nil
    }
}
```

`handleSessionSounds()` updates its call site to `sound(forTransitionInto:)`
(instance method). The gating (known-session, changed-state, soundEnabled,
not-muted, throttle) is **unchanged**. `play(_:)` is **unchanged**.

### 4. ViewModel bridge — `App/Aignals/Sources/AppViewModel.swift`

Two computed properties mirroring `theme`, plus a preview on set:

```swift
var permissionSound: AlertSound {
    get { config.permissionSound }
    set {
        var c = config; c.permissionSound = newValue; config = c
        Self.preview(newValue)   // audible feedback on selection
    }
}
var inputSound: AlertSound { /* symmetric, config.inputSound */ }

private static func preview(_ sound: AlertSound) {
    if let name = sound.systemSoundName { play(name) }
}
```

Setting `config` bumps `configVersion` (existing pattern), so the UI re-derives.
`.none` previews nothing (no name → no play).

### 5. UI — `App/Aignals/Sources/MenuContent.swift`

In the Settings fold, directly under the existing "Play sounds" checkbox, shown
only when `vm.soundEnabled` is true:

```
☑ Play sounds
   🟡 Permission   [ Ping  ⌄ ]
   🟢 Input        [ Glass ⌄ ]
```

Each row is a `Picker` over `AlertSound.allCases` (label = `displayName`), bound
to `vm.permissionSound` / `vm.inputSound`. Picking a non-`.none` value plays it
once via the setter's preview. Styling follows the surrounding Settings rows
(padding, theme tokens) — no new picker card; the two `Picker`s live inline.

## Data flow

State transition detected (existing) → `handleSessionSounds()` → for a session
that just entered 🟡/🟢 and passes all gates → `sound(forTransitionInto:)` reads
`config.permissionSound` / `config.inputSound` → `systemSoundName` (or nil for
None) → `play(name)`. User selection flows the other way: Picker → ViewModel
setter → `ConfigStore.save` (atomic) + `configVersion` bump + one-shot preview.

## Error handling

No new failure surface:
- Unknown `rawValue` in a hand-edited `config.json` → `decodeIfPresent ?? default`
  (Ping/Glass), same as `theme`.
- A `.aiff` that can't be resolved → existing `play(_:)` already no-ops silently.
- `.none` → `systemSoundName == nil` → existing short-circuit, no beep, no error.

## Testing

- **`Tests/AignalsCoreTests/AlertSoundTests.swift` (new, SPM):**
  rawValue stability; `allCases` membership; every `displayName` non-empty;
  `AlertSound.none.systemSoundName == nil`; every non-`.none` case's `.aiff`
  exists at `/System/Library/Sounds/<Name>.aiff`; Codable round-trip.
- **`Tests/AignalsCoreTests/ConfigStoreTests.swift` (extend):**
  `permissionSound`/`inputSound` default to `.ping`/`.glass`; round-trip through
  JSON; decode to defaults when the keys are absent (backward-compat).
- **Manual QA only** (XCTest can't drive MenuBarExtra modals or assert system
  audio — same limitation as Theme and the existing sound toggle): pick each
  sound and confirm preview; trigger a real 🟡/🟢 transition and confirm the
  selected sound plays; pick "None" and confirm that state is silent; confirm an
  old config.json (no keys) still plays Ping/Glass.

## ADRs

- **ADR-28 — Configurable per-state sounds (🟡/🟢 only).** Working/disconnected
  remain silent (preserves ADR-21). The two waiting states each get a global,
  user-selectable sound. Rationale: those are the states a user actually waits on.
- **ADR-29 — System sounds, no bundled assets.** `AlertSound` maps to
  `/System/Library/Sounds/*.aiff`, reusing the NSSound→afplay path. Zero new
  bundle files; `.none` = silent via `systemSoundName == nil`.
- **ADR-30 — Global, not per-session.** One `permissionSound` + one `inputSound`
  in `AignalsConfig`; per-session control stays limited to *mute* (unchanged).
- **ADR-31 — Backward-compatible decode + preview-on-select.** New config keys
  decode to the prior hard-coded defaults (Ping/Glass) when absent; selecting a
  sound previews it once for immediate feedback.

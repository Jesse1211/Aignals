# Aignals UI Redesign + Themes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the menu-bar dropdown + About window (cards, glowing status dots, brand header) and add a user-selectable Theme feature (Glass Light, Glass Dark [default], Terminal, Vibrant) switched via a side pop-out picker and persisted in `AignalsConfig.theme`.

**Architecture:** A pure `Theme` enum in `AignalsCore` holds the four themes and their style tokens; it is unit-tested and persisted in `AignalsConfig` (backward-compatible decode). The SwiftUI App target reads the current theme from `AppViewModel` and applies its tokens to the dropdown (`MenuContent`), a new `ThemePicker` popover, and `AboutView`. Pure logic is the automated gate; visual application is verified by CI build + manual smoke (per the Phase-8 convention — no driveable UI-test harness).

**Tech Stack:** Swift 5.9, SwiftUI (`MenuBarExtra .window`), AppKit (`NSVisualEffectView`), XcodeGen, SPM (XCTest for `AignalsCore`), bats (unaffected here).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-25-aignals-ui-redesign-design.md`. It is canonical; do not re-litigate decisions.
- Default theme = `glassDark`. Applied via BOTH `AignalsConfig.default` AND `decodeIfPresent(...) ?? .glassDark` so an old `config.json` without a `theme` key decodes to Glass Dark.
- `Theme` enum lives in `Sources/AignalsCore/` (pure, SPM-unit-tested). SwiftUI styling lives under `App/Aignals/Sources/`.
- Persist via the EXISTING `ConfigStore` atomic save (temp-file + `replaceItemAt`). Do NOT add a new store.
- macOS deployment target 14.0; Swift version 5.9 (see `App/Aignals/project.yml`).
- Animations are OUT OF SCOPE. Theme switch may be instant (no transition).
- The menu-bar `StatusIcon` image is OUT OF SCOPE (template-color constraint).
- Local build/run loop: `(cd App/Aignals && xcodegen generate)` → `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build` → `open App/Aignals/DerivedData/Build/Products/Debug/Aignals.app`. The `.xcodeproj` and `DerivedData/` are gitignored — only `project.yml` is committed.
- Commit hygiene: never `git add -A`, never `--no-verify`. Stage specific files. Commit messages end with the Co-Authored-By trailer used in this repo.
- Run `swift test` after Core changes; run `git status --short` after each commit; STOP and report on any test failure.

---

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `Sources/AignalsCore/Theme.swift` | Create | `Theme` enum (4 cases) + `displayName` + `swatchHexes` style tokens. Pure, Codable via `String` raw value. |
| `Sources/AignalsCore/ConfigStore.swift` | Modify | Add `theme: Theme` to `AignalsConfig` with backward-compatible decode (default `.glassDark`). |
| `Tests/AignalsCoreTests/ThemeTests.swift` | Create | Raw values, `allCases`, `displayName`, `swatchHexes` non-empty. |
| `Tests/AignalsCoreTests/ConfigStoreTests.swift` | Modify | Theme default, round-trip, decode-when-absent → glassDark. |
| `App/Aignals/Sources/ThemeStyle.swift` | Create | SwiftUI-side mapping from `Theme` → concrete style values (colors, font, material kind, row treatment) + an `NSVisualEffectView` wrapper for Glass themes. |
| `App/Aignals/Sources/AppViewModel.swift` | Modify | Add `theme` get/set bridging `config.theme`. |
| `App/Aignals/Sources/ThemePicker.swift` | Create | The side pop-out card: 4 swatch rows + ✓, binds to `vm.theme`. |
| `App/Aignals/Sources/MenuContent.swift` | Modify | Apply theme tokens to header/rows/footer/empty/error; add the "🎨 Theme ▸" row that presents the picker. |
| `App/Aignals/Sources/AboutView.swift` | Modify | Apply theme styling (logo, version, link). |

---

## Task 1: `Theme` enum in AignalsCore

**Files:**
- Create: `Sources/AignalsCore/Theme.swift`
- Test: `Tests/AignalsCoreTests/ThemeTests.swift`

**Interfaces:**
- Produces: `public enum Theme: String, Codable, CaseIterable, Sendable { case glassLight, glassDark, terminal, vibrant }`; `public var displayName: String`; `public var swatchHexes: [String]` (1–3 hex strings previewing the theme, used by the picker swatch).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AignalsCoreTests/ThemeTests.swift
import XCTest
@testable import AignalsCore

final class ThemeTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(Theme.glassLight.rawValue, "glassLight")
        XCTAssertEqual(Theme.glassDark.rawValue, "glassDark")
        XCTAssertEqual(Theme.terminal.rawValue, "terminal")
        XCTAssertEqual(Theme.vibrant.rawValue, "vibrant")
    }

    func testAllCasesCountIsFour() {
        XCTAssertEqual(Theme.allCases.count, 4)
    }

    func testDisplayNames() {
        XCTAssertEqual(Theme.glassLight.displayName, "Glass Light")
        XCTAssertEqual(Theme.glassDark.displayName, "Glass Dark")
        XCTAssertEqual(Theme.terminal.displayName, "Terminal")
        XCTAssertEqual(Theme.vibrant.displayName, "Vibrant")
    }

    func testSwatchHexesNonEmpty() {
        for t in Theme.allCases {
            XCTAssertFalse(t.swatchHexes.isEmpty, "\(t) must have at least one swatch hex")
            for hex in t.swatchHexes {
                XCTAssertTrue(hex.hasPrefix("#"), "swatch hex must start with #: \(hex)")
            }
        }
    }

    func testCodableRoundTrip() throws {
        for t in Theme.allCases {
            let data = try JSONEncoder().encode(t)
            let back = try JSONDecoder().decode(Theme.self, from: data)
            XCTAssertEqual(t, back)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ThemeTests`
Expected: FAIL — `cannot find 'Theme' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AignalsCore/Theme.swift
import Foundation

/// The four user-selectable visual themes for the dropdown + About window
/// (ADR-0808). Glass Light/Dark use a live system material; Terminal and
/// Vibrant are fixed palettes that deliberately do NOT follow the system
/// appearance. The enum is pure (no SwiftUI/AppKit) so it lives in
/// `AignalsCore` and is unit-tested; the App target maps each case to concrete
/// SwiftUI style values in `ThemeStyle.swift`.
public enum Theme: String, Codable, CaseIterable, Sendable {
    case glassLight
    case glassDark
    case terminal
    case vibrant

    /// Human-readable name shown in the picker.
    public var displayName: String {
        switch self {
        case .glassLight: return "Glass Light"
        case .glassDark:  return "Glass Dark"
        case .terminal:   return "Terminal"
        case .vibrant:    return "Vibrant"
        }
    }

    /// 1–3 hex colors previewing the theme in the picker's swatch. Pure data so
    /// it can be unit-tested and reused by the SwiftUI swatch view.
    public var swatchHexes: [String] {
        switch self {
        case .glassLight: return ["#F4F4F7", "#DCDCE4"]
        case .glassDark:  return ["#3A3A48", "#1E1E28"]
        case .terminal:   return ["#0C0F0A", "#143D1C"]
        case .vibrant:    return ["#FF453A", "#FFD60A", "#32D74B"]
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ThemeTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/Theme.swift Tests/AignalsCoreTests/ThemeTests.swift
git commit -m "feat(core): add Theme enum (Glass Light/Dark, Terminal, Vibrant)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 2: Persist `theme` in `AignalsConfig`

**Files:**
- Modify: `Sources/AignalsCore/ConfigStore.swift`
- Test: `Tests/AignalsCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `Theme` from Task 1.
- Produces: `AignalsConfig.theme: Theme` (default `.glassDark`); existing `init` gains a `theme: Theme = .glassDark` parameter; `decodeIfPresent` fallback to `.glassDark`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AignalsCoreTests/ConfigStoreTests.swift` (inside the class):

```swift
    func testThemeDefaultsToGlassDark() throws {
        let store = ConfigStore(paths: try tmpHome())
        XCTAssertEqual(store.config.theme, .glassDark)
    }

    func testThemeRoundtrip() throws {
        let paths = try tmpHome()
        let store = ConfigStore(paths: paths)
        var c = store.config
        c.theme = .terminal
        store.save(c)

        let reload = ConfigStore(paths: paths)
        XCTAssertEqual(reload.config.theme, .terminal)
    }

    func testThemeDecodesGlassDarkWhenAbsent() throws {
        let paths = try tmpHome()
        // Legacy config.json without `theme` must decode to Glass Dark.
        try Data(#"{"launchAtLogin":false,"dismissedInstallPrompt":false,"soundEnabled":true}"#.utf8)
            .write(to: paths.configFile)
        let store = ConfigStore(paths: paths)
        XCTAssertEqual(store.config.theme, .glassDark)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL — `value of type 'AignalsConfig' has no member 'theme'`.

- [ ] **Step 3: Modify `AignalsConfig`**

In `Sources/AignalsCore/ConfigStore.swift`, edit the struct to add the field, init param, default, coding key, and decode line (mirroring `soundEnabled`):

```swift
public struct AignalsConfig: Equatable, Codable, Sendable {
    public var launchAtLogin: Bool
    public var dismissedInstallPrompt: Bool
    /// Global sound toggle (ADR-20). Decodes to `true` when the key is absent so
    /// existing config.json files keep sound on after upgrade.
    public var soundEnabled: Bool
    /// Selected visual theme (ADR-0810). Decodes to `.glassDark` when the key is
    /// absent so existing config.json files land on the default after upgrade.
    public var theme: Theme

    public init(launchAtLogin: Bool, dismissedInstallPrompt: Bool, soundEnabled: Bool = true, theme: Theme = .glassDark) {
        self.launchAtLogin = launchAtLogin
        self.dismissedInstallPrompt = dismissedInstallPrompt
        self.soundEnabled = soundEnabled
        self.theme = theme
    }

    public static let `default` = AignalsConfig(launchAtLogin: false, dismissedInstallPrompt: false, soundEnabled: true, theme: .glassDark)

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case dismissedInstallPrompt
        case soundEnabled
        case theme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        self.dismissedInstallPrompt = try container.decode(Bool.self, forKey: .dismissedInstallPrompt)
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .glassDark
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS (existing + 3 new).

- [ ] **Step 5: Run the full Core suite (no regressions)**

Run: `swift test`
Expected: all green (60 prior + new Theme/Config tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/AignalsCore/ConfigStore.swift Tests/AignalsCoreTests/ConfigStoreTests.swift
git commit -m "feat(core): persist selected theme in AignalsConfig (default glassDark)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 3: `ThemeStyle` — SwiftUI style tokens + glass material

**Files:**
- Create: `App/Aignals/Sources/ThemeStyle.swift`

**Interfaces:**
- Consumes: `Theme` from Task 1.
- Produces:
  - `struct ThemeStyle` with: `static func tokens(for: Theme) -> ThemeStyle`; properties `panelBackground: AnyView`, `textPrimary: Color`, `textSecondary: Color`, `rowCorner: CGFloat`, `usesMonospaced: Bool`, `rowTint: (SessionState) -> Color?` (non-nil only for `.vibrant`), `hairline: Color`, `dotGlow: Bool`.
  - `struct VisualEffectBackground: NSViewRepresentable` wrapping `NSVisualEffectView` with a `material` + `appearance` (used by glass themes).
  - `Color(hex:)` initializer (from a `#RRGGBB` string) reused by swatches.
  - `EnvironmentValues.theme` / a `themeStyle` value injected so child views read it.

> This is presentation glue with no pure-logic branch a fresh reviewer would reject independently of its use; it has no SPM test. It is verified by the build in Task 7 and the manual smoke in Task 8. Keep it small and declarative.

- [ ] **Step 1: Implement `ThemeStyle.swift`**

```swift
// App/Aignals/Sources/ThemeStyle.swift
import SwiftUI
import AppKit
import AignalsCore

/// Concrete SwiftUI style values for a `Theme` (ADR-0808). The pure `Theme`
/// enum lives in AignalsCore; this maps each case to colors/fonts/materials the
/// views actually render. Verified by build + manual smoke (no UI-test harness).
struct ThemeStyle {
    var panelMaterial: NSVisualEffectView.Material?   // non-nil → glass; nil → fixed color
    var panelAppearance: NSAppearance.Name?           // glass appearance (aqua / darkAqua)
    var panelColor: Color                             // fixed fill for non-glass (Terminal/Vibrant)
    var textPrimary: Color
    var textSecondary: Color
    var hairline: Color
    var rowCorner: CGFloat
    var usesMonospaced: Bool
    var dotGlow: Bool
    var rowPrefix: String?                            // e.g. "›" for terminal
    var rowTint: (SessionState) -> Color?             // non-nil only for vibrant

    static func tokens(for theme: Theme) -> ThemeStyle {
        switch theme {
        case .glassLight:
            return ThemeStyle(
                panelMaterial: .popover, panelAppearance: .aqua,
                panelColor: Color(hex: "#FAFAFC"),
                textPrimary: .primary, textSecondary: .secondary,
                hairline: Color.black.opacity(0.08), rowCorner: 10,
                usesMonospaced: false, dotGlow: true, rowPrefix: nil,
                rowTint: { _ in nil })
        case .glassDark:
            return ThemeStyle(
                panelMaterial: .popover, panelAppearance: .darkAqua,
                panelColor: Color(hex: "#1C1C24"),
                textPrimary: .primary, textSecondary: .secondary,
                hairline: Color.white.opacity(0.10), rowCorner: 10,
                usesMonospaced: false, dotGlow: true, rowPrefix: nil,
                rowTint: { _ in nil })
        case .terminal:
            return ThemeStyle(
                panelMaterial: nil, panelAppearance: .darkAqua,
                panelColor: Color(hex: "#0C0F0A"),
                textPrimary: Color(hex: "#D8FFE0"), textSecondary: Color(hex: "#5AA86A"),
                hairline: Color(hex: "#1D3B22"), rowCorner: 6,
                usesMonospaced: true, dotGlow: false, rowPrefix: "›",
                rowTint: { _ in nil })
        case .vibrant:
            return ThemeStyle(
                panelMaterial: nil, panelAppearance: .darkAqua,
                panelColor: Color(hex: "#16121F"),
                textPrimary: .white, textSecondary: Color.white.opacity(0.6),
                hairline: Color.white.opacity(0.08), rowCorner: 10,
                usesMonospaced: false, dotGlow: true, rowPrefix: nil,
                rowTint: { state in
                    switch state {
                    case .working:           return Color(hex: "#FF453A")
                    case .waitingPermission: return Color(hex: "#FFD60A")
                    case .waitingInput:      return Color(hex: "#32D74B")
                    case .disconnected:      return nil
                    }
                })
        }
    }
}

/// `NSVisualEffectView` wrapper for the glass themes. Applies the theme's
/// material + appearance so the panel blurs the desktop behind it.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearance: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        if let appearance { v.appearance = NSAppearance(named: appearance) }
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        if let appearance { v.appearance = NSAppearance(named: appearance) }
    }
}

extension Color {
    /// `#RRGGBB` → Color. Falls back to clear on a malformed string.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&rgb) else {
            self = .clear; return
        }
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Inject the current `ThemeStyle` down the view tree.
private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.tokens(for: .glassDark)
}
extension EnvironmentValues {
    var themeStyle: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Commit** (build verified in Task 7 with the rest of the UI wiring)

```bash
git add App/Aignals/Sources/ThemeStyle.swift
git commit -m "feat(ui): add ThemeStyle tokens + NSVisualEffectView glass background

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 4: `AppViewModel.theme` get/set

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

**Interfaces:**
- Consumes: `config` get/set (already bumps `configVersion`), `Theme`.
- Produces: `var theme: Theme { get set }` on `AppViewModel`.

- [ ] **Step 1: Add the property**

In `App/Aignals/Sources/AppViewModel.swift`, in the same extension that defines `soundEnabled` (the `config`-backed one), add:

```swift
    /// Selected theme (ADR-0810). Reads/writes `AignalsConfig.theme` through the
    /// existing config setter, which bumps `configVersion` so SwiftUI re-derives
    /// the themed UI immediately.
    var theme: Theme {
        get { config.theme }
        set { var c = config; c.theme = newValue; config = c }
    }
```

- [ ] **Step 2: Build the Core to sanity-check the symbol resolves**

Run: `swift build`
Expected: `Build complete` (AignalsCore compiles; this property only references existing symbols + `Theme`).

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(ui): expose AppViewModel.theme bound to config.theme

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 5: `ThemePicker` side pop-out card

**Files:**
- Create: `App/Aignals/Sources/ThemePicker.swift`

**Interfaces:**
- Consumes: `Theme` (`allCases`, `displayName`, `swatchHexes`), `Color(hex:)` (Task 3), `AppViewModel.theme` (Task 4).
- Produces: `struct ThemePicker: View { @Bindable var vm: AppViewModel }` — the card body listing 4 swatch rows; and `struct ThemeSwatch: View` rendering the mini preview from `swatchHexes`.

- [ ] **Step 1: Implement `ThemePicker.swift`**

```swift
// App/Aignals/Sources/ThemePicker.swift
import SwiftUI
import AignalsCore

/// The side pop-out theme card (ADR-0809): one row per theme with a live
/// swatch + name + a ✓ on the active one. Presented from MenuContent via a
/// `.popover` so macOS auto-picks the side and it never clips off-screen.
/// Selecting applies instantly (writes `vm.theme`) and the card STAYS OPEN so
/// the user can compare themes back-to-back.
@MainActor
struct ThemePicker: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Theme")
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)

            ForEach(Theme.allCases, id: \.self) { theme in
                Button {
                    vm.theme = theme            // applies instantly; card stays open
                } label: {
                    HStack(spacing: 10) {
                        ThemeSwatch(hexes: theme.swatchHexes)
                        Text(theme.displayName)
                            .font(.callout)
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                            .opacity(vm.theme == theme ? 1 : 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(vm.theme == theme ? 0.10 : 0))
                )
            }
        }
        .padding(6)
        .frame(width: 208)
    }
}

/// A small rounded preview of a theme's palette: a horizontal gradient of its
/// `swatchHexes`.
struct ThemeSwatch: View {
    let hexes: [String]
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(
                colors: hexes.map { Color(hex: $0) },
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 26, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.18)))
    }
}
```

- [ ] **Step 2: Commit** (build verified in Task 7)

```bash
git add App/Aignals/Sources/ThemePicker.swift
git commit -m "feat(ui): add ThemePicker side pop-out card with swatch rows

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 6: Apply themes in `MenuContent` + add the Theme row

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `vm.theme`, `ThemeStyle.tokens(for:)`, `VisualEffectBackground`, `ThemePicker`, `SessionRow` (existing).
- Produces: a themed `MenuContent` whose root applies the panel background + injects `themeStyle` into the environment; a brand header; a "🎨 Theme ▸" Settings row that toggles a `.popover(isPresented:)` showing `ThemePicker(vm:)`.

This task does the bulk of the visual redesign. Implement in this order, building after each cohesive chunk so a failure is localized.

- [ ] **Step 1: Compute the style + apply the panel background**

At the top of `MenuContent.body`, derive the style and wrap the root `VStack` so the whole panel gets the themed background and the environment value. Replace the current `.frame(width: 320)` block's container with:

```swift
    private var style: ThemeStyle { ThemeStyle.tokens(for: vm.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(style.hairline)

            if vm.store.hasError {
                errorBanner
                Divider().background(style.hairline)
            }

            sessionList
            Divider().background(style.hairline)
            actions
        }
        .frame(width: 320)
        .environment(\.themeStyle, style)
        .foregroundStyle(style.textPrimary)
        .background(panelBackground)
        .onReceive(timer) { tick = $0 }
        .onAppear { FirstLaunchPrompt.maybeShow(viewModel: vm) }
    }

    /// Glass themes blur the desktop via NSVisualEffectView; fixed themes use a
    /// flat fill.
    @ViewBuilder
    private var panelBackground: some View {
        if let material = style.panelMaterial {
            VisualEffectBackground(material: material, appearance: style.panelAppearance)
        } else {
            style.panelColor
        }
    }
```

- [ ] **Step 2: Add the brand header**

Add a `header` view (logo + AIGNALS wordmark + status count chips):

```swift
    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(AngularGradient(colors: [.red, .yellow, .green, .red], center: .center))
                .frame(width: 18, height: 18)
            Text("AIGNALS").font(.system(size: 12, weight: .bold)).kerning(0.5)
            Spacer()
            countChips
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private var countChips: some View {
        let c = vm.store.statusCounts
        return HStack(spacing: 6) {
            chip(.red, c.working)
            chip(.yellow, c.waitingPermission)
            chip(.green, c.waitingInput)
        }
    }

    private func chip(_ color: Color, _ n: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: style.dotGlow ? color : .clear, radius: 3)
            Text("\(n)").font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.10)))
    }
```

> NOTE: `vm.store.statusCounts` exposes `working`, `waitingPermission`, `waitingInput` Int counts (see `Sources/AignalsCore/StatusCounts.swift`). If a property name differs, read that file and use the actual names — do not invent.

- [ ] **Step 3: Theme the session rows (dot glow, tint, mono, prefix)**

In `SessionRow.body`, read the injected style and apply it. Add at the top of `SessionRow`:

```swift
    @Environment(\.themeStyle) private var style
```

Change the status `Circle` to add a glow, the row container to add the vibrant tint + corner, and the title/subtitle fonts to honor monospacing. Replace the dot + row background treatment:

```swift
            Circle()
                .fill(Self.dotColor(for: session.state))
                .frame(width: 9, height: 9)
                .shadow(color: style.dotGlow ? Self.dotColor(for: session.state) : .clear, radius: 4)
                .padding(.top, 4)
```

Wrap the whole `HStack` content of the row with a themed card background:

```swift
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: style.rowCorner)
                .fill(style.rowTint(session.state)?.opacity(0.14) ?? .clear)
        )
```

Apply monospacing + secondary color to the subtitle:

```swift
                Text(subtitle)
                    .font(style.usesMonospaced ? .system(.caption, design: .monospaced) : .caption)
                    .foregroundStyle(style.textSecondary)
                    .lineLimit(1)
```

And the name field uses monospaced when the theme asks:

```swift
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(style.usesMonospaced ? .system(.body, design: .monospaced) : .body)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
```

- [ ] **Step 4: Add the "Theme" row + popover to the Settings fold**

Add picker presentation state near the other `@State` in `MenuContent`:

```swift
    @State private var themePopoverShown = false
```

In `settingsItems`, as the FIRST item inside the fold (above "Install Claude Code Hooks…"), add:

```swift
        Button { themePopoverShown.toggle() } label: {
            HStack {
                Text("🎨 Theme")
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popover(isPresented: $themePopoverShown, arrowEdge: .trailing) {
            ThemePicker(vm: vm)
        }
```

(`arrowEdge: .trailing` is a hint; SwiftUI flips it when space is tight — satisfying the "auto side" decision. The popover stays open until dismissed, satisfying "stays open".)

- [ ] **Step 5: Regenerate the project and build the app**

Run:
```bash
(cd App/Aignals && xcodegen generate)
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build
```
Expected: `** BUILD SUCCEEDED **`.

If the build fails on a `statusCounts` property name or any symbol, read the cited source file and fix the reference to the real name. Re-run until green.

- [ ] **Step 6: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift App/Aignals/project.yml
git commit -m "feat(ui): theme the dropdown (header, glowing dots, tinted rows) + Theme picker row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 7: Theme the About window + verify whole-app build

**Files:**
- Modify: `App/Aignals/Sources/AboutView.swift`

**Interfaces:**
- Consumes: `ThemeStyle`, `vm.theme` — BUT `AboutView` currently takes no view model. Keep it self-contained by reading the persisted theme directly via a fresh `ConfigStore` (the About window is a separate `Window` scene without the shared `vm`). Produces: a themed About window.

- [ ] **Step 1: Restyle `AboutView`**

```swift
// App/Aignals/Sources/AboutView.swift
import SwiftUI
import AignalsCore

/// About window content (ADR-0802). Themed per the persisted selection
/// (ADR-0808/0810): the About window is its own Window scene without the shared
/// AppViewModel, so it reads the theme directly from a fresh ConfigStore.
struct AboutView: View {
    private let style: ThemeStyle = {
        let paths = Paths()
        let theme = ConfigStore(paths: paths).config.theme
        return ThemeStyle.tokens(for: theme)
    }()

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(AngularGradient(colors: [.red, .yellow, .green, .red], center: .center))
                .frame(width: 56, height: 56)
            Text("Aignals").font(.title2).bold()
            Text("Version \(version)").foregroundStyle(style.textSecondary)
            Text("Menu bar signal light for your AI coding agents.")
                .font(.callout).foregroundStyle(style.textSecondary)
                .multilineTextAlignment(.center)
            Link("github.com/Jesse1211/Aignals",
                 destination: URL(string: "https://github.com/Jesse1211/Aignals")!)
        }
        .padding(28)
        .frame(width: 320)
        .foregroundStyle(style.textPrimary)
        .background(aboutBackground)
    }

    @ViewBuilder
    private var aboutBackground: some View {
        if let material = style.panelMaterial {
            VisualEffectBackground(material: material, appearance: style.panelAppearance)
        } else {
            style.panelColor
        }
    }
}
```

- [ ] **Step 2: Regenerate + build the whole app**

Run:
```bash
(cd App/Aignals && xcodegen generate)
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full Core test suite (no regressions)**

Run: `swift test`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/AboutView.swift
git commit -m "feat(ui): theme the About window

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git status --short
```

---

## Task 8: Manual smoke test (human-verifiable; no automated UI harness)

**Files:** none (verification only).

This is the acceptance gate for the visual work. Run the built app and confirm each item. Record pass/fail in the task report.

- [ ] **Step 1: Build + launch**

```bash
(cd App/Aignals && xcodegen generate)
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug -derivedDataPath App/Aignals/DerivedData build
open App/Aignals/DerivedData/Build/Products/Debug/Aignals.app
```

- [ ] **Step 2: Verify each acceptance item**

1. Dropdown opens with the brand header (logo + AIGNALS + count chips) and starts on **Glass Dark**.
2. Settings ▸ expands; the first item is **🎨 Theme ▸**.
3. Clicking Theme pops out a side card with **4 rows** (Glass Light, Glass Dark, Terminal, Vibrant), each with a swatch; the active one shows a ✓.
4. Selecting each theme **re-styles the whole panel instantly**: Glass Light/Dark blur the desktop; Terminal is monospaced phosphor-green with `›` prefixes; Vibrant tints rows by state color. Status dots glow on all but Terminal.
5. The picker **stays open** after selecting; clicking elsewhere dismisses it.
6. Open **About Aignals…** — it renders in the selected theme.
7. **Quit and relaunch** — the chosen theme persisted (verify `~/.aignals/config.json` contains the `theme` key).
8. Simulate a legacy config: quit, edit `~/.aignals/config.json` to remove the `"theme"` key, relaunch → app lands on **Glass Dark** (no crash).
9. Existing behaviors unaffected: rename a session, drag-reorder, pin, toggle mute, gray-remove, error banner (e.g. `chmod 000 ~/.aignals/sessions` then restore).

- [ ] **Step 3: Report** the pass/fail matrix. Any fail → STOP and fix the responsible task before declaring done.

---

## Self-Review

**Spec coverage:**
- §2 four themes + default → Task 1 (enum) + Task 2 (default persistence). ✅
- §3 layout (header, card rows, glow, empty, error, footer) → Task 6. ✅
- §4 theme picker pop-out (swatch rows, ✓, auto side, stays open, instant) → Task 5 + Task 6 Step 4. ✅
- §5 persistence (`theme` field, backward-compatible decode, existing ConfigStore, `AppViewModel.theme`) → Task 2 + Task 4. ✅
- §6 components/boundaries → file structure table maps 1:1. ✅
- §7 verification (SPM unit gates + build + manual smoke) → Tasks 1/2 (unit), 6/7 (build), 8 (smoke). ✅
- About window restyle (in scope) → Task 7. ✅

**Placeholder scan:** No TBD/TODO; all code blocks complete. The one "read the file if the property name differs" note (Task 6 Step 2) points at the exact source file rather than guessing — acceptable guidance, not a placeholder.

**Type consistency:** `Theme` cases/`displayName`/`swatchHexes` consistent across Tasks 1/3/5. `ThemeStyle` property names consistent across Tasks 3/6/7. `vm.theme` consistent across Tasks 4/5/6. `Color(hex:)` defined in Task 3, used in 3/5. `VisualEffectBackground` defined in 3, used in 6/7.

**Known verification caveat (carried from prior phases):** the picker popover + theme persistence have no automated UI test (XCTest can't drive a MenuBarExtra popover) — Task 8 manual smoke is the gate, consistent with the Phase-8/9/10 convention.

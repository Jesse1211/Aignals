# Phase 10 — Launch at Login + Config

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Toggle login-launch behaviour with `SMAppService` and persist user preferences to `~/.aignals/config.json`.

**Depends on:** Phase 8.

**Spec sections:** §10 (launch at login row), §7 (config.json fields).

---

### Task 10.1: `ConfigStore`

**Files:**
- Create: `Sources/AignalsCore/ConfigStore.swift`
- Create: `Tests/AignalsCoreTests/ConfigStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import AignalsCore

final class ConfigStoreTests: XCTestCase {
    private func tmpHome() throws -> Paths {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aignals-config-\(UUID().uuidString)")
        let paths = Paths(environment: ["AIGNALS_HOME": dir.path])
        try paths.ensureDirectories()
        return paths
    }

    func testDefaultsWhenFileMissing() throws {
        let store = ConfigStore(paths: try tmpHome())
        XCTAssertEqual(store.config, .default)
    }

    func testRoundtrip() throws {
        let paths = try tmpHome()
        let store = ConfigStore(paths: paths)
        var c = store.config
        c.launchAtLogin = true
        c.dismissedInstallPrompt = true
        store.save(c)

        let reload = ConfigStore(paths: paths)
        XCTAssertEqual(reload.config.launchAtLogin, true)
        XCTAssertEqual(reload.config.dismissedInstallPrompt, true)
    }

    func testMalformedFileFallsBackToDefaults() throws {
        let paths = try tmpHome()
        try Data("not json".utf8).write(to: paths.configFile)
        let store = ConfigStore(paths: paths)
        XCTAssertEqual(store.config, .default)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public struct AignalsConfig: Equatable, Codable, Sendable {
    public var launchAtLogin: Bool
    public var dismissedInstallPrompt: Bool

    public static let `default` = AignalsConfig(launchAtLogin: false, dismissedInstallPrompt: false)
}

public final class ConfigStore {
    private let paths: Paths
    public private(set) var config: AignalsConfig

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.configFile),
           let decoded = try? JSONDecoder().decode(AignalsConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    public func save(_ next: AignalsConfig) {
        config = next
        try? paths.ensureDirectories()
        let tmp = paths.configFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? JSONEncoder().encode(next) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.configFile, withItemAt: tmp)
        }
    }
}
```

- [ ] **Step 3: Run + commit**

```bash
swift test --filter ConfigStoreTests
git add Sources/AignalsCore/ConfigStore.swift Tests/AignalsCoreTests/ConfigStoreTests.swift
git commit -m "phase-10: add AignalsConfig + ConfigStore"
```

---

### Task 10.2: `LaunchAtLogin` SMAppService wrapper

**Files:**
- Create: `Sources/AignalsCore/LaunchAtLogin.swift`

Note: `SMAppService` requires a real signed app bundle for full functionality. In unit tests we only verify the wrapper returns the right state; the integration is verified manually (manual checklist).

- [ ] **Step 1: Write**

```swift
import Foundation
import ServiceManagement

public enum LaunchAtLogin {
    @available(macOS 13.0, *)
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @available(macOS 13.0, *)
    public static func set(_ enabled: Bool) throws {
        let svc = SMAppService.mainApp
        if enabled {
            if svc.status != .enabled { try svc.register() }
        } else {
            if svc.status == .enabled { try svc.unregister() }
        }
    }
}
```

- [ ] **Step 2: Commit (no automated tests; covered by manual checklist)**

```bash
git add Sources/AignalsCore/LaunchAtLogin.swift
git commit -m "phase-10: add LaunchAtLogin wrapper around SMAppService"
```

---

### Task 10.3: Wire toggle into menu

**Files:**
- Modify: `App/Aignals/UI/AppViewModel.swift`
- Modify: `App/Aignals/UI/MenuContent.swift`

- [ ] **Step 1: Extend view model**

```swift
extension AppViewModel {
    var config: AignalsConfig {
        get { configStore.config }
        set {
            configStore.save(newValue)
            try? LaunchAtLogin.set(newValue.launchAtLogin)
        }
    }
    var launchAtLogin: Bool {
        get { config.launchAtLogin }
        set { var c = config; c.launchAtLogin = newValue; config = c }
    }
}
```

Add `private let configStore: ConfigStore` to `AppViewModel.init`:

```swift
self.configStore = ConfigStore(paths: paths)
try? LaunchAtLogin.set(configStore.config.launchAtLogin) // re-apply on launch
```

- [ ] **Step 2: Replace placeholder Toggle in `MenuContent`**

```swift
Toggle("Launch at Login", isOn: Binding(
    get: { vm.launchAtLogin },
    set: { vm.launchAtLogin = $0 }
))
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals build
```

- [ ] **Step 4: Commit**

```bash
git add App/Aignals
git commit -m "phase-10: wire Launch at Login toggle through ConfigStore + SMAppService"
```

---

### Task 10.4: Migrate first-launch prompt to `ConfigStore`

**Files:**
- Modify: `App/Aignals/UI/FirstLaunchPrompt.swift`

- [ ] **Step 1: Update**

```swift
import AppKit
import AignalsCore

@MainActor
enum FirstLaunchPrompt {
    private static let legacyKey = "aignals.dismissedInstallPrompt"

    static func maybeShow(viewModel: AppViewModel) {
        // One-shot migration from the Phase 9 UserDefaults stopgap.
        if UserDefaults.standard.bool(forKey: legacyKey), !viewModel.config.dismissedInstallPrompt {
            var c = viewModel.config; c.dismissedInstallPrompt = true; viewModel.config = c
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        if viewModel.config.dismissedInstallPrompt { return }
        if viewModel.claudeHooksInstalled { return }

        let alert = NSAlert()
        alert.messageText = "Aignals needs hooks to light up"
        alert.informativeText = "Install Aignals hooks into ~/.claude/settings.json so the indicator can track Claude Code sessions?"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Later")
        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn {
            try? viewModel.installClaudeHooks()
        } else {
            var c = viewModel.config; c.dismissedInstallPrompt = true; viewModel.config = c
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals build
git add App/Aignals/UI/FirstLaunchPrompt.swift
git commit -m "phase-10: migrate first-launch prompt state from UserDefaults to ConfigStore"
```

---

### Acceptance for Phase 10

- `ConfigStoreTests` green.
- App builds.
- First-launch prompt persistence goes through `ConfigStore`, with a one-shot migration from the Phase 9 UserDefaults key.
- Manual: toggling "Launch at Login" persists across relaunches and survives a reboot (manual checklist item).

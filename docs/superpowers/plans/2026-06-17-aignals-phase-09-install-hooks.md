# Phase 09 — Hook Installer

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** A safe, idempotent merge of the Aignals hook snippet into `~/.claude/settings.json`, exposed as a menu item and as a first-launch prompt.

**Depends on:** Phase 8 (menu item placeholder exists).

**Spec sections:** §5 (settings.json snippet), §7 (first-launch prompt).

---

### Task 9.1: `HookInstaller` pure-Swift merge

**Files:**
- Create: `Sources/AignalsCore/HookInstaller.swift`
- Create: `Tests/AignalsCoreTests/HookInstallerTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import AignalsCore

final class HookInstallerTests: XCTestCase {
    private func tmpFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hi-\(UUID().uuidString).json")
    }

    func testMergeIntoEmptyFile() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        try installer.install(into: file)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["SessionStart"])
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertNotNil(hooks["Stop"])
        XCTAssertNotNil(hooks["SessionEnd"])
    }

    func testMergePreservesUnrelatedHooks() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "user-bash-watch"]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted)
            .write(to: file)

        let installer = HookInstaller()
        try installer.install(into: file)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let pretool = (json["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        // user's entry preserved
        XCTAssertTrue(pretool.contains { ($0["matcher"] as? String) == "Bash" })
        // aignals entry added
        XCTAssertTrue(pretool.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String) == "aignals-hook on-pretool" }
        })
    }

    func testInstallIsIdempotent() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        try installer.install(into: file)
        try installer.install(into: file)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let sessionStart = (json["hooks"] as! [String: Any])["SessionStart"] as! [[String: Any]]
        let count = sessionStart.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { ($0["command"] as? String) == "aignals-hook on-sessionstart" }
            .count
        XCTAssertEqual(count, 1)
    }

    func testDetectsExistingInstallation() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let installer = HookInstaller()
        XCTAssertFalse(installer.isInstalled(in: file))
        try installer.install(into: file)
        XCTAssertTrue(installer.isInstalled(in: file))
    }

    func testMalformedExistingFileThrows() throws {
        let file = tmpFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        let installer = HookInstaller()
        XCTAssertThrowsError(try installer.install(into: file))
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public struct HookInstaller {
    public enum InstallError: Error {
        case malformedSettingsJSON
    }

    public struct EventDef { let event: String; let command: String }
    public static let events: [EventDef] = [
        .init(event: "SessionStart", command: "aignals-hook on-sessionstart"),
        .init(event: "PreToolUse",   command: "aignals-hook on-pretool"),
        .init(event: "Stop",         command: "aignals-hook on-stop"),
        .init(event: "SessionEnd",   command: "aignals-hook on-sessionend"),
    ]

    public init() {}

    public func isInstalled(in file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return Self.events.allSatisfy { hasCommand($0.command, event: $0.event, root: root) }
    }

    public func install(into file: URL) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            if !data.isEmpty {
                guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    throw InstallError.malformedSettingsJSON
                }
                root = obj
            }
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for e in Self.events {
            hooks[e.event] = mergeEvent(eventArray: hooks[e.event] as? [[String: Any]] ?? [], command: e.command)
        }
        root["hooks"] = hooks

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let tmp = file.appendingPathExtension("tmp.\(UUID().uuidString)")
        let serialized = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try serialized.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }

    private func mergeEvent(eventArray: [[String: Any]], command: String) -> [[String: Any]] {
        // Already present?
        for entry in eventArray {
            if let inner = entry["hooks"] as? [[String: Any]],
               inner.contains(where: { ($0["command"] as? String) == command }) {
                return eventArray
            }
        }
        var out = eventArray
        out.append([
            "hooks": [
                ["type": "command", "command": command]
            ]
        ])
        return out
    }

    private func hasCommand(_ command: String, event: String, root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let arr = hooks[event] as? [[String: Any]] else { return false }
        return arr.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String) == command }
        }
    }
}
```

- [ ] **Step 3: Run tests + commit**

```bash
swift test --filter HookInstallerTests
git add Sources/AignalsCore/HookInstaller.swift Tests/AignalsCoreTests/HookInstallerTests.swift
git commit -m "phase-09: add HookInstaller (merge + isInstalled + idempotent)"
```

---

### Task 9.2: Flip the gate for Phase 7 case 13

**Files:**
- Modify: `Tests/AignalsE2ETests/InstallHooksE2ETests.swift`

- [ ] **Step 1: Replace the failing stub with a real test**

```swift
func test_case13_installHooksMergeIdempotent() throws {
    let file = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("settings-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let existing: [String: Any] = [
        "hooks": [
            "PreToolUse": [
                ["matcher": "Bash", "hooks": [["type": "command", "command": "user-bash-watch"]]]
            ]
        ]
    ]
    try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted).write(to: file)

    let installer = HookInstaller()
    try installer.install(into: file)
    try installer.install(into: file)  // idempotent

    XCTAssertTrue(installer.isInstalled(in: file))
    let data = try Data(contentsOf: file)
    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let pretool = (root["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
    XCTAssertTrue(pretool.contains { ($0["matcher"] as? String) == "Bash" })
}
```

Also remove the `XCTSkipUnless` gate now that the impl exists:

```swift
override func setUpWithError() throws {
    // gate removed: phase-09 implementation now exists
}
```

- [ ] **Step 2: Run**

```bash
swift test --filter InstallHooksE2ETests
```

Expected: case 13 passes. Case 14 still passes.

- [ ] **Step 3: Commit**

```bash
git add Tests/AignalsE2ETests/InstallHooksE2ETests.swift
git commit -m "phase-09: unskip case 13 (install merge) and verify"
```

---

### Task 9.3: Menu wiring + first-launch prompt

**Files:**
- Modify: `App/Aignals/UI/AppViewModel.swift`
- Modify: `App/Aignals/UI/MenuContent.swift`
- Create: `App/Aignals/UI/FirstLaunchPrompt.swift`

- [ ] **Step 1: Extend `AppViewModel`**

Add to the existing `AppViewModel`:

```swift
extension AppViewModel {
    var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    func installClaudeHooks() throws {
        try HookInstaller().install(into: claudeSettingsURL)
    }

    var claudeHooksInstalled: Bool {
        HookInstaller().isInstalled(in: claudeSettingsURL)
    }
}
```

- [ ] **Step 2: Wire "Install Claude Code Hooks…"**

In `MenuContent.swift`, replace the placeholder:

```swift
Button("Install Claude Code Hooks…") {
    do {
        try vm.installClaudeHooks()
        Self.alert("Hooks installed", informative: "Aignals will now light up when Claude Code is working.")
    } catch {
        Self.alert("Couldn't install hooks",
                   informative: "Edit ~/.claude/settings.json manually. Error: \(error)")
    }
}
```

Add helper to `MenuContent`:

```swift
private static func alert(_ title: String, informative: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = informative
    a.runModal()
}
```

- [ ] **Step 3: First-launch prompt**

Create `App/Aignals/UI/FirstLaunchPrompt.swift`. We use `UserDefaults` here as a stopgap; Phase 10 introduces `ConfigStore.dismissedInstallPrompt` and the prompt is migrated to read/write that field instead.

```swift
import AppKit
import AignalsCore

@MainActor
enum FirstLaunchPrompt {
    private static let defaultsKey = "aignals.dismissedInstallPrompt"

    static func maybeShow(viewModel: AppViewModel) {
        if UserDefaults.standard.bool(forKey: defaultsKey) { return }
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
            UserDefaults.standard.set(true, forKey: defaultsKey)
        }
    }
}
```

Trigger from `MenuContent.onAppear` — the most reliable hook with `@State` view models:

```swift
.onAppear { FirstLaunchPrompt.maybeShow(viewModel: vm) }
```

Note: `MenuBarExtra` body re-evaluates when the dropdown opens; the `UserDefaults` gate inside `FirstLaunchPrompt.maybeShow` ensures the alert fires at most once per machine.

- [ ] **Step 4: Build + smoke test**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build
```

Manual: launch app on a machine with a fresh `~/.claude/settings.json`. Verify prompt appears once, then never again.

- [ ] **Step 5: Commit**

```bash
git add App/Aignals
git commit -m "phase-09: menu item + first-launch prompt for hook install"
```

---

### Acceptance for Phase 9

- `HookInstallerTests` and `InstallHooksE2ETests` green.
- Menu item triggers the merge.
- First-launch prompt appears exactly once until either Install or Later is chosen.

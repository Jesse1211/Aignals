# Phase 08 — Menu Bar UI

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Wire the real menu bar icon (red/green/gray dot) and dropdown (session list, preferences, About) into `Aignals.app`.

**Depends on:** Phases 1–6 finished, `SessionStore` available.

**Spec sections:** §7 (UI detail).

---

### Task 8.1: `StatusIcon` image generator

**Files:**
- Create: `App/Aignals/UI/StatusIcon.swift`
- Create: `App/Aignals/Tests/StatusIconTests.swift` (under the Xcode target's unit-test bundle if one exists, otherwise add the file under `Sources/AignalsCore` since drawing logic is pure)

Decision: keep `StatusIcon` rendering in `AignalsCore` so SPM tests can verify pixel size + transparency. Wire into the app target via `AignalsCore`.

- [ ] **Step 1: Failing test**

Create `Tests/AignalsCoreTests/StatusIconTests.swift`:

```swift
import XCTest
import AppKit
@testable import AignalsCore

final class StatusIconTests: XCTestCase {
    func testEachStateProducesNonTemplate18ptImage() {
        for state in [AggregateStatus.idle, .running, .error] {
            let img = StatusIcon.image(for: state)
            XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
            XCTAssertFalse(img.isTemplate, "Status images must keep their own color")
        }
    }
}
```

- [ ] **Step 2: Implement**

Create `Sources/AignalsCore/StatusIcon.swift`:

```swift
import AppKit

public enum StatusIcon {
    public static func image(for status: AggregateStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let dotRect = NSRect(x: 4, y: 4, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: dotRect)
            switch status {
            case .running: NSColor.systemRed.setFill()
            case .idle:    NSColor.systemGreen.setFill()
            case .error:   NSColor.systemGray.setFill()
            }
            path.fill()

            if status == .error {
                // inner hollow ring to distinguish error from a generic gray dot
                NSColor.black.setStroke()
                let inner = NSBezierPath(ovalIn: dotRect.insetBy(dx: 2, dy: 2))
                inner.lineWidth = 1.5
                inner.stroke()
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}
```

- [ ] **Step 3: Run**

```bash
swift test --filter StatusIconTests
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/AignalsCore/StatusIcon.swift Tests/AignalsCoreTests/StatusIconTests.swift
git commit -m "phase-08: add StatusIcon image generator with 3-state rendering"
```

---

### Task 8.2: `ElapsedFormatter`

**Files:**
- Create: `Sources/AignalsCore/ElapsedFormatter.swift`
- Create: `Tests/AignalsCoreTests/ElapsedFormatterTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import AignalsCore

final class ElapsedFormatterTests: XCTestCase {
    func testSecondsUnder60() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 14), "14s")
    }
    func testMinutesUnder60() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 125), "2m")
    }
    func testHoursUnder24() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 3 * 3600 + 5), "3h")
    }
    func testDays() {
        XCTAssertEqual(ElapsedFormatter.format(seconds: 2 * 86_400 + 10), "2d")
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public enum ElapsedFormatter {
    public static func format(seconds: TimeInterval) -> String {
        let s = Int(seconds)
        switch s {
        case ..<60:           return "\(s)s"
        case ..<3600:         return "\(s / 60)m"
        case ..<86_400:       return "\(s / 3600)h"
        default:              return "\(s / 86_400)d"
        }
    }

    public static func format(from start: Date, to now: Date = Date()) -> String {
        format(seconds: now.timeIntervalSince(start))
    }
}
```

- [ ] **Step 3: Run + commit**

```bash
swift test --filter ElapsedFormatterTests
git add Sources/AignalsCore/ElapsedFormatter.swift Tests/AignalsCoreTests/ElapsedFormatterTests.swift
git commit -m "phase-08: add ElapsedFormatter"
```

---

### Task 8.3: Verb mapping helper

**Files:**
- Create: `Sources/AignalsCore/VerbMapper.swift`
- Create: `Tests/AignalsCoreTests/VerbMapperTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import AignalsCore

final class VerbMapperTests: XCTestCase {
    func testKnownTools() {
        XCTAssertEqual(VerbMapper.verb(forTool: "Edit"), "Editing")
        XCTAssertEqual(VerbMapper.verb(forTool: "Write"), "Editing")
        XCTAssertEqual(VerbMapper.verb(forTool: "Bash"), "Running")
        XCTAssertEqual(VerbMapper.verb(forTool: "Read"), "Reading")
        XCTAssertEqual(VerbMapper.verb(forTool: "Glob"), "Searching")
        XCTAssertEqual(VerbMapper.verb(forTool: "Grep"), "Searching")
    }
    func testUnknownToolTitleCased() {
        XCTAssertEqual(VerbMapper.verb(forTool: "myTool"), "Mytool")
        XCTAssertEqual(VerbMapper.verb(forTool: "ABC"), "Abc")
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public enum VerbMapper {
    public static func verb(forTool tool: String) -> String {
        switch tool {
        case "Edit", "Write": return "Editing"
        case "Bash":          return "Running"
        case "Read":          return "Reading"
        case "Glob", "Grep":  return "Searching"
        default:
            guard let first = tool.first else { return "" }
            return String(first).uppercased() + tool.dropFirst().lowercased()
        }
    }
}
```

- [ ] **Step 3: Run + commit**

```bash
swift test --filter VerbMapperTests
git add Sources/AignalsCore/VerbMapper.swift Tests/AignalsCoreTests/VerbMapperTests.swift
git commit -m "phase-08: add VerbMapper (tool name → display verb)"
```

---

### Task 8.4: `AppViewModel` wiring

**Files:**
- Create: `App/Aignals/UI/AppViewModel.swift`

- [ ] **Step 1: Write**

```swift
import Foundation
import AppKit
import AignalsCore

@MainActor
@Observable
final class AppViewModel {
    let paths: Paths
    let store: SessionStore
    private let watcher: FSEventsWatcher
    private let sweeper: PIDSweeper

    init() {
        self.paths = Paths()
        try? paths.ensureDirectories()
        self.store = SessionStore()
        self.watcher = FSEventsWatcher(directory: paths.sessionsDirectory, store: store)
        self.sweeper = PIDSweeper(sessionsDirectory: paths.sessionsDirectory, store: store)
        watcher.start()
        sweeper.start()
        seedInitialState()
    }

    private func seedInitialState() {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: paths.sessionsDirectory.path) else {
            return
        }
        for name in entries where name.hasSuffix(".json") {
            store.loadFromDisk(path: paths.sessionsDirectory.appendingPathComponent(name))
        }
    }

    func revealAignalsHome() {
        NSWorkspace.shared.open(paths.home)
    }
}
```

---

### Task 8.5: `MenuContent` view

**Files:**
- Create: `App/Aignals/UI/MenuContent.swift`

- [ ] **Step 1: Write**

```swift
import SwiftUI
import AignalsCore

struct MenuContent: View {
    @Bindable var vm: AppViewModel
    @State private var tick = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if vm.store.aggregateStatus == .error {
                Label("Cannot read ~/.aignals", systemImage: "exclamationmark.triangle")
                Button("Reveal in Finder") { vm.revealAignalsHome() }
                Divider()
            }

            if vm.store.sessions.isEmpty {
                Text("No active sessions").foregroundStyle(.secondary)
            } else {
                Text("Active Sessions").font(.caption).foregroundStyle(.secondary)
                ForEach(vm.store.sessions, id: \.sessionID) { session in
                    sessionRow(session)
                }
            }

            Divider()
            Button("Install Claude Code Hooks…") { /* phase-09 */ }
            Button("Open ~/.aignals") { vm.revealAignalsHome() }
            Divider()
            Button("Quit Aignals") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onReceive(timer) { tick = $0 }
    }

    @ViewBuilder
    private func sessionRow(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text(s.projectName).font(.body)
            }
            Text(subtitle(for: s)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func subtitle(for s: Session) -> String {
        let elapsed = ElapsedFormatter.format(from: s.startedAt, to: tick)
        if let a = s.currentAction {
            let verb = VerbMapper.verb(forTool: a.tool)
            let target = a.target.isEmpty ? "" : " \(a.target)"
            return "\(verb)\(target) · \(elapsed)"
        } else {
            return "Active · \(elapsed)"
        }
    }
}
```

---

### Task 8.6: Wire `AignalsApp` to real view model

**Files:**
- Modify: `App/Aignals/AignalsApp.swift`

- [ ] **Step 1: Replace placeholder**

```swift
import SwiftUI
import AignalsCore

@main
struct AignalsApp: App {
    @State private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(vm: vm)
        } label: {
            Image(nsImage: StatusIcon.image(for: vm.store.aggregateStatus))
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 2: Build the app**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke test**

```bash
# in repo root
swift run --package-path . 2>/dev/null   # SPM has no app target; instead open & run from Xcode:
open App/Aignals/Aignals.xcodeproj
# Then ⌘R. Confirm green dot in menu bar. Then:
mkdir -p ~/.aignals/sessions
echo '{"schema_version":1,"session_id":"m1","tool":"claude-code","project_name":"manual","started_at":"2026-06-17T10:00:00Z"}' > ~/.aignals/sessions/m1.json
# → dot should turn red within ~1s
rm ~/.aignals/sessions/m1.json
# → dot back to green
```

- [ ] **Step 4: Commit**

```bash
git add App/Aignals
git commit -m "phase-08: wire MenuBarExtra to AppViewModel + StatusIcon"
```

---

### Task 8.7: About window

**Files:**
- Create: `App/Aignals/UI/AboutView.swift`
- Modify: `App/Aignals/AignalsApp.swift`
- Modify: `App/Aignals/UI/MenuContent.swift`

- [ ] **Step 1: Write AboutView**

```swift
import SwiftUI

struct AboutView: View {
    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aignals").font(.title2).bold()
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Menu bar indicator for AI coding agent activity.")
            Link("github.com/YOUR-USERNAME/Aignals",
                 destination: URL(string: "https://github.com/YOUR-USERNAME/Aignals")!)
        }
        .padding(24)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Add a `Window` scene in `AignalsApp` and bind it via a notification**

Modify `AignalsApp.swift`:

```swift
import SwiftUI
import AignalsCore

@main
struct AignalsApp: App {
    @State private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(vm: vm)
        } label: {
            Image(nsImage: StatusIcon.image(for: vm.store.aggregateStatus))
        }
        .menuBarExtraStyle(.menu)

        Window("About Aignals", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 3: Add "About Aignals…" button to `MenuContent`**

```swift
@Environment(\.openWindow) private var openWindow
// ...
Button("About Aignals…") { openWindow(id: "about") }
```

- [ ] **Step 4: Build + commit**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals build
git add App/Aignals
git commit -m "phase-08: add About window + menu item"
```

---

### Task 8.8: Manual-test checklist

**Files:**
- Create: `docs/superpowers/specs/manual-test-checklist.md`

- [ ] **Step 1: Write**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/manual-test-checklist.md
git commit -m "phase-08: add manual test checklist"
```

---

### Acceptance for Phase 8

- All new unit tests green (`StatusIconTests`, `ElapsedFormatterTests`, `VerbMapperTests`).
- `xcodebuild` builds the app.
- Manual smoke test (Step 8.6.3) works end-to-end.

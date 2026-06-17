# Phase 00 — Repo Scaffolding

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Set up the directory layout, Swift Package Manager workspace, Xcode app target, and CI skeleton so every later phase has a place to put files and a way to verify them.

**Why first:** All later phases create Swift source / tests; without an SPM + Xcode setup, none of them can build or run.

**Spec sections:** §10 (build/package tooling references).

---

### Task 0.1: Verify toolchain

**Files:** none

- [ ] **Step 1: Confirm Xcode, swift, and bats are present**

```bash
xcodebuild -version
swift --version
bats --version || brew install bats-core
jq --version || brew install jq
```

Expected: Xcode ≥ 15, swift 5.9+, bats present (install if missing), jq present (install if missing).

- [ ] **Step 2: Note macOS version**

```bash
sw_vers -productVersion
```

Expected: 13.0 or higher. If lower, stop and surface.

---

### Task 0.2: Top-level directory layout

**Files:**
- Create: `Package.swift`
- Create: `Sources/AignalsCore/.gitkeep`
- Create: `Tests/AignalsCoreTests/.gitkeep`
- Create: `Tests/AignalsE2ETests/.gitkeep`
- Create: `App/Aignals/.gitkeep`
- Create: `CLI/aignals-hook/.gitkeep`
- Create: `Tests/HookTests/.gitkeep`
- Create: `.gitignore`

- [ ] **Step 1: Create directories**

```bash
mkdir -p Sources/AignalsCore Tests/AignalsCoreTests Tests/AignalsE2ETests Tests/HookTests App/Aignals CLI/aignals-hook
touch Sources/AignalsCore/.gitkeep Tests/AignalsCoreTests/.gitkeep Tests/AignalsE2ETests/.gitkeep Tests/HookTests/.gitkeep App/Aignals/.gitkeep CLI/aignals-hook/.gitkeep
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
.build/
.swiftpm/
DerivedData/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
xcuserdata/
build/
dist/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore Sources Tests App CLI
git commit -m "phase-00: scaffold directory layout"
```

---

### Task 0.3: SPM package manifest

**Files:**
- Create: `Package.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aignals",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AignalsCore", targets: ["AignalsCore"]),
    ],
    targets: [
        .target(
            name: "AignalsCore",
            path: "Sources/AignalsCore"
        ),
        .testTarget(
            name: "AignalsCoreTests",
            dependencies: ["AignalsCore"],
            path: "Tests/AignalsCoreTests"
        ),
        .testTarget(
            name: "AignalsE2ETests",
            dependencies: ["AignalsCore"],
            path: "Tests/AignalsE2ETests",
            resources: [.copy("Resources")]
        ),
    ]
)
```

- [ ] **Step 2: Drop a placeholder Swift file in each target so SPM doesn't error on empty target**

Create `Sources/AignalsCore/Placeholder.swift`:

```swift
// Removed in Phase 01 when Paths.swift lands.
@_documentation(visibility: internal)
public enum _AignalsCorePlaceholder {}
```

Create `Tests/AignalsCoreTests/PlaceholderTests.swift`:

```swift
import XCTest
@testable import AignalsCore

final class PlaceholderTests: XCTestCase {
    func testPlaceholderCompiles() {
        _ = _AignalsCorePlaceholder.self
    }
}
```

Create `Tests/AignalsE2ETests/PlaceholderE2ETests.swift`:

```swift
import XCTest

final class PlaceholderE2ETests: XCTestCase {
    func testPlaceholderCompiles() {
        XCTAssertTrue(true)
    }
}
```

Create the E2E resources dir so SPM is happy:

```bash
mkdir -p Tests/AignalsE2ETests/Resources
touch Tests/AignalsE2ETests/Resources/.gitkeep
```

- [ ] **Step 3: Verify build + test**

```bash
swift build
swift test
```

Expected: build OK, two placeholder tests pass.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "phase-00: add SPM manifest with library + test targets"
```

---

### Task 0.4: Xcode app target

**Files:**
- Create: `App/Aignals/Aignals.xcodeproj` (via Xcode)
- Create: `App/Aignals/AignalsApp.swift`
- Create: `App/Aignals/Info.plist`

- [ ] **Step 1: Create the Xcode project manually**

In Xcode: File → New → Project → macOS → App.
Settings:
- Product Name: `Aignals`
- Team: none (self-signed)
- Bundle ID: `com.aignals.Aignals`
- Interface: SwiftUI
- Language: Swift
- Use Core Data: off
- Include Tests: off (we use SPM for tests)

Save into `App/Aignals/`.

- [ ] **Step 2: Replace the generated `AignalsApp.swift` content**

```swift
import SwiftUI

@main
struct AignalsApp: App {
    var body: some Scene {
        MenuBarExtra("Aignals", systemImage: "circle.fill") {
            Text("Hello from Aignals")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

This is a placeholder; real icon/menu come in Phase 8.

- [ ] **Step 3: Set the app to "Application is agent (UIElement)" so it has no dock icon**

Edit `App/Aignals/Aignals/Info.plist`, add:

```xml
<key>LSUIElement</key>
<true/>
```

Build target: Set Deployment Target → macOS 13.0.

- [ ] **Step 4: Link `AignalsCore` library from the SPM workspace**

In Xcode: select the Aignals target → General → Frameworks, Libraries, and Embedded Content → `+` → Add Other → Add Package Dependency → Add Local → select repo root. Add `AignalsCore` to the app target.

- [ ] **Step 5: Build the app**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add App/Aignals
git commit -m "phase-00: add Xcode menu-bar app target wired to AignalsCore"
```

---

### Task 0.5: CI skeleton (GitHub Actions)

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app
      - name: Install bats + jq
        run: brew install bats-core jq
      - name: Swift tests (unit + integration + E2E)
        run: swift test
      - name: bats tests (hook CLI)
        run: bats Tests/HookTests
      - name: Build the app
        run: |
          xcodebuild \
            -project App/Aignals/Aignals.xcodeproj \
            -scheme Aignals \
            -configuration Debug \
            -destination 'platform=macOS' \
            build
```

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "phase-00: add CI workflow (swift test + bats + xcodebuild)"
```

---

### Acceptance for Phase 0

- `swift build` and `swift test` succeed locally.
- `xcodebuild ... build` succeeds locally.
- CI workflow file present.
- All commits land on `main` (or the active branch).

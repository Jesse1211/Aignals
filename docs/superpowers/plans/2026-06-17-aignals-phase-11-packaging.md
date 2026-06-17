# Phase 11 — Packaging + Release

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Produce a self-signed `Aignals.app` bundle (with `aignals-hook` inside), package it as a `.dmg`, set up a Homebrew tap, and publish a GitHub release.

**Depends on:** Phases 0–10 all green.

**Spec sections:** §10 (distribution).

---

### Task 11.1: Bundle `aignals-hook` into the app

**Files:**
- Modify: Xcode project (build phase + Copy Files)

- [ ] **Step 1a: Add the script as a project reference**

In Xcode: File → Add Files to "Aignals"… → select `CLI/aignals-hook/aignals-hook`.
- Uncheck "Copy items if needed" (keep it referenced in place).
- Uncheck *all* target memberships in the inspector (we'll wire it via Copy Files explicitly).

- [ ] **Step 1b: Add a Copy Files build phase**

Aignals target → Build Phases → `+` → New Copy Files Phase.
- Destination: `Resources`
- Click `+` inside the new phase and pick the `aignals-hook` file you just added.
- Ensure "Copy only when installing" is unchecked.

- [ ] **Step 2: Add a Run Script phase to chmod the copied script**

Run Script (after the Copy Files phase):

```bash
chmod +x "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/aignals-hook"
```

- [ ] **Step 3: Build + verify**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals \
  -configuration Release -derivedDataPath ./build build
APP="./build/Build/Products/Release/Aignals.app"
test -x "$APP/Contents/Resources/aignals-hook"
```

Expected: file exists and is executable.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Aignals.xcodeproj
git commit -m "phase-11: bundle aignals-hook into Aignals.app Resources"
```

---

### Task 11.2: CLI install helper inside the app

**Files:**
- Modify: `App/Aignals/UI/AppViewModel.swift`
- Modify: `App/Aignals/UI/MenuContent.swift`

- [ ] **Step 1: Install helper**

Add to `AppViewModel`:

```swift
extension AppViewModel {
    var bundledHookURL: URL? {
        Bundle.main.url(forResource: "aignals-hook", withExtension: nil)
    }

    var hookSymlinkURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/bin/aignals-hook")
    }

    var hookIsLinked: Bool {
        FileManager.default.fileExists(atPath: hookSymlinkURL.path)
    }

    func linkHookCLI() throws {
        guard let src = bundledHookURL else { return }
        let dir = hookSymlinkURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: hookSymlinkURL)
        try FileManager.default.createSymbolicLink(at: hookSymlinkURL, withDestinationURL: src)
    }
}
```

- [ ] **Step 2: Menu item**

In `MenuContent`:

```swift
if !vm.hookIsLinked {
    Button("Install aignals-hook CLI…") {
        do {
            try vm.linkHookCLI()
            Self.alert("Linked", informative: "Symlinked aignals-hook into ~/.local/bin. If that's not on your PATH, add: export PATH=\"$HOME/.local/bin:$PATH\"")
        } catch {
            Self.alert("Couldn't link CLI", informative: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals build
git add App/Aignals
git commit -m "phase-11: add 'Install aignals-hook CLI' menu item (~/.local/bin symlink)"
```

---

### Task 11.3: Self-sign + dmg packaging script

**Files:**
- Create: `scripts/build-release.sh`

- [ ] **Step 1: Write**

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:-0.1.0}"

PROJ="App/Aignals/Aignals.xcodeproj"
SCHEME="Aignals"
DERIVED="./build"
APP="$DERIVED/Build/Products/Release/Aignals.app"

rm -rf "$DERIVED" dist
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" build
test -x "$APP/Contents/Resources/aignals-hook"

# Self-sign
codesign --force --deep --sign - "$APP"

mkdir -p dist
ZIP="dist/Aignals-$VERSION.zip"
DMG="dist/Aignals-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if command -v create-dmg >/dev/null; then
  create-dmg \
    --volname "Aignals $VERSION" \
    --window-size 540 320 \
    --icon-size 96 \
    --icon "Aignals.app" 140 160 \
    --app-drop-link 400 160 \
    "$DMG" \
    "$APP"
else
  hdiutil create -volname "Aignals $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"
fi

shasum -a 256 "$ZIP" "$DMG" > "dist/SHA256SUMS-$VERSION.txt"
ls -lh dist/
```

- [ ] **Step 2: Run + commit**

```bash
chmod +x scripts/build-release.sh
./scripts/build-release.sh 0.1.0
git add scripts/build-release.sh
git commit -m "phase-11: add build-release.sh (self-sign + dmg + zip + checksum)"
```

---

### Task 11.4: Homebrew tap stub

**Files:**
- Create: `homebrew/aignals.rb`

- [ ] **Step 1: Write cask**

```ruby
cask "aignals" do
  version "0.1.0"
  sha256 "REPLACE-WITH-RELEASE-CHECKSUM"

  url "https://github.com/YOUR-USERNAME/Aignals/releases/download/v#{version}/Aignals-#{version}.dmg"
  name "Aignals"
  desc "Menu bar indicator for AI coding agent activity"
  homepage "https://github.com/YOUR-USERNAME/Aignals"

  app "Aignals.app"

  zap trash: [
    "~/.aignals",
    "~/Library/Preferences/com.aignals.Aignals.plist",
  ]
end
```

- [ ] **Step 2: README install instructions**

Append to `README.md`:

```markdown
## Install

```bash
brew tap YOUR-USERNAME/aignals
brew install --cask aignals
```

Or download `Aignals-0.1.0.dmg` from the [latest release](https://github.com/YOUR-USERNAME/Aignals/releases/latest). On first launch, right-click → Open to bypass Gatekeeper (the build is self-signed).

After installing the app, run **Install Claude Code Hooks…** from the menu (or accept the first-launch prompt) to wire it up.
```

- [ ] **Step 3: Commit**

```bash
git add homebrew/aignals.rb README.md
git commit -m "phase-11: add Homebrew cask stub + README install instructions"
```

---

### Task 11.5: CI release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write**

```yaml
name: release
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app
      - name: Build
        run: ./scripts/build-release.sh "${GITHUB_REF_NAME#v}"
      - name: Upload artifacts
        uses: softprops/action-gh-release@v2
        with:
          files: |
            dist/Aignals-*.dmg
            dist/Aignals-*.zip
            dist/SHA256SUMS-*.txt
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "phase-11: add release workflow (tag → dmg + zip + checksum)"
```

---

### Task 11.6: Tag v0.1.0

- [ ] **Step 1: Run full suite one more time**

```bash
swift test
bats Tests/HookTests
xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals build
```

Expected: everything green.

- [ ] **Step 2: Tag (ask user before pushing)**

```bash
git tag -a v0.1.0 -m "Aignals v0.1.0"
echo "Push with: git push origin main --tags  — verify with the user first"
```

---

### Acceptance for Phase 11

- `scripts/build-release.sh 0.1.0` produces `dist/Aignals-0.1.0.{dmg,zip}` and a checksum file.
- Bundled app contains an executable `aignals-hook` at `Contents/Resources/`.
- Homebrew cask + README install instructions present.
- Release workflow committed.
- Tag created locally (push deferred to user).

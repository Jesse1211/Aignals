# Feishu Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a Claude Code session transitions into 🟡 waiting-permission or 🟢 waiting-input, optionally POST a text message to a user-configured Feishu custom-bot webhook, alongside the existing system sound.

**Architecture:** A pure `FeishuMessage` builds the text; a `FeishuClient` does the async `URLSession` POST with optional CryptoKit HMAC signing; the existing `AppViewModel` diff loop (`handleSessionSounds` → `handleSessionAlerts`) drives both sound and Feishu off one pass, sharing a per-session throttle. Config gains four persisted fields; Settings gains a toggle + three text fields + a Send-test button + a last-error warning.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, `URLSession`, `CryptoKit` (HMAC-SHA256), XCTest. No third-party dependencies.

## Global Constraints

- Platform floor: macOS 14 (`Package.swift`). CryptoKit `HMAC<SHA256>` is available — do NOT add any dependency.
- `AignalsCore` is pure (no SwiftUI/AppKit) so it stays unit-testable — `FeishuMessage` and `FeishuClient` live there; SwiftUI wiring lives in the App target.
- New `AignalsConfig` fields MUST use `decodeIfPresent` with a default so legacy `config.json` upgrades cleanly (mirror `soundEnabled`).
- Every message text begins with the literal `Aignals` (keyword-mode bots can use `Aignals` as their keyword for free).
- Best-effort sends: fire-and-forget `Task`, no retries, no queue. Failures surface in the UI only.
- Conventional-commit messages, one commit per task. End commit bodies with the `Co-Authored-By` trailer already used in this repo.

---

### Task 1: Add four Feishu fields to `AignalsConfig`

**Files:**
- Modify: `Sources/AignalsCore/ConfigStore.swift`
- Test: `Tests/AignalsCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: existing `AignalsConfig` struct + `ConfigStore`.
- Produces: `AignalsConfig.feishuEnabled: Bool` (default `false`), `.feishuWebhookURL: String` (default `""`), `.feishuSecret: String` (default `""`), `.feishuKeyword: String` (default `""`); all persisted by `ConfigStore.save` and decoded with `decodeIfPresent`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AignalsCoreTests/ConfigStoreTests.swift` (before the final closing `}`):

```swift
func testFeishuDefaults() throws {
    let store = ConfigStore(paths: try tmpHome())
    XCTAssertEqual(store.config.feishuEnabled, false)
    XCTAssertEqual(store.config.feishuWebhookURL, "")
    XCTAssertEqual(store.config.feishuSecret, "")
    XCTAssertEqual(store.config.feishuKeyword, "")
}

func testFeishuRoundtrip() throws {
    let paths = try tmpHome()
    let store = ConfigStore(paths: paths)
    var c = store.config
    c.feishuEnabled = true
    c.feishuWebhookURL = "https://open.feishu.cn/open-apis/bot/v2/hook/abc"
    c.feishuSecret = "s3cr3t"
    c.feishuKeyword = "Aignals"
    store.save(c)

    let reload = ConfigStore(paths: paths)
    XCTAssertEqual(reload.config.feishuEnabled, true)
    XCTAssertEqual(reload.config.feishuWebhookURL, "https://open.feishu.cn/open-apis/bot/v2/hook/abc")
    XCTAssertEqual(reload.config.feishuSecret, "s3cr3t")
    XCTAssertEqual(reload.config.feishuKeyword, "Aignals")
}

func testFeishuFieldsDecodeDefaultsWhenAbsent() throws {
    let paths = try tmpHome()
    // Legacy config.json without any feishu keys must decode to the off defaults.
    try Data(#"{"launchAtLogin":false,"dismissedInstallPrompt":false,"soundEnabled":true,"theme":"glassDark"}"#.utf8)
        .write(to: paths.configFile)
    let store = ConfigStore(paths: paths)
    XCTAssertEqual(store.config.feishuEnabled, false)
    XCTAssertEqual(store.config.feishuWebhookURL, "")
    XCTAssertEqual(store.config.feishuSecret, "")
    XCTAssertEqual(store.config.feishuKeyword, "")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL — `value of type 'AignalsConfig' has no member 'feishuEnabled'`.

- [ ] **Step 3: Add the fields to `AignalsConfig`**

In `Sources/AignalsCore/ConfigStore.swift`:

Add stored properties after `public var inputSound: AlertSound` (line 17):

```swift
    /// Feishu (飞书/Lark) custom-bot notification toggle. Decodes to `false` when
    /// absent so existing config.json files keep notifications off after upgrade.
    public var feishuEnabled: Bool
    /// Feishu custom-bot webhook URL (https://open.feishu.cn/open-apis/bot/v2/hook/…).
    public var feishuWebhookURL: String
    /// Optional signing secret for signature-mode bots (HMAC-SHA256). Empty = unsigned.
    public var feishuSecret: String
    /// Optional keyword for keyword-mode bots; appended to messages that don't already
    /// contain it so Feishu accepts them. Empty = no keyword constraint.
    public var feishuKeyword: String
```

Extend the memberwise `init` signature (line 19) and body. Replace the existing `public init(...)` with:

```swift
    public init(launchAtLogin: Bool, dismissedInstallPrompt: Bool, soundEnabled: Bool = true, theme: Theme = .glassDark, permissionSound: AlertSound = .ping, inputSound: AlertSound = .glass, feishuEnabled: Bool = false, feishuWebhookURL: String = "", feishuSecret: String = "", feishuKeyword: String = "") {
        self.launchAtLogin = launchAtLogin
        self.dismissedInstallPrompt = dismissedInstallPrompt
        self.soundEnabled = soundEnabled
        self.theme = theme
        self.permissionSound = permissionSound
        self.inputSound = inputSound
        self.feishuEnabled = feishuEnabled
        self.feishuWebhookURL = feishuWebhookURL
        self.feishuSecret = feishuSecret
        self.feishuKeyword = feishuKeyword
    }
```

`static let default` (line 28) needs no change — the new params all default, so `.default` keeps the Feishu-off values.

Add to `CodingKeys` (after `case inputSound`):

```swift
        case feishuEnabled
        case feishuWebhookURL
        case feishuSecret
        case feishuKeyword
```

Add to `init(from:)` (after the `inputSound` decode line):

```swift
        self.feishuEnabled = try container.decodeIfPresent(Bool.self, forKey: .feishuEnabled) ?? false
        self.feishuWebhookURL = try container.decodeIfPresent(String.self, forKey: .feishuWebhookURL) ?? ""
        self.feishuSecret = try container.decodeIfPresent(String.self, forKey: .feishuSecret) ?? ""
        self.feishuKeyword = try container.decodeIfPresent(String.self, forKey: .feishuKeyword) ?? ""
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS (all existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/ConfigStore.swift Tests/AignalsCoreTests/ConfigStoreTests.swift
git commit -m "feat(core): persist feishuEnabled/URL/secret/keyword in AignalsConfig

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `FeishuMessage` — pure text builder with keyword guarantee

**Files:**
- Create: `Sources/AignalsCore/FeishuMessage.swift`
- Test: `Tests/AignalsCoreTests/FeishuMessageTests.swift`

**Interfaces:**
- Consumes: `SessionState` (cases `.working`, `.waitingPermission`, `.waitingInput`, `.disconnected`).
- Produces: `enum FeishuMessage { static func text(displayName: String, state: SessionState, keyword: String = "") -> String? }`. Returns `nil` for `.working`/`.disconnected`. For 🟡/🟢 returns the formatted string, with ` [<keyword>]` appended iff `keyword` is non-empty and not already a substring.

- [ ] **Step 1: Write the failing tests**

Create `Tests/AignalsCoreTests/FeishuMessageTests.swift`:

```swift
import XCTest
@testable import AignalsCore

final class FeishuMessageTests: XCTestCase {
    func testWorkingAndDisconnectedAreNil() {
        XCTAssertNil(FeishuMessage.text(displayName: "p", state: .working))
        XCTAssertNil(FeishuMessage.text(displayName: "p", state: .disconnected))
    }

    func testPermissionText() {
        let t = FeishuMessage.text(displayName: "my-project", state: .waitingPermission)
        XCTAssertEqual(t, "Aignals • my-project: 🟡 waiting for permission — go click Allow")
    }

    func testInputText() {
        let t = FeishuMessage.text(displayName: "my-project", state: .waitingInput)
        XCTAssertEqual(t, "Aignals • my-project: 🟢 finished — your turn")
    }

    func testDisplayNameHonored() {
        let t = FeishuMessage.text(displayName: "renamed!", state: .waitingInput)
        XCTAssertTrue(t!.contains("renamed!"))
    }

    func testEmptyKeywordAppendsNothing() {
        let t = FeishuMessage.text(displayName: "p", state: .waitingInput, keyword: "")
        XCTAssertFalse(t!.contains("["))
    }

    func testKeywordAlreadyPresentAppendsNothing() {
        // "Aignals" is always in the text, so an Aignals keyword adds nothing.
        let t = FeishuMessage.text(displayName: "p", state: .waitingInput, keyword: "Aignals")
        XCTAssertFalse(t!.contains("[Aignals]"))
    }

    func testNovelKeywordIsAppended() {
        let t = FeishuMessage.text(displayName: "p", state: .waitingInput, keyword: "robot")
        XCTAssertTrue(t!.hasSuffix(" [robot]"))
        XCTAssertTrue(t!.contains("robot"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FeishuMessageTests`
Expected: FAIL — `cannot find 'FeishuMessage' in scope`.

- [ ] **Step 3: Implement `FeishuMessage`**

Create `Sources/AignalsCore/FeishuMessage.swift`:

```swift
import Foundation

/// Builds the plain-text body Aignals pushes to a Feishu custom bot on a 🟡/🟢
/// transition. Pure (no networking) so it is unit-tested; the App target passes
/// the session's effective display name (honoring renames) and the configured
/// keyword. States that never alert (working/disconnected) return `nil`, mirroring
/// `AppViewModel.sound(forTransitionInto:)`.
public enum FeishuMessage {
    /// The message for a transition INTO `state`, or `nil` for non-alerting states.
    ///
    /// Every message begins with the literal `Aignals`. If `keyword` is non-empty
    /// and the text does not already contain it (Feishu keyword-mode requires a
    /// literal-substring match), ` [<keyword>]` is appended so the bot accepts it.
    public static func text(displayName: String, state: SessionState, keyword: String = "") -> String? {
        let body: String
        switch state {
        case .waitingPermission:
            body = "Aignals • \(displayName): 🟡 waiting for permission — go click Allow"
        case .waitingInput:
            body = "Aignals • \(displayName): 🟢 finished — your turn"
        case .working, .disconnected:
            return nil
        }
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if kw.isEmpty || body.contains(kw) { return body }
        return body + " [\(kw)]"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FeishuMessageTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/FeishuMessage.swift Tests/AignalsCoreTests/FeishuMessageTests.swift
git commit -m "feat(core): FeishuMessage pure text builder with keyword guarantee

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `FeishuClient` — signing helper (pure, deterministic)

**Files:**
- Create: `Sources/AignalsCore/FeishuClient.swift`
- Test: `Tests/AignalsCoreTests/FeishuClientTests.swift`

**Interfaces:**
- Produces, in this task:
  - `enum FeishuError: Error, Equatable { case transport(String); case http(Int); case feishu(Int, String) }`
  - `struct FeishuClient` with a static signing helper `static func sign(timestamp: Int, secret: String) -> String` computing `Base64(HMAC-SHA256(key: "<timestamp>\n<secret>", data: empty))`.
  - `static func body(text: String, timestamp: Int, secret: String) -> [String: Any]` building the request dictionary: always `msg_type`/`content`; adds `timestamp`/`sign` only when `secret` is non-empty.
- The async `send` method is added in Task 4 (kept separate so signing/body shape are tested without any URLSession plumbing).

- [ ] **Step 1: Write the failing tests**

Create `Tests/AignalsCoreTests/FeishuClientTests.swift`:

```swift
import XCTest
@testable import AignalsCore

final class FeishuClientTests: XCTestCase {
    // Known vector: HMAC-SHA256 with key "1599360000\nmysecret" over empty data,
    // Base64-encoded. Recomputed independently to lock the algorithm.
    func testSignKnownVector() {
        let sig = FeishuClient.sign(timestamp: 1599360000, secret: "mysecret")
        XCTAssertEqual(sig, "S5GhС…")   // replace with computed value in Step 3
    }

    func testBodyWithoutSecretOmitsSignFields() {
        let b = FeishuClient.body(text: "hi", timestamp: 1599360000, secret: "")
        XCTAssertEqual(b["msg_type"] as? String, "text")
        XCTAssertEqual((b["content"] as? [String: Any])?["text"] as? String, "hi")
        XCTAssertNil(b["timestamp"])
        XCTAssertNil(b["sign"])
    }

    func testBodyWithSecretAddsSignFields() {
        let b = FeishuClient.body(text: "hi", timestamp: 1599360000, secret: "mysecret")
        XCTAssertEqual(b["timestamp"] as? String, "1599360000")
        XCTAssertEqual(b["sign"] as? String, FeishuClient.sign(timestamp: 1599360000, secret: "mysecret"))
    }
}
```

> The `testSignKnownVector` expected value is filled in Step 3 once computed locally — do NOT leave the placeholder. The test exists to pin the exact algorithm against regressions.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FeishuClientTests`
Expected: FAIL — `cannot find 'FeishuClient' in scope`.

- [ ] **Step 3: Implement signing + body, then capture the real vector**

Create `Sources/AignalsCore/FeishuClient.swift`:

```swift
import Foundation
import CryptoKit

/// Errors from a Feishu webhook send, each carrying a short string for the UI.
public enum FeishuError: Error, Equatable {
    case transport(String)   // offline / DNS / TLS — no HTTP response
    case http(Int)           // non-2xx HTTP status
    case feishu(Int, String) // HTTP ok but body code != 0 (e.g. 19021 bad sign)
}

/// Posts a text message to a Feishu custom-bot webhook. Signing and body-shaping
/// are pure statics (unit-tested); `send` (Task 4) does the URLSession POST.
public struct FeishuClient {
    /// Feishu signature: Base64(HMAC-SHA256(key: "<timestamp>\n<secret>", data: empty)).
    public static func sign(timestamp: Int, secret: String) -> String {
        let key = SymmetricKey(data: Data("\(timestamp)\n\(secret)".utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(), using: key)
        return Data(mac).base64EncodedString()
    }

    /// The JSON request body. Adds `timestamp`/`sign` only for signature-mode bots.
    public static func body(text: String, timestamp: Int, secret: String) -> [String: Any] {
        var b: [String: Any] = ["msg_type": "text", "content": ["text": text]]
        if !secret.isEmpty {
            b["timestamp"] = "\(timestamp)"
            b["sign"] = sign(timestamp: timestamp, secret: secret)
        }
        return b
    }
}
```

Now compute the real signature to replace the placeholder in the test. Run:

```bash
swift -e 'import Foundation; import CryptoKit; let k = SymmetricKey(data: Data("1599360000\nmysecret".utf8)); print(Data(HMAC<SHA256>.authenticationCode(for: Data(), using: k)).base64EncodedString())'
```

Copy the printed Base64 string into `testSignKnownVector`'s `XCTAssertEqual` (replacing `"S5GhС…"`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FeishuClientTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/FeishuClient.swift Tests/AignalsCoreTests/FeishuClientTests.swift
git commit -m "feat(core): FeishuClient HMAC-SHA256 signing + request body shaping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `FeishuClient.send` — async POST with injected transport

**Files:**
- Modify: `Sources/AignalsCore/FeishuClient.swift`
- Test: `Tests/AignalsCoreTests/FeishuClientTests.swift`

**Interfaces:**
- Consumes: `FeishuClient.body`, `FeishuError` (Task 3).
- Produces:
  - A transport seam `public protocol FeishuTransport: Sendable { func post(_ request: URLRequest) async throws -> (Data, URLResponse) }` with a default `URLSession` conformance.
  - `func send(text: String, webhookURL: String, secret: String, timestamp: Int) async -> Result<Void, FeishuError>` on `FeishuClient`, using the instance's transport. `timestamp` is a param (caller passes current Unix seconds) so tests are deterministic.
  - `init(transport: FeishuTransport = URLSession.shared)`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AignalsCoreTests/FeishuClientTests.swift`:

```swift
private struct StubTransport: FeishuTransport {
    let result: Result<(Data, URLResponse), Error>
    func post(_ request: URLRequest) async throws -> (Data, URLResponse) {
        switch result {
        case .success(let pair): return pair
        case .failure(let err): throw err
        }
    }
    static func http(_ status: Int, _ json: String) -> StubTransport {
        let resp = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return StubTransport(result: .success((Data(json.utf8), resp)))
    }
}

func testSendSuccessOnCodeZero() async {
    let client = FeishuClient(transport: StubTransport.http(200, #"{"code":0,"msg":"success"}"#))
    let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "", timestamp: 1599360000)
    XCTAssertEqual(r, .success(()))
}

func testSendFeishuRejectionOnNonZeroCode() async {
    let client = FeishuClient(transport: StubTransport.http(200, #"{"code":19021,"msg":"sign match fail"}"#))
    let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "s", timestamp: 1599360000)
    XCTAssertEqual(r, .failure(.feishu(19021, "sign match fail")))
}

func testSendHTTPErrorOnNon2xx() async {
    let client = FeishuClient(transport: StubTransport.http(500, "oops"))
    let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "", timestamp: 1599360000)
    XCTAssertEqual(r, .failure(.http(500)))
}

func testSendTransportErrorWhenThrown() async {
    let stub = StubTransport(result: .failure(URLError(.notConnectedToInternet)))
    let client = FeishuClient(transport: stub)
    let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "", timestamp: 1599360000)
    if case .failure(.transport) = r { } else { XCTFail("expected .transport, got \(r)") }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FeishuClientTests`
Expected: FAIL — `cannot find type 'FeishuTransport'` / no `send` member.

- [ ] **Step 3: Implement transport + send**

In `Sources/AignalsCore/FeishuClient.swift`, add above `public struct FeishuClient`:

```swift
/// Seam over the network call so `send` is unit-testable with a stub.
public protocol FeishuTransport: Sendable {
    func post(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FeishuTransport {
    public func post(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
```

Add a stored `transport` + `init` and the `send` method inside `FeishuClient`:

```swift
    let transport: FeishuTransport
    public init(transport: FeishuTransport = URLSession.shared) {
        self.transport = transport
    }

    /// POST `text` to `webhookURL`. `timestamp` is supplied by the caller (current
    /// Unix seconds) so signing is deterministic in tests. Best-effort: returns a
    /// `Result` rather than throwing, for the UI to surface.
    public func send(text: String, webhookURL: String, secret: String, timestamp: Int) async -> Result<Void, FeishuError> {
        guard let url = URL(string: webhookURL) else {
            return .failure(.transport("invalid URL"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: Self.body(text: text, timestamp: timestamp, secret: secret))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport.post(req)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return .failure(.http(http.statusCode))
        }
        // Feishu returns {"code":0} on success, non-zero on rejection.
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let code = (obj?["code"] as? Int) ?? 0
        if code != 0 {
            let msg = (obj?["msg"] as? String) ?? "unknown"
            return .failure(.feishu(code, msg))
        }
        return .success(())
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FeishuClientTests`
Expected: PASS (7 total: 3 from Task 3 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/FeishuClient.swift Tests/AignalsCoreTests/FeishuClientTests.swift
git commit -m "feat(core): FeishuClient.send async POST with injectable transport

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: View-model wiring — config bridges, `lastFeishuError`, send helpers, test action

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

**Interfaces:**
- Consumes: `FeishuMessage`, `FeishuClient`, `FeishuError`, `AignalsConfig.feishu*`, existing `config` setter, `displayName(for:)`.
- Produces (used by Task 6 UI and Task 7 trigger):
  - `var feishuEnabled: Bool { get set }`, `var feishuWebhookURL: String { get set }`, `var feishuSecret: String { get set }`, `var feishuKeyword: String { get set }` — each backed by `config` (persisted).
  - `private(set) var lastFeishuError: String?` (observable).
  - `func sendFeishu(text: String)` — fire-and-forget; updates `lastFeishuError`.
  - `func sendFeishuTest()` — sends the fixed test message through `FeishuMessage` keyword-append.
  - `let feishuClient = FeishuClient()` stored on the view-model.

This task has no unit test (the view-model is `@MainActor`/AppKit-bound and not in the test target — consistent with the existing sound code, which is also untested here). Verification is the build + the Task 8 manual checklist.

- [ ] **Step 1: Add the stored client and error state**

In `App/Aignals/Sources/AppViewModel.swift`, add near the other stored properties (after `private let sweeper: PIDSweeper` at line 33):

```swift
    private let feishuClient = FeishuClient()

    /// Last Feishu send outcome surfaced to Settings: `nil` = ok/never-sent, else a
    /// short human string. Set on the main actor after each send completes.
    private(set) var lastFeishuError: String?
```

- [ ] **Step 2: Add the config bridges**

Add to the `extension AppViewModel` that holds `soundEnabled`/`theme` (after `soundEnabled`, around line 483):

```swift
    /// Feishu master toggle, backed by `config.feishuEnabled` (persisted).
    var feishuEnabled: Bool {
        get { config.feishuEnabled }
        set { var c = config; c.feishuEnabled = newValue; config = c }
    }

    /// Feishu webhook URL (persisted). Send is gated on this being non-empty.
    var feishuWebhookURL: String {
        get { config.feishuWebhookURL }
        set { var c = config; c.feishuWebhookURL = newValue; config = c }
    }

    /// Optional signing secret (persisted).
    var feishuSecret: String {
        get { config.feishuSecret }
        set { var c = config; c.feishuSecret = newValue; config = c }
    }

    /// Optional keyword for keyword-mode bots (persisted).
    var feishuKeyword: String {
        get { config.feishuKeyword }
        set { var c = config; c.feishuKeyword = newValue; config = c }
    }
```

- [ ] **Step 3: Add the send helpers**

Add a new extension at the end of `App/Aignals/Sources/AppViewModel.swift`:

```swift
// MARK: - Feishu notifications (send + test)

extension AppViewModel {
    /// Fire-and-forget POST of `text` to the configured webhook. Best-effort: on
    /// completion sets `lastFeishuError` (nil on success) so Settings can warn.
    /// Caller is responsible for all gating; this just sends.
    func sendFeishu(text: String) {
        let url = config.feishuWebhookURL
        let secret = config.feishuSecret
        guard !url.isEmpty else { return }
        let ts = Int(Date().timeIntervalSince1970)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.feishuClient.send(text: text, webhookURL: url, secret: secret, timestamp: ts)
            switch result {
            case .success:
                self.lastFeishuError = nil
            case .failure(let err):
                self.lastFeishuError = Self.describe(err)
            }
        }
    }

    /// Send the fixed test message (run through the keyword-append so keyword-mode
    /// bots accept it), invoked by the Settings "Send test" button.
    func sendFeishuTest() {
        let base = "Aignals • test — notifications are working"
        let kw = config.feishuKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (kw.isEmpty || base.contains(kw)) ? base : base + " [\(kw)]"
        sendFeishu(text: text)
    }

    /// Map a `FeishuError` to a short UI string.
    private static func describe(_ err: FeishuError) -> String {
        switch err {
        case .transport(let m): return "Send failed: \(m)"
        case .http(let s):      return "Send failed: HTTP \(s)"
        case .feishu(let c, let m): return "Feishu rejected: \(m) (\(c))"
        }
    }
}
```

> Note `import AignalsCore` is already at the top of this file (line 3), so `FeishuClient`/`FeishuError`/`FeishuMessage` are in scope.

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Builds clean (the `AignalsCore` library target compiles; the App target is built by Xcode but `swift build` confirms the core + the file's `AignalsCore` references resolve). If Xcode is available, also build the app scheme.

- [ ] **Step 5: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): Feishu config bridges, lastFeishuError, send + test helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Settings UI — toggle, three fields, Send-test button, error warning

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `vm.feishuEnabled`, `vm.feishuWebhookURL`, `vm.feishuSecret`, `vm.feishuKeyword`, `vm.lastFeishuError`, `vm.sendFeishuTest()` (Task 5).
- Produces: UI only.

- [ ] **Step 1: Add the Feishu block to the Settings fold**

In `App/Aignals/Sources/MenuContent.swift`, insert AFTER the sound `if vm.soundEnabled { … }` block (closes at line 280) and BEFORE the `// One-way Enable Launch at Login` comment (line 282):

```swift
        // Feishu (飞书/Lark) notifications: independent of sounds. Fires on the same
        // 🟡/🟢 transitions, POSTing to a user-configured custom-bot webhook.
        Toggle("Feishu notifications", isOn: Binding(
            get: { vm.feishuEnabled },
            set: { vm.feishuEnabled = $0 }
        ))
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)

        if vm.feishuEnabled {
            feishuField("Webhook URL", text: Binding(
                get: { vm.feishuWebhookURL }, set: { vm.feishuWebhookURL = $0 }))
            feishuField("Secret (optional)", text: Binding(
                get: { vm.feishuSecret }, set: { vm.feishuSecret = $0 }))
            feishuField("Keyword (optional)", text: Binding(
                get: { vm.feishuKeyword }, set: { vm.feishuKeyword = $0 }))

            Text("Secret: for signature-mode bots. Keyword: only if your bot uses keyword security.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            menuButton("Send test message") { vm.sendFeishuTest() }

            if let err = vm.lastFeishuError {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("⚠︎")
                    Text(err).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
```

- [ ] **Step 2: Add the `feishuField` helper**

Add next to `soundPicker` (after it closes at line 309):

```swift
    private func feishuField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Builds clean. If Xcode is available, build the app scheme and open the menu to confirm the fields render only when the toggle is on.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/MenuContent.swift
git commit -m "feat(ui): Feishu settings — toggle, URL/secret/keyword fields, test button, error warning

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Trigger wiring — fire Feishu on 🟡/🟢 transitions, shared throttle

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

**Interfaces:**
- Consumes: `FeishuMessage.text`, `vm.sendFeishu`, `config.feishuEnabled`, `config.feishuWebhookURL`, `config.feishuKeyword`, `displayName(for:)`.
- Produces: behavior change only — Feishu sends alongside sound from one diff pass.

This is the control-flow refactor the spec flagged as implementation-critical. The throttle moves OUT of the sound branch so a sound-off / Feishu-on session still reaches it.

- [ ] **Step 1: Rename the throttle map and method**

In `App/Aignals/Sources/AppViewModel.swift`:
- Rename `private var lastSoundAt: [String: Date] = [:]` (line 46) to `private var lastAlertAt: [String: Date] = [:]`.
- Rename the method `handleSessionSounds()` (declaration ~line 279) to `handleSessionAlerts()`, and update its call site inside the `Task` in `init` (line 84) from `self?.handleSessionSounds()` to `self?.handleSessionAlerts()`.
- Update the two `lastSoundAt` references inside the method (the filter at the bottom, ~line 307) to `lastAlertAt`.

- [ ] **Step 2: Restructure the per-session loop body**

Replace the body of the `for session in store.sessions` loop in `handleSessionAlerts()` (lines ~284–301, from `let id = session.sessionID` through `Self.play(sound)`) with:

```swift
            let id = session.sessionID
            live.insert(id)
            let previous = lastKnownState[id]
            lastKnownState[id] = session.state

            // Channel-independent gate: first observation or unchanged state → nothing,
            // and a per-session muted row sends neither channel.
            guard let previous, previous != session.state else { continue }
            guard overrideStore.override(for: id)?.muted != true else { continue }

            // Decide per channel whether it wants to fire THIS transition.
            let soundName = sound(forTransitionInto: session.state)
            let wantsSound = soundOn && soundName != nil
            let wantsFeishu = config.feishuEnabled
                && !config.feishuWebhookURL.isEmpty
                && FeishuMessage.text(displayName: displayName(for: session),
                                      state: session.state,
                                      keyword: config.feishuKeyword) != nil
            guard wantsSound || wantsFeishu else { continue }

            // Shared per-session throttle: one stamp covers both channels.
            if let last = lastAlertAt[id], now.timeIntervalSince(last) < soundThrottle {
                continue
            }
            lastAlertAt[id] = now

            if wantsSound, let soundName { Self.play(soundName) }
            if wantsFeishu,
               let text = FeishuMessage.text(displayName: displayName(for: session),
                                             state: session.state,
                                             keyword: config.feishuKeyword) {
                sendFeishu(text: text)
            }
```

The trailing map cleanup stays but uses the renamed map:

```swift
        lastKnownState = lastKnownState.filter { live.contains($0.key) }
        lastAlertAt = lastAlertAt.filter { live.contains($0.key) }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Builds clean.

- [ ] **Step 4: Manual smoke (if Xcode available)**

Build + run the app. With hooks installed and a real Claude Code session: enable Feishu + paste a valid webhook, then drive a session to 🟢 (finish a turn). Confirm a Feishu message arrives AND (if sound on) a sound plays once. Toggle sound OFF, drive another transition: Feishu still fires. This confirms the throttle moved out of the sound branch correctly.

- [ ] **Step 5: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): fire Feishu on 🟡/🟢 transitions; shared per-session throttle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Docs — README + manual test checklist

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/manual-test-checklist.md`

**Interfaces:** docs only.

- [ ] **Step 1: Add a README section**

In `README.md`, after the "Sound alerts" section, add:

```markdown
## Feishu notifications

Aignals can also push a message to **Feishu (飞书/Lark)** on the same 🟡/🟢
transitions, independent of sound. To set it up:

1. In a Feishu group: **More (···) → Settings → Group Bots → Add Bot → Custom Bot**. Name it (e.g. "Aignals") and add it.
2. Copy the generated **webhook URL** (`https://open.feishu.cn/open-apis/bot/v2/hook/…`; Lark international uses `open.larksuite.com`).
3. (Optional) Under the bot's **Security Settings**, pick one:
   - **Signature** — copy the **secret** into Aignals' *Secret* field (most secure).
   - **Custom keywords** — set a keyword and enter the SAME word in Aignals' *Keyword* field. Tip: use `Aignals` (every message already starts with it).
4. In Aignals: **Settings → Feishu notifications** → paste the webhook URL (and secret/keyword if used) → **Send test message** to confirm.

Sends are best-effort; if one fails, Settings shows a one-line reason under the toggle.
```

- [ ] **Step 2: Add manual-test rows**

In `docs/superpowers/specs/manual-test-checklist.md`, append:

```markdown
## Feishu notifications
- [ ] Settings shows "Feishu notifications" toggle; fields appear only when on.
- [ ] Webhook URL / Secret / Keyword persist across app relaunch (config.json).
- [ ] "Send test message" with a valid webhook delivers a message to the group.
- [ ] Invalid webhook → red error line appears under the toggle; valid send clears it.
- [ ] Real 🟢 transition delivers a message naming the session; rename is honored.
- [ ] Sound OFF + Feishu ON: a transition still sends Feishu (throttle moved out of sound branch).
- [ ] Per-session 🔇 mute suppresses BOTH sound and Feishu for that session.
- [ ] Keyword-mode bot: with Keyword set, messages are accepted (not dropped by Feishu).
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/superpowers/specs/manual-test-checklist.md
git commit -m "docs: document Feishu notifications + manual test checklist rows

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Plan Self-Review

**Spec coverage:**
- Triggers 🟡/🟢 → Task 7. ✓
- Independent toggle + webhook + secret + keyword config → Task 1 (persist), Task 5 (bridges), Task 6 (UI). ✓
- Reuse per-session mute + shared throttle → Task 7 (mute guard + `lastAlertAt`). ✓
- No deps; CryptoKit HMAC → Task 3. ✓
- Async POST, code!=0 vs transport vs http → Task 4. ✓
- Pure message + keyword guarantee → Task 2. ✓
- Failures surfaced in UI (`lastFeishuError`) → Task 5 + Task 6. ✓
- Send-test button (Aignals-prefixed, keyword-passed) → Task 5 (`sendFeishuTest`) + Task 6. ✓
- Tests: message, sign vector, body shape, send outcomes → Tasks 2–4. ✓
- Migration (decodeIfPresent defaults) → Task 1. ✓
- Feishu-side setup docs → Task 8. ✓

**Placeholder scan:** The only intentional placeholder is `testSignKnownVector`'s expected Base64, which Task 3 Step 3 computes and fills via the provided `swift -e` one-liner — flagged explicitly, not left vague.

**Type consistency:** `FeishuMessage.text(displayName:state:keyword:)`, `FeishuClient.sign(timestamp:secret:)`, `.body(text:timestamp:secret:)`, `.send(text:webhookURL:secret:timestamp:)`, `FeishuError.{transport,http,feishu}`, `lastAlertAt`, `handleSessionAlerts`, `sendFeishu`, `sendFeishuTest`, `lastFeishuError` — names match across Tasks 1–7. ✓

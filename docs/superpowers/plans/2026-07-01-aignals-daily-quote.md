# Daily Motivation Quote — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a daily motivation quote in the menubar that auto-refreshes at local midnight, with manual refresh, save-to-favorites, and a projector list of saved quotes.

**Architecture:** Three new pure/testable units in `Sources/AignalsCore` — `QuoteProvider` (network fetch behind a transport seam, like `FeishuClient`), `QuoteStore` (atomic JSON persistence + dedup, like `OverrideStore`), `MidnightRefresher` (injected-clock timer). UI wiring in `App/Aignals/Sources` adds a `MenuBarExtra` label text, a dropdown top row, a Settings "Daily Quote" card, a projector list, and an Uninstall "keep saved data" checkbox. **Quote code shares NO logic with session monitoring.**

**Tech Stack:** Swift 5.9, macOS 14+, SwiftUI (`MenuBarExtra` `.window` style), `URLSession`, `XCTest`. Core builds/tests via `swift test`; UI target is the Xcode `App/Aignals` project.

## Global Constraints

- **Decoupling (hard):** quote code MUST NOT reference session state, `SessionStore`, `SessionState`, or any session type. Independent units only.
- Data dir is `~/.aignals/` (via `Paths`), NOT Application Support. Saved quotes → `~/.aignals/quotes.json`.
- Persistence uses atomic temp-file + `FileManager.replaceItemAt` (match `OverrideStore`/`ConfigStore`). Corrupt/missing file → empty list.
- Network unit MUST be testable via an injected transport protocol (match `FeishuClient`'s `FeishuTransport` seam). Fetch failure (transport/non-2xx/parse) → `nil`.
- Source API: **ZenQuotes** — `https://zenquotes.io/api/today` (daily), `https://zenquotes.io/api/random` (manual refresh). Response is a JSON array of objects with keys `q` (text), `a` (author).
- Config back-compat: every new `AignalsConfig` field decodes via `decodeIfPresent ?? <default>` so existing `config.json` upgrades cleanly.
- Menubar quote text is ON by default; default truncation length = 40.
- New `Codable` structs live in `Sources/AignalsCore` so both Core tests and the App target can use them.

---

### Task 1: `Quote` model

**Files:**
- Create: `Sources/AignalsCore/Quote.swift`
- Test: `Tests/AignalsCoreTests/QuoteTests.swift`

**Interfaces:**
- Produces: `public struct Quote: Codable, Equatable, Sendable { public let text: String; public let author: String; public init(text: String, author: String) }` and `public struct SavedQuote: Codable, Equatable, Sendable { public let text: String; public let author: String; public let savedAt: Date; public init(text:author:savedAt:) }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AignalsCore

final class QuoteTests: XCTestCase {
    func test_quote_roundtrips_through_codable() throws {
        let q = Quote(text: "Keep going.", author: "Anon")
        let data = try JSONEncoder().encode(q)
        let back = try JSONDecoder().decode(Quote.self, from: data)
        XCTAssertEqual(back, q)
    }

    func test_savedQuote_encodes_savedAt_as_iso8601() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let sq = SavedQuote(text: "T", author: "A", savedAt: Date(timeIntervalSince1970: 0))
        let json = String(data: try enc.encode(sq), encoding: .utf8)!
        XCTAssertTrue(json.contains("1970-01-01T00:00:00Z"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter QuoteTests`
Expected: FAIL — `cannot find 'Quote' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A motivation quote fetched from the online source. In-memory only for the
/// daily quote; the saved-favorites variant is `SavedQuote`.
public struct Quote: Codable, Equatable, Sendable {
    public let text: String
    public let author: String
    public init(text: String, author: String) {
        self.text = text
        self.author = author
    }
}

/// A quote the user chose to keep, with the time it was saved. Persisted in
/// `~/.aignals/quotes.json` by `QuoteStore`.
public struct SavedQuote: Codable, Equatable, Sendable {
    public let text: String
    public let author: String
    public let savedAt: Date
    public init(text: String, author: String, savedAt: Date) {
        self.text = text
        self.author = author
        self.savedAt = savedAt
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter QuoteTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/Quote.swift Tests/AignalsCoreTests/QuoteTests.swift
git commit -m "feat(core): Quote + SavedQuote models"
```

---

### Task 2: `Paths.quotesFile`

**Files:**
- Modify: `Sources/AignalsCore/Paths.swift`
- Test: `Tests/AignalsCoreTests/PathsTests.swift`

**Interfaces:**
- Consumes: existing `Paths.home`.
- Produces: `public var quotesFile: URL` → `home/quotes.json`.

- [ ] **Step 1: Write the failing test** (append to `PathsTests.swift`)

```swift
func test_quotesFile_is_quotes_json_under_home() {
    let paths = Paths(environment: ["AIGNALS_HOME": "/tmp/aignals-test-home"])
    XCTAssertEqual(paths.quotesFile.path, "/tmp/aignals-test-home/quotes.json")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PathsTests/test_quotesFile_is_quotes_json_under_home`
Expected: FAIL — value of type 'Paths' has no member 'quotesFile'.

- [ ] **Step 3: Write minimal implementation** — add to `Paths.swift` after `overridesFile`:

```swift
    public var quotesFile: URL {
        home.appendingPathComponent("quotes.json")
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PathsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/Paths.swift Tests/AignalsCoreTests/PathsTests.swift
git commit -m "feat(core): Paths.quotesFile"
```

---

### Task 3: `QuoteStore` — save/dedup/delete/load

**Files:**
- Create: `Sources/AignalsCore/QuoteStore.swift`
- Test: `Tests/AignalsCoreTests/QuoteStoreTests.swift`

**Interfaces:**
- Consumes: `Paths.quotesFile`, `Quote`, `SavedQuote`.
- Produces:
  - `public final class QuoteStore`
  - `public init(paths: Paths)`
  - `public private(set) var saved: [SavedQuote]` (newest-first order)
  - `public func isSaved(_ text: String) -> Bool`
  - `public func save(_ quote: Quote, at date: Date)` — dedup by `text`, no-op if already saved
  - `public func delete(text: String)`
  - On-disk shape: `{ "version": 1, "quotes": [SavedQuote…] }` (a private `Envelope` struct).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class QuoteStoreTests: XCTestCase {
    private func tempPaths() -> Paths {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qs-\(UUID().uuidString)")
        return Paths(environment: ["AIGNALS_HOME": dir.path])
    }

    func test_save_appends_and_persists() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(store.saved.map(\.text), ["A"])
        // Fresh store reads it back from disk.
        XCTAssertEqual(QuoteStore(paths: paths).saved.map(\.text), ["A"])
    }

    func test_save_dedups_by_text() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        store.save(Quote(text: "A", author: "y"), at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(store.saved.count, 1)
    }

    func test_saved_is_newest_first() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "old", author: "x"), at: Date(timeIntervalSince1970: 10))
        store.save(Quote(text: "new", author: "x"), at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(store.saved.map(\.text), ["new", "old"])
    }

    func test_delete_removes_by_text() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        store.delete(text: "A")
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertFalse(QuoteStore(paths: paths).isSaved("A"))
    }

    func test_corrupt_file_loads_as_empty() throws {
        let paths = tempPaths()
        try paths.ensureDirectories()
        try Data("not json".utf8).write(to: paths.quotesFile)
        XCTAssertTrue(QuoteStore(paths: paths).saved.isEmpty)
    }

    func test_isSaved_reflects_state() {
        let paths = tempPaths()
        let store = QuoteStore(paths: paths)
        XCTAssertFalse(store.isSaved("A"))
        store.save(Quote(text: "A", author: "x"), at: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(store.isSaved("A"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter QuoteStoreTests`
Expected: FAIL — `cannot find 'QuoteStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// App-owned persistence for saved (favorited) quotes in `~/.aignals/quotes.json`.
/// Mirrors `OverrideStore`: crash-safe load (missing/malformed → empty), atomic
/// write via temp-file + `replaceItemAt`. Dedups by `text`; `saved` is kept
/// newest-first for the projector list. No session coupling.
public final class QuoteStore {
    private struct Envelope: Codable {
        var version: Int
        var quotes: [SavedQuote]
    }

    private let paths: Paths
    public private(set) var saved: [SavedQuote]

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.quotesFile),
           let env = try? Self.decoder.decode(Envelope.self, from: data) {
            self.saved = env.quotes.sorted { $0.savedAt > $1.savedAt }
        } else {
            self.saved = []
        }
    }

    public func isSaved(_ text: String) -> Bool {
        saved.contains { $0.text == text }
    }

    public func save(_ quote: Quote, at date: Date) {
        guard !isSaved(quote.text) else { return }
        saved.insert(SavedQuote(text: quote.text, author: quote.author, savedAt: date), at: 0)
        saved.sort { $0.savedAt > $1.savedAt }
        persist()
    }

    public func delete(text: String) {
        let before = saved.count
        saved.removeAll { $0.text == text }
        if saved.count != before { persist() }
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    private func persist() {
        try? paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tmp = paths.quotesFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? enc.encode(Envelope(version: 1, quotes: saved)) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.quotesFile, withItemAt: tmp)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter QuoteStoreTests`
Expected: PASS (all six).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/QuoteStore.swift Tests/AignalsCoreTests/QuoteStoreTests.swift
git commit -m "feat(core): QuoteStore — save/dedup/delete/load quotes.json"
```

---

### Task 4: `QuoteProvider` — network fetch behind a seam

**Files:**
- Create: `Sources/AignalsCore/QuoteProvider.swift`
- Test: `Tests/AignalsCoreTests/QuoteProviderTests.swift`

**Interfaces:**
- Consumes: `Quote`.
- Produces:
  - `public protocol QuoteTransport: Sendable { func get(_ request: URLRequest) async throws -> (Data, URLResponse) }` with `extension URLSession: QuoteTransport`.
  - `public struct QuoteProvider { public init(transport: QuoteTransport = URLSession.shared) }`
  - `public enum QuoteEndpoint { case today, random }`
  - `public func fetchQuote(_ endpoint: QuoteEndpoint = .today) async -> Quote?` — returns `nil` on transport error, non-2xx, or parse failure.
  - `public static func parse(_ data: Data) -> Quote?` — pure ZenQuotes-array parser (first element's `q`/`a`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

private struct StubTransport: QuoteTransport {
    let result: Result<(Data, URLResponse), Error>
    func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try result.get()
    }
}

private func http(_ code: Int) -> URLResponse {
    HTTPURLResponse(url: URL(string: "https://zenquotes.io")!, statusCode: code,
                    httpVersion: nil, headerFields: nil)!
}

final class QuoteProviderTests: XCTestCase {
    func test_parse_reads_first_element_q_and_a() {
        let body = Data(#"[{"q":"Keep going.","a":"Anon","h":"..."}]"#.utf8)
        XCTAssertEqual(QuoteProvider.parse(body), Quote(text: "Keep going.", author: "Anon"))
    }

    func test_parse_returns_nil_on_garbage() {
        XCTAssertNil(QuoteProvider.parse(Data("not json".utf8)))
        XCTAssertNil(QuoteProvider.parse(Data("[]".utf8)))
    }

    func test_fetch_success() async {
        let body = Data(#"[{"q":"Do it.","a":"Yoda"}]"#.utf8)
        let provider = QuoteProvider(transport: StubTransport(result: .success((body, http(200)))))
        let q = await provider.fetchQuote()
        XCTAssertEqual(q, Quote(text: "Do it.", author: "Yoda"))
    }

    func test_fetch_returns_nil_on_transport_error() async {
        struct Boom: Error {}
        let provider = QuoteProvider(transport: StubTransport(result: .failure(Boom())))
        let q = await provider.fetchQuote()
        XCTAssertNil(q)
    }

    func test_fetch_returns_nil_on_non_2xx() async {
        let provider = QuoteProvider(transport: StubTransport(result: .success((Data("[]".utf8), http(500)))))
        let q = await provider.fetchQuote()
        XCTAssertNil(q)
    }

    func test_fetch_returns_nil_on_malformed_body() async {
        let provider = QuoteProvider(transport: StubTransport(result: .success((Data("nope".utf8), http(200)))))
        let q = await provider.fetchQuote()
        XCTAssertNil(q)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter QuoteProviderTests`
Expected: FAIL — `cannot find 'QuoteProvider' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Seam over the network call so `fetchQuote` is unit-testable with a stub
/// (mirrors `FeishuTransport`).
public protocol QuoteTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: QuoteTransport {
    public func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Which ZenQuotes endpoint to hit. `.today` for the daily quote / launch /
/// midnight refresh; `.random` for the manual ⟳ refresh button.
public enum QuoteEndpoint {
    case today, random

    var url: URL {
        switch self {
        case .today:  return URL(string: "https://zenquotes.io/api/today")!
        case .random: return URL(string: "https://zenquotes.io/api/random")!
        }
    }
}

/// Fetches one quote from ZenQuotes. No retry, no caching. Any failure
/// (transport, non-2xx, parse) yields `nil` so the UI can show `—`.
/// No session coupling.
public struct QuoteProvider {
    private let transport: QuoteTransport

    public init(transport: QuoteTransport = URLSession.shared) {
        self.transport = transport
    }

    /// ZenQuotes returns a JSON array: `[{"q": text, "a": author, ...}]`.
    public static func parse(_ data: Data) -> Quote? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let q = first["q"] as? String,
              let a = first["a"] as? String else { return nil }
        return Quote(text: q, author: a)
    }

    public func fetchQuote(_ endpoint: QuoteEndpoint = .today) async -> Quote? {
        var req = URLRequest(url: endpoint.url)
        req.timeoutInterval = 10
        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport.get(req)
        } catch {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        return Self.parse(data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter QuoteProviderTests`
Expected: PASS (all six).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/QuoteProvider.swift Tests/AignalsCoreTests/QuoteProviderTests.swift
git commit -m "feat(core): QuoteProvider — ZenQuotes fetch behind a transport seam"
```

---

### Task 5: `MidnightRefresher` — injected-clock midnight trigger

**Files:**
- Create: `Sources/AignalsCore/MidnightRefresher.swift`
- Test: `Tests/AignalsCoreTests/MidnightRefresherTests.swift`

**Interfaces:**
- Produces:
  - `public struct MidnightRefresher`
  - `public static func nextMidnight(after date: Date, calendar: Calendar) -> Date` — the next local 00:00 strictly after `date`.
  - `public static func didCrossMidnight(from last: Date, to now: Date, calendar: Calendar) -> Bool` — true iff `last` and `now` fall on different calendar days.

Rationale: the App layer polls on its existing 1-second `MenuContent` timer (or a lightweight `Timer`), asking `didCrossMidnight(from: lastQuoteFetch, to: now)`. Keeping the decision a pure static makes it unit-testable without a live timer. `nextMidnight` is exposed for a future precise scheduler but the crossing check is what the UI uses.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class MidnightRefresherTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func test_didCrossMidnight_true_across_days() {
        // 23:30 EST -> 00:15 EST next day (in UTC these are 04:30Z and 05:15Z)
        let last = date("2026-07-01T23:30:00-04:00")
        let now  = date("2026-07-02T00:15:00-04:00")
        XCTAssertTrue(MidnightRefresher.didCrossMidnight(from: last, to: now, calendar: cal))
    }

    func test_didCrossMidnight_false_same_day() {
        let last = date("2026-07-01T09:00:00-04:00")
        let now  = date("2026-07-01T17:00:00-04:00")
        XCTAssertFalse(MidnightRefresher.didCrossMidnight(from: last, to: now, calendar: cal))
    }

    func test_nextMidnight_is_strictly_after_and_at_00() {
        let now = date("2026-07-01T09:00:00-04:00")
        let next = MidnightRefresher.nextMidnight(after: now, calendar: cal)
        let comps = cal.dateComponents([.hour, .minute, .second], from: next)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertTrue(next > now)
        // Same calendar day's midnight would be in the past, so it must be the NEXT day.
        XCTAssertEqual(cal.dateComponents([.day], from: next).day, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MidnightRefresherTests`
Expected: FAIL — `cannot find 'MidnightRefresher' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Pure helpers for "did we cross local midnight?" so the daily-quote refresh
/// can be driven off the UI's existing tick without a live timer in tests.
/// No session coupling.
public struct MidnightRefresher {
    /// The next local 00:00 strictly after `date`.
    public static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    /// True iff `last` and `now` fall on different calendar days (local time).
    public static func didCrossMidnight(from last: Date, to now: Date, calendar: Calendar) -> Bool {
        !calendar.isDate(last, inSameDayAs: now)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MidnightRefresherTests`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/MidnightRefresher.swift Tests/AignalsCoreTests/MidnightRefresherTests.swift
git commit -m "feat(core): MidnightRefresher — pure midnight-crossing helpers"
```

---

### Task 6: Truncation helper

**Files:**
- Create: `Sources/AignalsCore/QuoteTruncation.swift`
- Test: `Tests/AignalsCoreTests/QuoteTruncationTests.swift`

**Interfaces:**
- Produces: `public enum QuoteTruncation { public static func truncate(_ text: String, to limit: Int) -> String }` — returns `text` unchanged if `count <= limit`, else the first `limit` characters + `…`. `limit <= 0` returns just `…`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AignalsCore

final class QuoteTruncationTests: XCTestCase {
    func test_short_text_unchanged() {
        XCTAssertEqual(QuoteTruncation.truncate("hi", to: 40), "hi")
    }
    func test_exact_length_unchanged() {
        XCTAssertEqual(QuoteTruncation.truncate("abcde", to: 5), "abcde")
    }
    func test_long_text_truncated_with_ellipsis() {
        XCTAssertEqual(QuoteTruncation.truncate("abcdef", to: 5), "abcde…")
    }
    func test_zero_limit_is_just_ellipsis() {
        XCTAssertEqual(QuoteTruncation.truncate("abc", to: 0), "…")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter QuoteTruncationTests`
Expected: FAIL — `cannot find 'QuoteTruncation' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Truncates menubar quote text to a character budget, adding `…` when cut.
public enum QuoteTruncation {
    public static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "…" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter QuoteTruncationTests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/QuoteTruncation.swift Tests/AignalsCoreTests/QuoteTruncationTests.swift
git commit -m "feat(core): QuoteTruncation helper"
```

---

### Task 7: Config fields for the menubar quote

**Files:**
- Modify: `Sources/AignalsCore/ConfigStore.swift`
- Test: `Tests/AignalsCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: existing `AignalsConfig`.
- Produces: two new stored properties `public var quoteEnabled: Bool` (default `true`) and `public var quoteTruncation: Int` (default `40`), both back-compat via `decodeIfPresent`.

- [ ] **Step 1: Write the failing test** (append to `ConfigStoreTests.swift`)

```swift
func test_quote_defaults_when_absent_from_json() throws {
    // JSON from before this feature — no quote keys.
    let json = Data(#"{"launchAtLogin":false,"dismissedInstallPrompt":false}"#.utf8)
    let cfg = try JSONDecoder().decode(AignalsConfig.self, from: json)
    XCTAssertTrue(cfg.quoteEnabled)
    XCTAssertEqual(cfg.quoteTruncation, 40)
}

func test_quote_fields_roundtrip() throws {
    var cfg = AignalsConfig.default
    cfg.quoteEnabled = false
    cfg.quoteTruncation = 25
    let data = try JSONEncoder().encode(cfg)
    let back = try JSONDecoder().decode(AignalsConfig.self, from: data)
    XCTAssertFalse(back.quoteEnabled)
    XCTAssertEqual(back.quoteTruncation, 25)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL — `value of type 'AignalsConfig' has no member 'quoteEnabled'`.

- [ ] **Step 3: Write minimal implementation** — edit `AignalsConfig`:

  1. Add stored properties after `feishuKeyword`:
```swift
    /// Show the daily quote text next to the menubar icon. Decodes to `true`
    /// when absent so existing config.json shows the quote after upgrade.
    public var quoteEnabled: Bool
    /// Character budget for the menubar quote before truncation. Decodes to 40.
    public var quoteTruncation: Int
```
  2. Add to the `init` signature (before the closing paren) and body:
```swift
        // signature params:
        quoteEnabled: Bool = true, quoteTruncation: Int = 40
        // body:
        self.quoteEnabled = quoteEnabled
        self.quoteTruncation = quoteTruncation
```
  3. Add to `CodingKeys`:
```swift
        case quoteEnabled
        case quoteTruncation
```
  4. Add to `init(from:)`:
```swift
        self.quoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .quoteEnabled) ?? true
        self.quoteTruncation = try container.decodeIfPresent(Int.self, forKey: .quoteTruncation) ?? 40
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AignalsCore/ConfigStore.swift Tests/AignalsCoreTests/ConfigStoreTests.swift
git commit -m "feat(core): AignalsConfig.quoteEnabled + quoteTruncation (back-compat)"
```

---

### Task 8: `uninstall(keepSavedData:)` — preserve quotes.json

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift:447-456`
- Test: `Tests/AignalsCoreTests/PathsTests.swift` (a pure helper is added to Core so it is unit-testable; the App method delegates to it)

Because `AppViewModel.uninstall()` is in the (untested) App target, extract the file-preservation logic into a pure, testable Core helper and have `uninstall` call it.

**Interfaces:**
- Produces (in Core): `public enum HomeWipe { public static func wipe(home: URL, keeping keepFilenames: [String], fileManager: FileManager) }` — deletes `home` but preserves the named top-level files by moving them aside and restoring them into a recreated `home`.
- Consumes (in App): `paths.home`, `HomeWipe.wipe`.

- [ ] **Step 1: Write the failing test** — create `Tests/AignalsCoreTests/HomeWipeTests.swift`

```swift
import XCTest
@testable import AignalsCore

final class HomeWipeTests: XCTestCase {
    private func tempHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
    }

    func test_wipe_keeping_preserves_named_file_and_removes_rest() throws {
        let fm = FileManager.default
        let home = tempHome()
        try fm.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: home.appendingPathComponent("quotes.json"))
        try Data("gone".utf8).write(to: home.appendingPathComponent("config.json"))

        HomeWipe.wipe(home: home, keeping: ["quotes.json"], fileManager: fm)

        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("quotes.json").path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("config.json").path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("sessions").path))
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("quotes.json")), "keep")
    }

    func test_wipe_keeping_nothing_removes_home() {
        let fm = FileManager.default
        let home = tempHome()
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: home.appendingPathComponent("quotes.json"))

        HomeWipe.wipe(home: home, keeping: [], fileManager: fm)

        XCTAssertFalse(fm.fileExists(atPath: home.path))
    }

    func test_wipe_keeping_missing_file_is_safe() {
        let fm = FileManager.default
        let home = tempHome()
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)

        HomeWipe.wipe(home: home, keeping: ["quotes.json"], fileManager: fm)

        // Nothing to keep existed; home is gone.
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("config.json").path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HomeWipeTests`
Expected: FAIL — `cannot find 'HomeWipe' in scope`.

- [ ] **Step 3: Write minimal implementation** — create `Sources/AignalsCore/HomeWipe.swift`

```swift
import Foundation

/// Deletes the `~/.aignals` data dir during uninstall, optionally preserving
/// named top-level files (e.g. `quotes.json`) so the user can keep saved data.
/// Preserved files are moved to a sibling temp dir, `home` is removed, then a
/// fresh `home` is recreated and the kept files restored. All best-effort.
public enum HomeWipe {
    public static func wipe(home: URL, keeping keepFilenames: [String], fileManager fm: FileManager) {
        // Collect the kept files that actually exist.
        let present = keepFilenames
            .map { home.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }

        guard !present.isEmpty else {
            try? fm.removeItem(at: home)
            return
        }

        let stash = home.deletingLastPathComponent()
            .appendingPathComponent(".aignals-keep-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: stash, withIntermediateDirectories: true)
        for file in present {
            try? fm.moveItem(at: file, to: stash.appendingPathComponent(file.lastPathComponent))
        }

        try? fm.removeItem(at: home)
        try? fm.createDirectory(at: home, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        for file in present {
            let from = stash.appendingPathComponent(file.lastPathComponent)
            try? fm.moveItem(at: from, to: home.appendingPathComponent(file.lastPathComponent))
        }
        try? fm.removeItem(at: stash)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HomeWipeTests`
Expected: PASS (all three).

- [ ] **Step 5: Wire the App method** — replace the data-dir wipe in `AppViewModel.uninstall()` (`App/Aignals/Sources/AppViewModel.swift`). Change the signature and the wipe line:

```swift
    func uninstall(keepSavedData: Bool = false) throws {
        try HookInstaller().uninstall(from: claudeSettingsURL)
        if FileManager.default.fileExists(atPath: hookSymlinkURL.path) {
            try? FileManager.default.removeItem(at: hookSymlinkURL)
        }
        // Wipe ~/.aignals, optionally preserving saved data (quotes.json, and
        // future worklog.json). Best-effort.
        HomeWipe.wipe(home: paths.home,
                      keeping: keepSavedData ? ["quotes.json", "worklog.json"] : [],
                      fileManager: .default)
        installVersion &+= 1
    }
```

- [ ] **Step 6: Build the app target to confirm it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/AignalsCore/HomeWipe.swift Tests/AignalsCoreTests/HomeWipeTests.swift App/Aignals/Sources/AppViewModel.swift
git commit -m "feat: uninstall(keepSavedData:) preserves quotes.json via HomeWipe"
```

---

### Task 9: `AppViewModel` quote coordination

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

No new unit test (App target isn't unit-tested; logic pieces are already covered by Core tests). Verified by building + the manual checklist in Task 13.

**Interfaces:**
- Consumes: `QuoteProvider`, `QuoteStore`, `MidnightRefresher`, `QuoteTruncation`, `Quote`, config `quoteEnabled`/`quoteTruncation`.
- Produces on `AppViewModel`:
  - `var currentQuote: Quote?` (observable) — nil ⇒ show `—`.
  - `var isFetchingQuote: Bool` (observable) — refresh spinner.
  - `private(set) var lastQuoteFetch: Date?`
  - `func refreshQuote(endpoint: QuoteEndpoint)` — sets fetching, calls provider, stores result (or leaves `currentQuote` and shows `—` on nil), records `lastQuoteFetch`.
  - `func fetchQuoteIfNeeded(now: Date)` — fetch on first launch or when `didCrossMidnight(from: lastQuoteFetch, to: now)`.
  - `var menubarQuoteText: String?` — `nil` when `!config.quoteEnabled`; else `QuoteTruncation.truncate(currentQuote?.text ?? "—", to: config.quoteTruncation)`.
  - `var quoteEnabled: Bool` / `var quoteTruncation: Int` — get/set through config (mirror `soundEnabled`/`theme` pattern).
  - Saved-quote passthrough: `var savedQuotes: [SavedQuote]`, `func saveCurrentQuote()`, `func deleteSavedQuote(text:)`, `func isCurrentQuoteSaved() -> Bool`.

- [ ] **Step 1: Add stored deps + observable state** — near the other stored properties in `AppViewModel` (e.g. beside `configStore`/`store`), add:

```swift
    private let quoteProvider = QuoteProvider()
    private let quoteStore: QuoteStore
    private let quoteCalendar = Calendar.current

    var currentQuote: Quote?
    var isFetchingQuote = false
    private(set) var lastQuoteFetch: Date?
```

Initialize `quoteStore` in `init` where `paths` is available (alongside the other `paths`-based stores):

```swift
        self.quoteStore = QuoteStore(paths: paths)
```

- [ ] **Step 2: Add the fetch/refresh methods** — add in an `extension AppViewModel`:

```swift
extension AppViewModel {
    /// Fetch on first launch or after crossing local midnight since the last fetch.
    func fetchQuoteIfNeeded(now: Date = Date()) {
        if let last = lastQuoteFetch,
           !MidnightRefresher.didCrossMidnight(from: last, to: now, calendar: quoteCalendar) {
            return
        }
        refreshQuote(endpoint: .today)
    }

    /// Fetch a quote (⟳ uses `.random`, launch/midnight use `.today`). On failure
    /// leaves `currentQuote` = nil so the UI shows `—`.
    func refreshQuote(endpoint: QuoteEndpoint = .random) {
        isFetchingQuote = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let q = await self.quoteProvider.fetchQuote(endpoint)
            self.currentQuote = q            // nil ⇒ show “—”
            self.lastQuoteFetch = Date()
            self.isFetchingQuote = false
        }
    }

    /// Truncated text for the menubar label; nil when the user disabled the quote.
    var menubarQuoteText: String? {
        guard config.quoteEnabled else { return nil }
        let full = currentQuote?.text ?? "—"
        return QuoteTruncation.truncate(full, to: config.quoteTruncation)
    }

    var quoteEnabled: Bool {
        get { config.quoteEnabled }
        set { var c = config; c.quoteEnabled = newValue; config = c }
    }
    var quoteTruncation: Int {
        get { config.quoteTruncation }
        set { var c = config; c.quoteTruncation = max(1, newValue); config = c }
    }

    // Saved-quote passthrough to QuoteStore.
    var savedQuotes: [SavedQuote] { quoteStore.saved }
    func isCurrentQuoteSaved() -> Bool {
        guard let q = currentQuote else { return false }
        return quoteStore.isSaved(q.text)
    }
    func saveCurrentQuote() {
        guard let q = currentQuote else { return }   // no-op on “—”
        quoteStore.save(q, at: Date())
    }
    func deleteSavedQuote(text: String) {
        quoteStore.delete(text: text)
    }
}
```

- [ ] **Step 3: Kick off the first fetch at startup** — in `init` after the existing setup (e.g. after `seedFeishuDrafts()`), add:

```swift
        fetchQuoteIfNeeded()
```

- [ ] **Step 4: Build to confirm it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): AppViewModel quote coordination (fetch/refresh/save)"
```

---

### Task 9.5: `sendCurrentQuoteToFeishu()` — reusable push (no UI)

**Files:**
- Modify: `App/Aignals/Sources/AppViewModel.swift`

**No UI is added.** This task only builds the reusable architecture: a method that pushes today's quote to the already-configured Feishu bot, gated properly, so a future stopwatch `start` can call it. There is NO button and NO current call site.

**Interfaces:**
- Consumes: existing `sendFeishu(text:)` (`AppViewModel.swift:574`), `config.feishuEnabled`, `config.feishuWebhookURL`, `currentQuote`.
- Produces on `AppViewModel`: `func sendCurrentQuoteToFeishu()` — no-op unless Feishu is enabled + configured AND a real quote exists; otherwise delegates to `sendFeishu`.

- [ ] **Step 1: Add the method** — in the Feishu `extension AppViewModel` (near `sendFeishu`), add:

```swift
    /// Push today's quote to the configured Feishu bot, reusing the same tokens
    /// as session notifications. Gated: no-op when Feishu is disabled/unconfigured
    /// or when there is no real quote (currentQuote == nil ⇒ “—”). No UI entry
    /// point yet — this is the reusable hook a future stopwatch `start` calls.
    func sendCurrentQuoteToFeishu() {
        guard config.feishuEnabled, !config.feishuWebhookURL.isEmpty else { return }
        guard let quote = currentQuote else { return }   // no “—”
        let author = quote.author.isEmpty ? "" : " — \(quote.author)"
        sendFeishu(text: "\(quote.text)\(author)")
    }
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/AppViewModel.swift
git commit -m "feat(app): sendCurrentQuoteToFeishu() reusable push (no UI, for stopwatch start)"
```

---

### Task 10: Menubar label shows the quote

**Files:**
- Modify: `App/Aignals/Sources/AignalsApp.swift`

**Interfaces:**
- Consumes: `vm.menubarQuoteText`, `vm.currentQuote`, `vm.fetchQuoteIfNeeded`.

- [ ] **Step 1: Add quote text to the `MenuBarExtra` label** — replace the `label:` closure so it shows icon + optional truncated text with a full-text tooltip:

```swift
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: StatusIcon.image(for: vm.store.statusCounts, hasError: vm.store.hasError))
                if let text = vm.menubarQuoteText {
                    Text(text)
                        .help(vm.currentQuote?.text ?? "—")
                }
            }
        }
```

- [ ] **Step 2: Poll for midnight crossing** — add a `.task` timer on the scene content so a day change refreshes the quote. Attach to `MenuContent` in the content closure:

```swift
        MenuBarExtra {
            MenuContent(vm: vm)
                .task {
                    // Re-check on a coarse interval; fetchQuoteIfNeeded is a no-op
                    // until local midnight is crossed.
                    while !Task.isCancelled {
                        vm.fetchQuoteIfNeeded()
                        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                    }
                }
        } label: { … }
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/Aignals/Sources/AignalsApp.swift
git commit -m "feat(app): menubar label shows truncated daily quote + midnight poll"
```

---

### Task 11: Dropdown top row — full quote + refresh/save/projector

**Files:**
- Modify: `App/Aignals/Sources/MenuContent.swift`

**Interfaces:**
- Consumes: `vm.currentQuote`, `vm.isFetchingQuote`, `vm.refreshQuote`, `vm.saveCurrentQuote`, `vm.isCurrentQuoteSaved`, `vm.savedQuotes`, `vm.deleteSavedQuote`. Uses `@State private var showProjector = false`.

- [ ] **Step 1: Add a `quoteRow` view** — add to `MenuContent`:

```swift
    @State private var showProjector = false

    @ViewBuilder
    private var quoteRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.currentQuote?.text ?? "—")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let author = vm.currentQuote?.author, !author.isEmpty {
                Text("— \(author)").font(.caption).foregroundStyle(style.textSecondary)
            }
            HStack(spacing: 12) {
                Button { vm.refreshQuote(endpoint: .random) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isFetchingQuote)
                .help("Refresh quote")

                Button { vm.saveCurrentQuote() } label: {
                    Image(systemName: vm.isCurrentQuoteSaved() ? "heart.fill" : "heart")
                }
                .disabled(vm.currentQuote == nil)        // disabled on “—”
                .help("Save quote")

                Button { showProjector = true } label: {
                    Image(systemName: "book")
                }
                .help("Saved quotes")

                if vm.isFetchingQuote { ProgressView().controlSize(.small) }
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
```

- [ ] **Step 2: Insert `quoteRow` at the top of the panel body** — in `body`, add it as the first child of the outer `VStack`, before `header`:

```swift
        VStack(alignment: .leading, spacing: 0) {
            quoteRow
            Divider().background(style.hairline)
            header
            …
```

- [ ] **Step 3: Present the projector sheet** — add a `.sheet` modifier on the outer `VStack` (Task 12 defines `ProjectorView`):

```swift
        .sheet(isPresented: $showProjector) {
            ProjectorView(vm: vm)
        }
```

- [ ] **Step 4: Build to confirm it compiles** (will fail until Task 12 adds `ProjectorView` — acceptable; do Task 12 next, then build)

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: build fails with `cannot find 'ProjectorView'` — proceed to Task 12.

- [ ] **Step 5: Commit** (after Task 12 builds green — commit both together there). Skip committing here.

---

### Task 12: Projector list view

**Files:**
- Create: `App/Aignals/Sources/ProjectorView.swift`

**Interfaces:**
- Consumes: `vm.savedQuotes` (`[SavedQuote]`, newest-first), `vm.deleteSavedQuote(text:)`.

- [ ] **Step 1: Create `ProjectorView`**

```swift
import SwiftUI
import AignalsCore

/// A list of saved quotes shown as a sheet from the dropdown's 📖 button.
/// Each row shows text + author + saved time and can be deleted. No session
/// coupling.
@MainActor
struct ProjectorView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Quotes").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(12)
            Divider()

            if vm.savedQuotes.isEmpty {
                Text("No saved quotes yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List {
                    ForEach(vm.savedQuotes, id: \.text) { q in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.text)
                            HStack {
                                if !q.author.isEmpty {
                                    Text("— \(q.author)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Self.dateFormat.string(from: q.savedAt))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            Button(role: .destructive) {
                                vm.deleteSavedQuote(text: q.text)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 420)
    }
}
```

- [ ] **Step 2: Build to confirm it compiles** (Tasks 11 + 12 together now)

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

> If the build reports `ProjectorView.swift` is not in the target, add it to the Xcode project's `Aignals` target membership (the other `App/Aignals/Sources/*.swift` files show the pattern) and rebuild.

- [ ] **Step 3: Commit** (Tasks 11 + 12)

```bash
git add App/Aignals/Sources/MenuContent.swift App/Aignals/Sources/ProjectorView.swift
git commit -m "feat(app): dropdown quote row (refresh/save) + projector list"
```

---

### Task 13: Settings "Daily Quote" card

**Files:**
- Modify: `App/Aignals/Sources/SettingsView.swift`

**Interfaces:**
- Consumes: `vm.quoteEnabled`, `vm.quoteTruncation`.

- [ ] **Step 1: Add a Daily Quote card in the Customization group** — following the existing Sounds/Feishu card pattern, add a section:

```swift
            Section("Daily Quote") {
                Toggle("Show quote in menu bar", isOn: Binding(
                    get: { vm.quoteEnabled },
                    set: { vm.quoteEnabled = $0 }
                ))
                Stepper(value: Binding(
                    get: { vm.quoteTruncation },
                    set: { vm.quoteTruncation = $0 }
                ), in: 20...80, step: 5) {
                    Text("Truncate at \(vm.quoteTruncation) characters")
                }
                .disabled(!vm.quoteEnabled)
            }
```

> Match the surrounding layout: if the Customization pane uses `Form`/`Section`, place this alongside the Sounds and Feishu sections; if it uses the custom `groupCard` helper, mirror that instead. Read the file's Customization region first and follow whichever pattern is present.

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/SettingsView.swift
git commit -m "feat(app): Settings Daily Quote card (toggle + truncation)"
```

---

### Task 14: Uninstall dialog — "Keep my saved data" checkbox

**Files:**
- Modify: `App/Aignals/Sources/SettingsView.swift:215-235` (`runUninstall`)

**Interfaces:**
- Consumes: `vm.uninstall(keepSavedData:)` (Task 8).

- [ ] **Step 1: Add an accessory checkbox to the confirm alert** — replace the body of `runUninstall()` so the alert carries a checkbox and passes its state:

```swift
    private func runUninstall() {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall Aignals?"
        confirm.informativeText = "This removes its Claude Code hooks, the aignals-hook CLI link, and all data in ~/.aignals. Aignals.app itself you'll drag to the Trash."
        confirm.alertStyle = .warning

        let keep = NSButton(checkboxWithTitle: "Keep my saved data (work log & quotes)", target: nil, action: nil)
        keep.state = .off
        confirm.accessoryView = keep

        confirm.addButton(withTitle: "Cancel")
        let uninstallButton = confirm.addButton(withTitle: "Uninstall")
        if #available(macOS 11.0, *) {
            uninstallButton.hasDestructiveAction = true
        }
        guard confirm.runModal() == .alertSecondButtonReturn else { return }
        do {
            try vm.uninstall(keepSavedData: keep.state == .on)
            Self.alert("Aignals uninstalled",
                       informative: "Aignals uninstalled — drag Aignals.app to the Trash to finish.")
            NSApplication.shared.terminate(nil)
        } catch {
            Self.alert("Couldn't uninstall",
                       informative: "Aignals was not fully uninstalled. Error: \(error)")
        }
    }
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Aignals/Sources/SettingsView.swift
git commit -m "feat(app): uninstall dialog keep-saved-data checkbox"
```

---

### Task 15: Full test pass + manual checklist + docs

**Files:**
- Modify: `README.md` (uninstall section), `docs/superpowers/specs/manual-test-checklist.md`

- [ ] **Step 1: Run the whole Core suite**

Run: `swift test 2>&1 | tail -15`
Expected: all tests pass, including the new `QuoteTests`, `QuoteStoreTests`, `QuoteProviderTests`, `MidnightRefresherTests`, `QuoteTruncationTests`, `HomeWipeTests`, and the updated `PathsTests`/`ConfigStoreTests`.

- [ ] **Step 2: Build the app**

Run: `xcodebuild -project App/Aignals/Aignals.xcodeproj -scheme Aignals -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual integration checklist** (run the app; verify each):
  - [ ] Menu bar shows the traffic-light icon **plus** a truncated quote; hovering shows the full text tooltip.
  - [ ] Opening the dropdown shows the full quote + author at top with ⟳ / ♥ / 📖 buttons.
  - [ ] ⟳ refresh fetches a new quote (spinner shows briefly).
  - [ ] ♥ save stores the current quote; the heart fills; saving the same quote again does nothing (dedup).
  - [ ] 📖 opens the projector list; saved quotes appear newest-first with saved time; swipe-delete removes one.
  - [ ] With no network, the quote shows `—` and ♥ save is disabled.
  - [ ] Settings → Daily Quote: toggling off hides the menubar quote text (icon only); changing truncation length shortens/lengthens it.
  - [ ] `~/.aignals/quotes.json` exists after saving and contains `{"version":1,"quotes":[…]}`.
  - [ ] Settings → Uninstall with **"Keep my saved data"** checked, then reinstall/relaunch: `~/.aignals/quotes.json` was preserved. With it unchecked, `~/.aignals` is fully removed.

- [ ] **Step 4: Update docs** — in `README.md`, update the Uninstall section to mention the "Keep my saved data (work log & quotes)" option and that `~/.aignals/quotes.json` holds saved quotes. Add the corresponding rows to `docs/superpowers/specs/manual-test-checklist.md`.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/specs/manual-test-checklist.md
git commit -m "docs: daily quote — uninstall keep-data note + manual checklist"
```

---

## Notes for the implementer

- Run `swift test` for all Core tasks (1–8). The App target (Tasks 9–14) is verified by `xcodebuild … build` + the Task 15 manual checklist; it has no unit tests by project convention.
- If a newly created `App/Aignals/Sources/*.swift` file isn't picked up by the build, add it to the `Aignals` target in the Xcode project (existing UI files show the membership pattern).
- Keep the hard decoupling rule in mind: nothing in the quote units may import or reference session types.

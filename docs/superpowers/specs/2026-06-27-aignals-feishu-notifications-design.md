# Feishu notifications — design spec

**Date:** 2026-06-27
**Status:** Approved, ready for implementation plan
**Target version:** v0.4.0 (notification channel #2, alongside sounds)

## Summary

Add an optional **Feishu (飞书/Lark) notification channel** to Aignals. When a Claude
Code session transitions into a state that needs the user — 🟡 `waiting_permission`
or 🟢 `waiting_input` — Aignals POSTs a text message to a user-configured **Feishu
custom-bot webhook**, in addition to (and independently of) the existing system sound.

This lets the user get pushed a message on their phone/desktop Feishu when a task
finishes or a permission prompt is blocking, without watching the menu bar.

## Goals

- Notify on the **same two transitions** as sounds: 🟡 waiting-permission, 🟢 waiting-input.
- Configured **independently** of sound (Feishu can be on with sound off, or vice versa).
- Reuse the existing per-session **mute** and per-session **throttle** so the two
  channels never disagree about "leave this session alone" or double-fire.
- **Zero third-party dependencies** — Feishu custom bots are a plain HTTP webhook;
  `URLSession` + `CryptoKit` cover the POST and optional HMAC signing.
- Surface send **failures in the Settings UI** so a misconfigured webhook is visible.

## Non-goals (YAGNI)

- No retry queue / backoff / persistence of failed sends (best-effort fire-and-forget).
- No interactive Feishu *cards* — plain `text` messages only.
- No per-state Feishu toggles (one master toggle; the per-state granularity already
  exists for sounds and isn't needed here).
- No Keychain storage — the webhook URL lives in `~/.aignals/config.json` like the
  rest of config (same trust level; personal machine).
- No notification on 🔴 `working` or ⚪️ `disconnected`.

## Background: Feishu custom-bot webhook

A Feishu/Lark **custom bot** is added to a group chat and exposes a webhook URL of the
form `https://open.feishu.cn/open-apis/bot/v2/hook/<token>` (host `open.larksuite.com`
for Lark international). Pushing a message is a single HTTP POST — no app review, no
OAuth, no SDK.

**Text message body:**
```json
{ "msg_type": "text", "content": { "text": "request example" } }
```

**Success response:** `{ "code": 0, "msg": "success", "data": {} }`. A non-zero `code`
means Feishu rejected the request (e.g. `19021` = bad signature / stale timestamp).

**Optional signature** (when the bot has "signature verification" enabled): add two
fields to the body —
```json
{ "timestamp": "1599360473", "sign": "…", "msg_type": "text", "content": { … } }
```
where `timestamp` is the current Unix seconds (must be within 1 hour of Feishu's clock)
and `sign = Base64( HMAC-SHA256( key = "<timestamp>\n<secret>", data = <empty bytes> ) )`.

**Three optional bot security modes** (the user picks one when creating the bot):
*custom keywords*, *IP whitelist*, or *signature*. We only build in support for
**signature** (the `feishuSecret` field) because the others need no client code — BUT
they constrain our message:
- **Custom keywords:** Feishu drops any message not containing one of the configured
  keywords. Our messages always begin with the literal `Aignals`, so a user on keyword
  mode just sets a keyword of `Aignals` and every message passes. This is documented in
  the user-facing setup guide so a keyword-mode user isn't silently dropped.
- **IP whitelist:** sends originate from the user's own machine IP; nothing we can set in
  the app. Out of scope — the user manages it on Feishu's side.

Sources:
- https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot

## Architecture

### Where it hooks in

The trigger is the **existing diff loop** in `AppViewModel`, today named
`handleSessionSounds()` and driven off `store.changes`. That loop already:

- walks `store.sessions`,
- compares each session's state to `lastKnownState[id]`,
- classifies first-observation (seed/adoption → silent) vs. a real transition,
- updates the baseline for the next diff.

We add the Feishu send **next to** the sound play in that same single pass. The method
is renamed `handleSessionAlerts()` since it now drives two alert channels off one diff.

```
store.changes  ──▶  handleSessionAlerts()  ──┬──▶ play(sound)            [existing]
   (one diff pass over sessions)             │     gated by soundEnabled
                                             │
                                             └──▶ FeishuNotifier.notify(…)  [new]
                                                   gated by feishuEnabled + URL set
                                                      │ build text
                                                      ▼  FeishuClient.send (async POST)
                                                      ▼  result → lastFeishuError (UI)
```

### Components

All notification logic lives in `AignalsCore` (pure/testable); the App target only owns
the wiring and SwiftUI.

**`FeishuMessage`** (`Sources/AignalsCore/FeishuMessage.swift`)
- Pure function: `static func text(displayName: String, state: SessionState, keyword: String = "") -> String?`
- Returns `nil` for non-notifying states (working/disconnected) — mirrors
  `sound(forTransitionInto:)`.
- Format: `Aignals • <displayName>: <emoji> <state phrase> — <action>`, e.g.
  - 🟡 → `Aignals • my-project: 🟡 waiting for permission — go click Allow`
  - 🟢 → `Aignals • my-project: 🟢 finished — your turn`
- Takes `displayName` as a param so the view-model can pass `displayName(for:)`
  (honors renames).
- **Keyword guarantee:** if `keyword` is non-empty and the built text does NOT already
  contain it (case-sensitive, Feishu's match is literal-substring), append ` [<keyword>]`
  so a keyword-mode bot accepts the message. Since every message already begins with the
  literal `Aignals`, a keyword of `Aignals` is satisfied for free and nothing is
  appended — the append only kicks in for a non-`Aignals` keyword. This keeps the
  keyword-passing logic pure and unit-tested rather than implicit in the wording.

**`FeishuClient`** (`Sources/AignalsCore/FeishuClient.swift`)
- `func send(text: String, to webhookURL: String, secret: String) async -> Result<Void, FeishuError>`
- Builds the JSON body; when `secret` is non-empty, adds `timestamp` + `sign`
  (HMAC-SHA256 via CryptoKit, per the spec above).
- POSTs via an injected `URLSession` (default `.shared`) so tests can mock transport.
- Maps outcomes:
  - transport error → `.failure(.transport(message))`
  - HTTP non-2xx → `.failure(.http(status))`
  - body `code != 0` → `.failure(.feishu(code, msg))` (e.g. 19021)
  - `code == 0` → `.success`
- `enum FeishuError` carries a short human string for the UI.
- A `timestamp` provider is injectable (closure returning Unix seconds) so the sign
  computation is deterministically unit-testable.

**`FeishuNotifier`** (App target, `App/Aignals/Sources/` — or a thin method on the
view-model)
- Owns the gating decision + reports the `Result` back to `AppViewModel` for the UI.
- Fires the async `send` as a detached `Task` (fire-and-forget); on completion sets
  `lastFeishuError` on the main actor.

### Config

Four new fields on `AignalsConfig`, all `decodeIfPresent` with defaults so existing
`config.json` upgrades cleanly (identical pattern to `soundEnabled`/`theme`):

```swift
public var feishuEnabled: Bool       // default false
public var feishuWebhookURL: String  // default ""
public var feishuSecret: String      // default "" (optional signing)
public var feishuKeyword: String     // default "" (optional keyword-mode passphrase)
```

`feishuSecret` and `feishuKeyword` are independent optional security modes (a bot uses
one of them, or neither) — both may be empty. Update `init`, `default`, `CodingKeys`,
and the custom `init(from:)`. All three string fields are user-entered and persisted to
`~/.aignals/config.json` via the existing `ConfigStore.save`.

### Gating (mirrors sound, INV parity)

A Feishu message fires only when ALL hold (parallel to the sound gate):
1. new state is `.waitingPermission` or `.waitingInput`; AND
2. the session was already **known** in `lastKnownState` (first observation is silent); AND
3. the state actually **changed**; AND
4. `config.feishuEnabled`; AND
5. `config.feishuWebhookURL` is non-empty; AND
6. the session is **not per-row muted**; AND
7. the per-session **throttle** allows it.

**Throttle:** the existing `lastSoundAt: [String: Date]` (3s per-session) is generalized
to `lastAlertAt` and shared by both channels, so a single transition cannot double-fire
across sound + Feishu, and rapid flapping is throttled per session for both.

> Note: the throttle is shared, so if a session sounds AND Feishu-sends on the same
> transition, both fire for that one transition (same diff pass, same `now`). The
> throttle prevents a *second* transition's alerts within the window — matching today's
> sound behavior.

**Control-flow refactor (implementation-critical, easy to get wrong).** Today the throttle
timestamp is written *inside* the sound branch — `lastSoundAt[id] = now` only runs after
`guard soundOn` passes and a sound actually plays. Sharing the throttle means it must move
*out* of any single channel. The per-session loop body must become:

1. Compute the diff (known? changed? into 🟡/🟢? not muted?) — the **channel-independent**
   gate. If it fails, `continue` without touching `lastAlertAt`.
2. Decide per channel whether it *wants* to fire this transition:
   `wantsSound = soundEnabled && sound(forState) != nil`,
   `wantsFeishu = feishuEnabled && !feishuWebhookURL.isEmpty`.
3. If neither wants to fire, `continue`.
4. Apply the **shared** throttle once: if `lastAlertAt[id]` is within 3s, `continue`;
   otherwise set `lastAlertAt[id] = now`.
5. Then fire each wanting channel (`play(...)` and/or `FeishuNotifier.notify(...)`).

This ordering is the whole reason the channels stay consistent: a session that is sound-off
but Feishu-on must still reach the throttle/send step, which the *old* `guard soundOn else
{ continue }` placement would have skipped. The implementation plan MUST restructure this
loop rather than bolt a second `if` after the existing sound code.

## Failure handling & UI

`AppViewModel` gains:
```swift
private(set) var lastFeishuError: String?   // @Observable, set on @MainActor
```
- Success clears it to `nil`; failure sets a short string
  (`"Send failed: offline"`, `"Feishu rejected: bad signature (19021)"`, …).

**Settings additions** (in the existing expandable Settings section of `MenuContent`):
- A **"Feishu notifications"** toggle (`feishuEnabled`).
- When enabled, three text fields (each bound to its config string, persisted on edit):
  - **Webhook URL** (`feishuWebhookURL`) — required; the send is gated on it being non-empty.
  - **Secret** (`feishuSecret`) — optional; only needed for signature-mode bots.
  - **Keyword** (`feishuKeyword`) — optional; only needed for keyword-mode bots. A short
    helper line clarifies "leave blank unless your bot uses keyword security".
- A **"Send test"** button → calls `FeishuClient.send` with a fixed sample text
  (`Aignals • test — notifications are working`, kept `Aignals`-prefixed) passed through
  the same `FeishuMessage` keyword-append so it also passes keyword-mode bots; lets the
  user verify URL/secret/keyword without waiting for a real transition. Its result feeds
  the same `lastFeishuError`.
- When `lastFeishuError != nil`: a one-line **red warning** under the toggle — same
  visual treatment as the existing "hooks not installed" reminder.

Send is fire-and-forget `Task`; no retries, no queue.

## Testing

Pure/core logic is unit-tested in `Tests/AignalsCoreTests`; no real network.

- **`FeishuMessageTests`** — text for 🟡 and 🟢; `nil` for working/disconnected;
  rename honored (displayName param); action suffix correct; **keyword logic**: empty
  keyword appends nothing; keyword already present (e.g. `Aignals`) appends nothing;
  a novel keyword is appended as ` [<keyword>]` and the result contains it.
- **`FeishuClientTests`**
  - sign computation matches a known vector (fixed timestamp + secret →
    expected Base64), exercising the documented `"<ts>\n<secret>"` key + empty data;
  - body shape with secret (has `timestamp`/`sign`) vs. without (omits them);
  - response `{"code":0}` → `.success`; `{"code":19021,…}` → `.failure(.feishu)`;
    transport error → `.failure(.transport)`; injected mock `URLSession`.
- **Gating coverage** — extend the existing alert-diff expectations so a session that is
  muted / unknown / unchanged / feishu-disabled / has empty URL sends nothing, and the
  shared throttle blocks a rapid second transition.

## Migration / compatibility

- Existing `config.json` without the new keys decodes with Feishu off, empty URL/secret
  — no behavior change until the user opts in.
- No change to the hook protocol, session-file format, or sound behavior.

## Open items

None — defaults and behavior fully specified above.

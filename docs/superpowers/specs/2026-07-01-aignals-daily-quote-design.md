# Aignals — Daily Motivation Quote (Design)

**Date:** 2026-07-01
**Status:** Approved (brainstorming complete)
**Scope:** Standalone menubar feature. Fully independent of session monitoring — MUST NOT couple to any session logic.

## Goal

Show a daily motivation quote in the menubar. Each local midnight the quote auto-refreshes from an online API. The user can manually refresh, save (favorite) quotes, and browse saved quotes. The quote is unrelated to Claude session state and shares no code with it.

## Non-Goals

- No stopwatch (separate feature, separate spec).
- No YouTube playback (deferred).
- No long-term persistence of the *daily* quote — only *saved* quotes persist.
- No offline built-in fallback list. Fetch failure shows a placeholder.

## Architecture & Data Flow

Three new single-purpose units plus UI wiring. None of them reference session state.

### QuoteProvider (new)
- Responsibility: fetch + parse one quote from the online API; handle timeout / HTTP error.
- Public surface: `func fetchQuote() async -> Quote?` — returns `nil` on any failure (network, timeout, non-2xx, parse error).
- Source API: **ZenQuotes** (`https://zenquotes.io/api/today` for the daily; refresh may use `/api/random`). `/api/today` fits the "quote of the day" semantics.
- Timeout: reasonable request timeout (e.g. 10s); no retry.

### QuoteStore (new)
- Responsibility: hold the current in-memory daily quote + manage saved quotes on disk.
- Saved quotes file: `~/.aignals/quotes.json` (same directory as other Aignals data, sibling to future `worklog.json`).
- Operations: `save(Quote)` (dedup by `text`), `delete(Quote)`, `load()` (corrupt/missing → empty list), atomic write (same approach as existing session file writes).
- Today's quote is in-memory only — NOT persisted (each day refreshes; failure shows `—`).

### MidnightRefresher (new)
- Responsibility: fire a callback when the local clock crosses midnight.
- Testable via injected clock/timer so tests can simulate crossing 00:00 and assert it fires exactly once (no duplicate/no drift double-fire).

### UI wiring (changes to existing views)
- Menubar display (`NSStatusItem`), dropdown top row, Settings "Daily Quote" card, Projector list, Uninstall checkbox.

### Data flow
1. On app launch, if today's quote not yet fetched, call `QuoteProvider.fetchQuote()`.
2. `MidnightRefresher` fires at local midnight → fetch again.
3. Manual ⟳ refresh → same fetch path (may use `/api/random`).
4. Success → update in-memory today's quote → UI reflects it.
5. Failure → show `—` (quietly); no cache, no fallback; next success overwrites.

## Menubar Display & Settings

### Menubar bar
- Current: `NSStatusItem` shows the traffic-light icon.
- New: **icon + truncated quote text**.
- Truncation: first N characters, `…` when longer; hover tooltip shows full text.
- Default N = **40**.
- Quote text is **ON by default**.
- Quote shows regardless of session state (including zero sessions).

### Settings — "Daily Quote" card
- Lives in the **Customization** group, peer to Sounds / Feishu.
- **Toggle**: show/hide the menubar quote text (off → icon only, current behavior).
- **Truncation length**: stepper/field, range ~20–80, default 40.

## Dropdown Top Row & Projector

### Dropdown top row (above sessions list)
- One row: **full today's quote** + buttons **⟳ refresh** | **♥ save** | **📖 projector**.
- refresh: fetch a new quote (QuoteProvider); show a loading state while fetching.
- save: store current quote in `quotes.json` (dedup). Already-saved → ♥ filled/disabled ("saved").
- save is **disabled when the quote is `—`** (fetch failed — cannot save an empty quote).

### Projector (a list)
- A list of saved quotes. Clicking expands to show all saved quotes.
- Each entry: **text + author + saved time**; each can be **deleted**.
- Sort by saved time, newest first.
- Empty state: "No saved quotes yet."

## Feishu Push Hook (architecture only — no UI)

Provide a reusable method that pushes today's quote to the already-configured
Feishu bot, reusing the same tokens as session notifications. This is
**architecture only** — there is NO button and NO current call site. It exists
so a future stopwatch `start` can call it (the user's intended trigger).

- `AppViewModel.sendCurrentQuoteToFeishu()` delegates to the existing
  `sendFeishu(text:)`.
- Gated: no-op unless `config.feishuEnabled` and `feishuWebhookURL` is non-empty,
  AND `currentQuote != nil` (never sends the `—` placeholder).
- No new Core code; reuses `FeishuClient` and the existing `feishu*` config.
- No Settings change, no dropdown button.

## Persistence Format

`~/.aignals/quotes.json`:
```json
{
  "version": 1,
  "quotes": [
    {
      "text": "The best way out is always through.",
      "author": "Robert Frost",
      "savedAt": "2026-07-01T14:30:00Z"
    }
  ]
}
```
- Dedup key: `text` (same quote saved only once).
- Atomic write (consistent with existing session file writes).
- Corrupt/missing file → treated as empty list.

## Uninstall Changes

- The existing Uninstall confirmation dialog gains a checkbox: **"Keep my saved data (work log & quotes)"**.
- Checked → when deleting `~/.aignals`, **skip `quotes.json`** (and future `worklog.json`).
- Implementation: move the files-to-keep to a temp location → `removeItem(~/.aignals)` → recreate `~/.aignals` and restore the kept files.
- Default unchecked (delete everything, current behavior).

## Testing & Acceptance

Dev agent implements; an INDEPENDENT test agent verifies each gate.

### Unit tests
- **QuoteProvider**: mock the network — assert successful parse; timeout → nil; non-2xx → nil; malformed body → nil.
- **QuoteStore**: save dedup; delete; load corrupt file → empty; atomic write.
- **MidnightRefresher**: injected clock — fires once when crossing 00:00; does not double-fire.

### Manual integration checklist
- Menubar shows icon + truncated quote + tooltip full text.
- Settings toggle hides/shows menubar quote; truncation length changes take effect.
- Dropdown refresh fetches new quote; save stores it (dedup); projector lists saved quotes; delete removes one.
- Fetch failure shows `—` and save is disabled.
- Uninstall with checkbox checked preserves `quotes.json`; unchecked deletes it.

### Acceptance gate
Test agent verifies line-by-line: all unit tests green + every manual checklist item passes.

## Key Constraints

- **Decoupling (hard):** quote code shares NO logic with session monitoring. Independent provider/store/UI units.
- Follow existing patterns: `~/.aignals/` data dir, atomic writes, Settings card layout (Sounds/Feishu peer).
- YAGNI: no offline list, no daily-quote persistence, no retry.

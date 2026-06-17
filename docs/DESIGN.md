# Design & Decisions

Context and reasoning behind Claude Usage Quota, so the next person (or future us)
doesn't have to re-derive it.

## Goal

A macOS menu bar widget that, on click, shows three numbers:

1. **Time remaining** in the current 5-hour window (live countdown)
2. **5-hour usage left** (% remaining)
3. **Weekly usage left** (% remaining)

These must be the *official* numbers (the same ones `/usage` shows), not estimates.

## Data source — why the statusline bridge

We evaluated four ways to get usage data. Summary of the tradeoffs:

| Approach | Official %? | Works when CC closed? | Cost / risk |
|---|---|---|---|
| **Statusline stdin bridge** ✅ chosen | Exact | No (frozen, but countdown stays live) | Free, no creds, trivial |
| OAuth `/api/oauth/usage` | Exact | Yes | Needs Keychain token; aggressively rate-limited; undocumented |
| PTY-spawn `/usage` | Exact | Yes | Spawns a full CC process per refresh (heavy) |
| Parse `~/.claude/projects/**/*.jsonl` | Approximate | Yes | Can't know plan limits / Anthropic's accounting |

**Decision:** statusline bridge only. The user accepted "live while Claude Code is
active, frozen-but-honest when it's closed," in exchange for zero credentials and
zero API calls. The app computes the countdown itself so *that* stays live always.

### The official `rate_limits` schema (Claude Code v2.1.80+)

Claude Code passes this on stdin to the statusline command, for **Pro/Max plans
only**, and only **after the first API response in a session** (never with API keys):

```json
{ "rate_limits": {
    "five_hour": { "used_percentage": 42.5, "resets_at": 1711540800 },
    "seven_day": { "used_percentage": 15.3, "resets_at": 1712059200 }
} }
```

- Field is `seven_day`, **not** `weekly`. `resets_at` is Unix epoch **seconds**.
- The separate per-model Opus weekly limit is **not** in stdin (only via the OAuth
  API), so it is out of scope here. "Weekly" = the all-model `seven_day` window.
- **Known bug** ([#52326](https://github.com/anthropics/claude-code/issues/52326)):
  `used_percentage` can come back as an *epoch timestamp* instead of 0/null before
  a window has data. Both the bridge (`jq`) and the Swift parser guard this by
  nulling any value outside 0–100.

### Statusline refresh cadence (important)

The statusline command re-runs on **conversation activity** (each prompt / turn /
tool call), throttled to ~once per 300ms — **not** on a wall-clock timer. So:
- Active session → file rewritten constantly (near real-time).
- Idle at a prompt → no new renders; file stops updating.
- CC closed → no updates at all.
The `rate_limits` *values* themselves only change when CC makes an API call.

## Architecture

```
Claude Code ──stdin──▶ statusline-command.sh ──atomic write──▶ ~/.claude/menubar-usage.json ──reads──▶ ClaudeUsageBar.app
                       (+ bridge snippet)
```

- **Bridge** (`bridge/statusline-bridge.sh`, installed by `install-bridge.sh`):
  inserted after `input=$(cat)`; uses `jq` to emit `{captured_at, five_hour,
  seven_day}` to a temp file then `mv` (atomic, never a half-written read).
- **App** (SwiftPM executable → bundled `.app`, `LSUIElement`):
  - `UsageStore` reads/parses the JSON, caches the last good reading in
    `UserDefaults` (resilience if the file is briefly missing), and **ticks every
    second continuously** (1s timer; reloads the file every 5s).
  - `captured_at` age is the **freshness / "is CC live"** signal: ≤90s ⇒ "Live",
    else "Claude Code idle/closed — Nm ago". (Timestamp, not a process scan — a
    closed *and* an idle CC both mean "no fresh data.")
  - The **countdown** is computed from `resets_at` in the app, so it stays live
    regardless of CC state.
  - **After-reset inference:** once `now >= resets_at` with no fresher reading, the
    window is shown as replenished (100% left, time row reads "ready / already
    reset"). Inferred, not measured — flagged with an "after reset" tag.

### The live menu bar icon

A colored hourglass that encodes both dimensions:
- **Shape** = time: `hourglass.tophalf.filled` (fresh) → `hourglass` (mid) →
  `hourglass.bottomhalf.filled` (almost reset), by fraction of the 5h window left.
- **Color** = urgency: green ≥50%, amber 20–49%, red <20%, driven by the **scarcer**
  of the two quotas (`min(5h%, weekly%)`), so it warns when *either* runs low.
- Rendered via `NSImage.SymbolConfiguration(paletteColors:)` with
  `isTemplate = false` (so our color sticks); falls back to a neutral template glyph
  when there's no data.

## Key learnings (the expensive ones)

1. **SwiftUI `MenuBarExtra` silently fails to register a status item when built as a
   bare SwiftPM executable** (no Xcode app target). The process runs as an
   `LSUIElement` agent but *no* menu bar item appears — independent of whether the
   label is an icon, `Label`, or `Text`. **Fix:** create the item with AppKit
   `NSStatusItem` in an `NSApplicationDelegate` (via `@NSApplicationDelegateAdaptor`,
   with an inert `Settings { EmptyView() }` scene) and host the SwiftUI view in an
   `NSPopover`. This cost a long debugging detour — check it first next time.
2. **Mark the `AppDelegate` `@MainActor`** or Swift 6 rejects the main-actor AppKit
   calls (status item, popover) with isolation errors.
3. For a **live** menu bar icon, the store must tick **continuously** — don't gate
   the timer on the panel's `onAppear`/`onDisappear`, or the icon freezes when the
   popover is closed.
4. A composite SwiftUI `Label` as a `MenuBarExtra` label can collapse to zero width
   (invisible). Plain `Text`/`Image` are the only reliable forms — moot now that we
   use `NSStatusItem`, but worth knowing.
5. **Notch caveat:** on notched Macs a full menu bar hides overflow items behind the
   notch with no indicator. If an item "won't show," rule out the code (we did) then
   suspect space — free room or use a manager like Ice.
6. `build.sh` gotcha: `$VAR…` (a var immediately followed by a multibyte char) can be
   mis-parsed as part of the name — brace it (`${VAR}`).

## Future ideas (not built)

- **OAuth `/api/oauth/usage` fallback** for true liveness when CC is closed. Endpoint:
  `GET https://api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer
  <token>`, `anthropic-beta: oauth-2025-04-20`, and **`User-Agent: claude-code/<ver>`
  (mandatory — without it you hit an aggressively rate-limited bucket)**. Token is in
  the macOS Keychain ("Claude Code-credentials"). Must cache (~5 min) — the endpoint
  429s hard ([#31637](https://github.com/anthropics/claude-code/issues/31637)).
- Launch-at-login via `SMAppService`.
- Threshold notifications (e.g. alert at 90% used).
- Per-model Opus weekly window (only available via the OAuth API).

## Prior art surveyed

Open-source menu bar trackers: `lionhylra/cc-usage-bar` (PTY-spawn `/usage`),
`ohugonnot/claude-code-statusline` (tiered stdin → OAuth API → cache — the closest
blueprint), plus `Saqoosha/ccusage-menubar`, `rjwalters/claude-monitor`, and others
that parse JSONL and estimate.

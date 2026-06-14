# Claude Usage Bar

A macOS menu bar widget that shows your Claude Code usage at a glance — click the
icon to see:

1. **Time remaining** in the current 5-hour window (live countdown)
2. **5-hour usage left** (% remaining)
3. **Weekly usage left** (% remaining, the rolling 7-day window)

The numbers are Anthropic's own — the same ones `/usage` shows — not estimates.

## How it works

Claude Code passes a `rate_limits` object to your status line command on every
render (v2.1.80+, Pro/Max plans). A small **bridge** in your status line script
persists that data to `~/.claude/menubar-usage.json`; the menu bar app reads it.

```
Claude Code ──stdin──▶ statusline-command.sh ──writes──▶ ~/.claude/menubar-usage.json ──reads──▶ ClaudeUsageBar.app
                       (+ bridge snippet)
```

- **Live while Claude Code is active** — the file is rewritten on every render.
- **Keeps working when Claude Code is closed** — the app caches the last reading
  (file + `UserDefaults`) and keeps the countdown ticking from `resets_at`. The
  footer shows whether the data is **Live** or how long ago it was captured.
- No API calls, no credentials, no token parsing. Purely the official data that
  already flows through your machine.

## Build

```sh
./build.sh          # -> ClaudeUsageBar.app
./build.sh --run    # build and (re)launch
```

Requires the Xcode command-line toolchain (Swift 6+). The app is menu-bar-only
(`LSUIElement`), so it has no Dock icon.

## Install the bridge

```sh
./install-bridge.sh
```

This inserts the bridge snippet (`bridge/statusline-bridge.sh`) into
`~/.claude/statusline-command.sh` after the line that captures stdin, backing the
file up to `.bak` first. It's idempotent and requires `jq` (which the status line
already uses). The next Claude Code render starts producing live data.

To install manually instead, paste `bridge/statusline-bridge.sh` into your status
line script right after `input=$(cat)`.

## Notes & limitations

- The widget is **icon-only**; details appear on click.
- After a window's reset time passes with Claude Code closed, that window is shown
  as replenished (100% left) with an *"after reset"* tag — inferred, since only a
  live session can report the true post-reset number.
- Guards the [known Claude Code bug](https://github.com/anthropics/claude-code/issues/52326)
  where `used_percentage` can return an epoch timestamp before a window has data.
- "Weekly" is the all-model `seven_day` window. The separate per-model Opus weekly
  limit is not exposed in the status line stdin, so it's out of scope.

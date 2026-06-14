# ─── Claude Usage Bar bridge ──────────────────────────────────────────────
# Persist the rate-limit data Claude Code passes on stdin so the menu bar app
# can read it. Paste this block into ~/.claude/statusline-command.sh *after*
# `input=$(cat)` is set. It does not affect what the status line prints.
#
# Requires: jq (already used by the status line script).
__cub_cache="$HOME/.claude/menubar-usage.json"
__cub_tmp="$(mktemp "${__cub_cache}.XXXXXX" 2>/dev/null)" || __cub_tmp=""
if [ -n "$__cub_tmp" ]; then
  if printf '%s' "$input" | jq -c --argjson now "$(date +%s)" '
        # Drop bogus percentages: Claude Code can return an epoch timestamp in
        # used_percentage when a window has no data yet (it should be 0..100).
        def clean(p): (p // null) | if . == null or . < 0 or . > 100 then null else . end;
        def win(w): if w.resets_at == null then null
                    else { used_percentage: clean(w.used_percentage), resets_at: w.resets_at } end;
        {
          captured_at: $now,
          five_hour:  win(.rate_limits.five_hour  // {}),
          seven_day:  win(.rate_limits.seven_day  // {})
        }
      ' > "$__cub_tmp" 2>/dev/null; then
    mv -f "$__cub_tmp" "$__cub_cache" 2>/dev/null || rm -f "$__cub_tmp"
  else
    rm -f "$__cub_tmp"
  fi
fi
# ─── end Claude Usage Bar bridge ──────────────────────────────────────────

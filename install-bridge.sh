#!/usr/bin/env bash
# Install the Claude Usage Bar bridge into ~/.claude/statusline-command.sh.
# Idempotent: safe to run more than once. Makes a .bak backup the first time.
set -euo pipefail

STATUSLINE="$HOME/.claude/statusline-command.sh"
SNIPPET="$(dirname "$0")/bridge/statusline-bridge.sh"
MARKER="Claude Usage Bar bridge"

if [[ ! -f "$STATUSLINE" ]]; then
    echo "error: $STATUSLINE not found." >&2
    echo "Set up a Claude Code status line first, or create the file with 'input=\$(cat)'." >&2
    exit 1
fi

if grep -q "$MARKER" "$STATUSLINE"; then
    echo "Bridge already installed in $STATUSLINE — nothing to do."
    exit 0
fi

if ! grep -q 'input=$(cat)' "$STATUSLINE"; then
    echo "error: could not find 'input=\$(cat)' in $STATUSLINE." >&2
    echo "The bridge needs the raw stdin captured in \$input. Add it manually:" >&2
    echo "  paste $SNIPPET after the line that sets \$input." >&2
    exit 1
fi

cp "$STATUSLINE" "$STATUSLINE.bak"
echo "Backed up -> $STATUSLINE.bak"

# Insert the snippet immediately after the first 'input=$(cat)' line.
tmp="$(mktemp)"
inserted=0
while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >> "$tmp"
    if [[ $inserted -eq 0 && "$line" == 'input=$(cat)' ]]; then
        printf '\n' >> "$tmp"
        cat "$SNIPPET" >> "$tmp"
        inserted=1
    fi
done < "$STATUSLINE"

mv "$tmp" "$STATUSLINE"
chmod +x "$STATUSLINE"
echo "Bridge installed. Next Claude Code render will start writing ~/.claude/menubar-usage.json"

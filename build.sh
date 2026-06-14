#!/usr/bin/env bash
# Build ClaudeUsageBar and assemble a proper .app bundle (menu-bar-only).
#
#   ./build.sh           # release build -> ./ClaudeUsageBar.app
#   ./build.sh --run     # build, then (re)launch the app
set -euo pipefail

cd "$(dirname "$0")"

APP="ClaudeUsageBar"
BUNDLE="$APP.app"
CONFIG="release"

echo "==> Compiling ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP"

echo "==> Assembling ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc codesign so the app launches without Gatekeeper friction.
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "==> Built $BUNDLE"

if [[ "${1:-}" == "--run" ]]; then
    echo "==> Relaunching…"
    pkill -x "$APP" 2>/dev/null || true
    sleep 0.3
    open "$BUNDLE"
fi

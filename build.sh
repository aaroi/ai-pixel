#!/usr/bin/env bash
# Builds ai.pixel.app from the Swift package + Resources/Info.plist.
# Usage: ./build.sh [debug|release]   (default: release)

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ai.pixel"
BIN_NAME="ai-pixel"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "→ swift build -c $CONFIG"
cd "$ROOT"
swift build -c "$CONFIG"

BIN_PATH="$ROOT/.build/$CONFIG/$BIN_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "✗ binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "→ assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Optional icon
if [ -f "$ROOT/Resources/icon.icns" ]; then
    cp "$ROOT/Resources/icon.icns" "$APP_DIR/Contents/Resources/icon.icns"
fi

# Ad-hoc sign so Gatekeeper doesn't quarantine on first launch.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo "✓ built $APP_DIR ($SIZE)"
echo
echo "Run:    open '$APP_DIR'"
echo "Install: cp -R '$APP_DIR' /Applications/"

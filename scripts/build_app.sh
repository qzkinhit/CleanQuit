#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Building CleanQuit (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/CleanQuit"
APP_DIR="$ROOT_DIR/dist/CleanQuit.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/CleanQuit"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "Done! App bundle created at: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    INSTALL_DIR="/Applications/CleanQuit.app"
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"
    echo "Installed to: $INSTALL_DIR"
fi

echo "You can launch it with: open \"$APP_DIR\""

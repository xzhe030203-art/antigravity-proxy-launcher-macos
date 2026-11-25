#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="${APP_NAME:-Antigravity Proxy Launcher.app}"
APP_PATH="$DIST_DIR/$APP_NAME"
SRC_SCRIPT="$ROOT_DIR/src/launcher.applescript"

if [ ! -f "$SRC_SCRIPT" ]; then
  echo "Error: source script not found at $SRC_SCRIPT" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$APP_PATH"

echo "Building $APP_PATH from src/launcher.applescript..."
osacompile -o "$APP_PATH" "$SRC_SCRIPT"

echo "Applying local ad-hoc signature..."
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Done! Built app at:"
echo "  $APP_PATH"

#!/usr/bin/env bash
set -euo pipefail

# Path to the .app, .dmg, or directory containing TickTick.app to patch.
# Defaults to /Applications/TickTick.app if not provided.
DEFAULT_SOURCE="/Applications/TickTick.app"
SOURCE_INPUT="${1:-$DEFAULT_SOURCE}"

# Output path for the prepared app bundle. This will be overwritten if it already exists.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/build/TickTick.patched.app"
ENTITLEMENTS="$SCRIPT_DIR/debug-entitlements.plist"
MOUNT_POINT=""
SOURCE_APP=""

usage() {
  cat <<USAGE
Usage:
  $0 [SOURCE] [OUTPUT_APP]

SOURCE can be:
  - TickTick.app
  - a directory containing TickTick.app
  - a TickTick .dmg

Defaults:
  SOURCE     $DEFAULT_SOURCE
  OUTPUT_APP $SCRIPT_DIR/build/TickTick.patched.app

Examples:
  $0
  $0 TickTick_8.0.60_468.dmg
  $0 /Applications/TickTick.app /tmp/TickTick.patched.app
USAGE
}

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

resolve_source_app() {
  local input="$1"

  if [[ "$input" == "-h" || "$input" == "--help" || "$input" == "help" ]]; then
    usage
    exit 0
  fi

  if [[ -d "$input" && "$input" == *.app ]]; then
    SOURCE_APP="$input"
    return
  fi

  if [[ -d "$input" ]]; then
    local app
    app="$(find "$input" -maxdepth 4 -type d -name 'TickTick.app' -print -quit)"
    if [[ -n "$app" ]]; then
      SOURCE_APP="$app"
      return
    fi
  fi

  if [[ -f "$input" && "$input" == *.dmg ]]; then
    local plist
    plist="$(hdiutil attach "$input" -nobrowse -readonly -plist)"
    MOUNT_POINT="$(printf '%s' "$plist" | plutil -extract system-entities.0.mount-point raw -o - - 2>/dev/null || true)"
    if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
      echo "Could not mount DMG: $input" >&2
      exit 1
    fi

    local app
    app="$(find "$MOUNT_POINT" -maxdepth 4 -type d -name 'TickTick.app' -print -quit)"
    if [[ -n "$app" ]]; then
      SOURCE_APP="$app"
      return
    fi

    echo "Mounted DMG but did not find TickTick.app: $input" >&2
    exit 1
  fi

  echo "Could not resolve TickTick.app from: $input" >&2
  exit 1
}

require_tool ditto
require_tool codesign
require_tool xattr
require_tool hdiutil
require_tool plutil

if [[ "$SOURCE_INPUT" == "-h" || "$SOURCE_INPUT" == "--help" || "$SOURCE_INPUT" == "help" ]]; then
  usage
  exit 0
fi

resolve_source_app "$SOURCE_INPUT"

if [[ ! -d "$SOURCE_APP/Contents" ]]; then
  echo "Invalid app bundle: $SOURCE_APP" >&2
  exit 1
fi

echo "[source] $SOURCE_APP"
echo "[output] $APP"

echo "[1/4] Creating clean patched copy"
if [[ -e "$APP" ]]; then
  rm -rf "$APP"
fi
ditto --noextattr --noacl "$SOURCE_APP" "$APP"

echo "[2/4] Removing Gatekeeper quarantine/provenance metadata"
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -name '*:com.apple.quarantine' -type f -delete
find "$APP" -name '*:com.apple.provenance' -type f -delete

echo "[3/4] Re-signing nested code for local debugging"
while IFS= read -r item; do
  codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$item" >/dev/null
done < <(
  find "$APP/Contents" \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' -o -name '*.xpc' -o -name '*.app' -o -name '*.docktileplugin' \) \
    -print | sort -r
)

echo "[4/4] Re-signing app bundle"
codesign --force --deep --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP" >/dev/null

echo "[done] Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "[done] Patched app: $APP"

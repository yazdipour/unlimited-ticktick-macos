#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP="${TICKTICK_APP:-$REPO_DIR/TickTick.debug.app}"
APP_BIN="$APP/Contents/MacOS/TickTick"
DYLIB_NAME="libPatchZero.dylib"
DYLIB_PATH="$APP/Contents/MacOS/$DYLIB_NAME"

die() {
  echo "error: $*" >&2
  exit 1
}

if [[ ! -d "$APP" ]]; then
  die "App directory not found: $APP. Run prepare-app.sh first?"
fi

echo "==> Compiling the Objective-C hook..."
clang -dynamiclib -framework Foundation -o "$SCRIPT_DIR/$DYLIB_NAME" "$SCRIPT_DIR/hook.m"

echo "==> Copying dylib to the App bundle..."
cp "$SCRIPT_DIR/$DYLIB_NAME" "$DYLIB_PATH"

echo "==> Setting up insert_dylib tool..."
if ! command -v insert_dylib >/dev/null 2>&1; then
    if [[ ! -x "$SCRIPT_DIR/insert_dylib/insert_dylib" ]]; then
        echo "    Downloading and building insert_dylib..."
        rm -rf "$SCRIPT_DIR/insert_dylib"
        git clone --depth 1 https://github.com/Tyilo/insert_dylib "$SCRIPT_DIR/insert_dylib"
        (cd "$SCRIPT_DIR/insert_dylib" && xcodebuild -quiet)
    fi
    INSERT_DYLIB="$SCRIPT_DIR/insert_dylib/build/Release/insert_dylib"
else
    INSERT_DYLIB="insert_dylib"
fi

echo "==> Injecting dylib into binary..."
"$INSERT_DYLIB" --inplace "@executable_path/$DYLIB_NAME" "$APP_BIN"

ENTITLEMENTS="$SCRIPT_DIR/patch-entitlements.plist"
echo "==> Generating debug entitlements..."
cat << 'ENT' > "$ENTITLEMENTS"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
  <key>com.apple.security.get-task-allow</key>
  <true/>
</dict>
</plist>
ENT

echo "==> Re-signing the App..."
if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --deep --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
else
  codesign --force --deep --sign - --timestamp=none "$APP"
fi

echo "==> Clearing quarantine attributes..."
xattr -cr "$APP"

echo "==> Success! You can now launch the app directly."
echo "    open \"$APP\""

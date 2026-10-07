#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/build/TickTick.patched.app"
APP_BIN="$APP/Contents/MacOS/TickTick"
DYLIB_NAME="libPatchZero.dylib"
DYLIB_PATH="$APP/Contents/MacOS/$DYLIB_NAME"

die() {
  echo "error: $*" >&2
  exit 1
}

set_entitlement_bool() {
  local key="$1"
  local value="$2"

  /usr/libexec/PlistBuddy -c "Set :$key $value" "$ENTITLEMENTS" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$ENTITLEMENTS"
}

echo "==> Preparing App..."
"$SCRIPT_DIR/prepare.sh" "$@"

if [[ ! -d "$APP" ]]; then
  die "App directory not found: $APP. Run prepare.sh first?"
fi

echo "==> Compiling the Objective-C hook..."
mkdir -p "$SCRIPT_DIR/build"
ARCH_FLAGS=()
while IFS= read -r arch; do
  ARCH_FLAGS+=("-arch" "$arch")
done < <(lipo -archs "$APP_BIN" | tr ' ' '\n')
clang "${ARCH_FLAGS[@]}" -dynamiclib -framework Foundation -framework AppKit -lsqlite3 -o "$SCRIPT_DIR/build/$DYLIB_NAME" "$SCRIPT_DIR/hook.m"

echo "==> Copying dylib to the App bundle..."
cp "$SCRIPT_DIR/build/$DYLIB_NAME" "$DYLIB_PATH"

echo "==> Setting up insert_dylib tool..."
if ! command -v insert_dylib >/dev/null 2>&1; then
    if [[ ! -x "$SCRIPT_DIR/build/insert_dylib/insert_dylib" ]]; then
        echo "    Downloading and building insert_dylib..."
        rm -rf "$SCRIPT_DIR/build/insert_dylib"
        git clone --depth 1 https://github.com/Tyilo/insert_dylib "$SCRIPT_DIR/build/insert_dylib"
        (cd "$SCRIPT_DIR/build/insert_dylib" && xcodebuild -quiet)
    fi
    INSERT_DYLIB="$SCRIPT_DIR/build/insert_dylib/build/Release/insert_dylib"
else
    INSERT_DYLIB="insert_dylib"
fi

if ! otool -L "$APP_BIN" | grep -q "$DYLIB_NAME"; then
    echo "==> Injecting dylib into binary..."
    "$INSERT_DYLIB" --inplace --all-yes "@executable_path/$DYLIB_NAME" "$APP_BIN"
else
    echo "==> Dylib already injected into binary, skipping injection..."
fi
install_name_tool -id "@executable_path/$DYLIB_NAME" "$DYLIB_PATH"

echo "==> Neutralizing the piracy alert handler in the binary..."
# The app's notification handler shows "Application Not Licensed" and then
# hides the windows after runModal, which is what causes the launch flash.
# Patching its entry to `ret` stops it before any UI runs; the dylib alert
# suppression stays as a fallback if the pattern is not found.
if python3 "$SCRIPT_DIR/disable_piracy_alert.py" "$APP_BIN"; then
  echo "    Piracy handler patched (binary level)."
else
  echo "    WARNING: piracy handler pattern not found; relying on dylib suppression."
fi

ENTITLEMENTS="$SCRIPT_DIR/build/patch-entitlements.plist"
ORIGINAL_ENTITLEMENTS="$SCRIPT_DIR/build/original-entitlements.plist"

# Preserve the original App Group entitlement so the patched app keeps read-write
# access to its data container (~/Library/Group Containers/<group-id>). Without it
# the ad-hoc re-signed app fails the WAL checkpoint during the "Upgrading..." data
# migration and crashes with "Abnormal data detected" / "Upgrade Failed".
#
# The provisioning-profile-backed keys below are deliberately dropped: keeping them
# on an ad-hoc signature triggers "Namespace CODESIGNING ... Invalid Signature" and
# the app refuses to launch.
DROP_KEYS=(
  com.apple.developer.team-identifier
  com.apple.developer.aps-environment
  com.apple.developer.associated-domains
  com.apple.developer.usernotifications.time-sensitive
)

if grep -q '<dict>' "$ORIGINAL_ENTITLEMENTS" 2>/dev/null; then
  echo "==> Building entitlements from original (preserving App Group access)..."
  # Normalize to XML and start from the original entitlements.
  plutil -convert xml1 -o "$ENTITLEMENTS" "$ORIGINAL_ENTITLEMENTS"
  for key in "${DROP_KEYS[@]}"; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$ENTITLEMENTS" 2>/dev/null || true
  done
else
  echo "==> No original entitlements found; generating debug-only entitlements..."
  cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
ENT
fi

set_entitlement_bool com.apple.security.cs.disable-library-validation true
set_entitlement_bool com.apple.security.cs.allow-dyld-environment-variables true
set_entitlement_bool com.apple.security.get-task-allow true

echo "==> Re-signing the App..."
# Sign the injected dylib first
codesign --force --sign - --timestamp=none "$DYLIB_PATH"

if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --deep --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
else
  codesign --force --deep --sign - --timestamp=none "$APP"
fi

echo "==> Clearing quarantine attributes..."
xattr -cr "$APP"

echo "==> Success! You can now launch the app directly."
echo "    open \"$APP\""

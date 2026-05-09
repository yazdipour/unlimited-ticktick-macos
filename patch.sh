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
clang "${ARCH_FLAGS[@]}" -dynamiclib -framework Foundation -o "$SCRIPT_DIR/build/$DYLIB_NAME" "$SCRIPT_DIR/hook.m"

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

ENTITLEMENTS="$SCRIPT_DIR/build/patch-entitlements.plist"
echo "==> Generating local debug entitlements..."
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
ENT
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

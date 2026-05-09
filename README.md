# Unlimited TickTick - macOS

A standalone set of tools to statically patch the official TickTick macOS application. It injects a custom Objective-C dynamic library to modify runtime behavior without needing an external debugger or runtime injection tool like Frida.

This creates a fully re-signed `.app` bundle that you can launch natively on macOS by simply double-clicking it.

## Features

- **Static Injection**: Compiles and injects an Objective-C hook (`hook.m`) directly into the app's Mach-O binary.
- **Universal Dylib Build**: Builds `libPatchZero.dylib` for the same architectures as TickTick's main executable, for example `x86_64 arm64`.
- **Local Re-Signing**: Re-signs the injected dylib and app bundle ad-hoc with minimal local debug entitlements.
- **Quarantine Cleanup**: Drops Gatekeeper quarantine/provenance attributes from the generated bundle.
- **No External Daemons**: Unlike Frida, you do not need to keep a terminal open to attach to the process. 
- **Auto-dependency Resolution**: Automatically clones and builds `Tyilo/insert_dylib` locally for Mach-O modification.

## Prerequisites

You only need standard macOS developer tools:
- Xcode Command Line Tools (`xcode-select --install`)
- Common Unix tools already included with macOS: `bash`, `codesign`, `curl`, `ditto`, `hdiutil`, `lipo`, `otool`, `plutil`, `xattr`
- `git`, used only if `insert_dylib` needs to be cloned automatically

## Usage

Run `patch.sh` with an optional source argument:

```bash
# By default, it patches ~/Applications/TickTick.app
./patch.sh

# Or you can target a specific local disk image
./patch.sh ~/Downloads/TickTick_8.0.60_468.dmg

# Or target a specific App bundle
./patch.sh /Applications/TickTick.app

# Or download and patch a disk image directly
./patch.sh "https://example.com/TickTick.dmg"
```

Once the script completes successfully, it produces `build/TickTick.patched.app`.


## Troubleshooting

### Quarantine or damaged-app warnings

The scripts clear quarantine automatically, but you can repeat it manually:

```bash
xattr -cr "build/TickTick.patched.app"
```

### `The application "TickTick.patched.app" can't be opened`

Check the generated bundle signature:

```bash
codesign --verify --deep --strict --verbose=2 "build/TickTick.patched.app"
```

Also confirm the app executable and injected dylib have matching architectures:

```bash
lipo -archs "build/TickTick.patched.app/Contents/MacOS/TickTick"
lipo -archs "build/TickTick.patched.app/Contents/MacOS/libPatchZero.dylib"
```

Both should print the same architecture list.

### `Namespace CODESIGNING, Code 1, Taskgated Invalid Signature`

This usually means macOS rejected the app at launch even though the bundle may look valid on disk. The current script avoids the common cause by signing the final app with only local debug/code-loading entitlements:

- `com.apple.security.cs.disable-library-validation`
- `com.apple.security.cs.allow-dyld-environment-variables`
- `com.apple.security.get-task-allow`

Verify the embedded entitlements with:

```bash
codesign -d --entitlements :- "build/TickTick.patched.app" 2>/dev/null | plutil -p -
```

If restricted production entitlements such as `com.apple.developer.team-identifier`, `com.apple.developer.aps-environment`, associated domains, or application groups appear in the final app signature, rebuild with the current `patch.sh`.

### `MACOSX_DEPLOYMENT_TARGET` warning from `insert_dylib`

This warning is from building the helper tool:

```text
The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.9...
```

It is not the cause of TickTick launch failures. The helper still builds and is only used to modify the Mach-O load commands.

## Development

To modify the injected behavior, simply edit `hook.m`. It uses standard Objective-C method swizzling.

## Disclaimer

This repository is provided for informational and educational purposes only.

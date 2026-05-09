# Unlimited TickTick - macOS

A standalone string of tools to statically patch the official TickTick macOS application. It injects a custom Objective-C dynamic library to modify runtime behaviors (like forcing Pro feature flags) without needing an external debugger or runtime injection tools like Frida.

This creates a fully re-signed `.app` bundle that you can launch natively on macOS by simply double-clicking it.

## Features

- **Static Injection**: Compiles and injects an Objective-C hook (`hook.m`) directly into the app's Mach-O binary.
- **Self-Contained**: The patch script automatically drops Gatekeeper quarantine attributes, disables Library Validation, generates debug entitlements, and recursively re-signs the entire application bundle.
- **No External Daemons**: Unlike Frida, you do not need to keep a terminal open to attach to the process. 
- **Auto-dependency Resolution**: Automatically clones and builds `Tyilo/insert_dylib` locally for Mach-O modification.

## Prerequisites

You only need standard macOS developer tools:
- Xcode Command Line Tools (`xcode-select --install`)
- Common Unix tools (already included in macOS: `git`, `bash`, `codesign`, `xattr`)

## Usage

Simply run the `patch.sh` script. It accepts a `.dmg` file, an `.app` folder, or a directory containing the app.

```bash
# Auto-detect a local TickTick DMG or App in the parent directories
./patch.sh

# Or target a specific DMG file
./patch.sh ~/Downloads/TickTick_8.0.60_468.dmg

# Or target an installed App bundle
./patch.sh /Applications/TickTick.app ~/Desktop/TickTick.patched.app
```

Once the script completes successfully:
1. It will produce a `TickTick.patched.app` directory.
2. You can launch it from the terminal via `open TickTick.patched.app` or by double-clicking it in Finder.

> [!TIP]
> If the error "The application 'TickTick' cannot be opened" appears, or it shows as damaged, you can often fix it by running:  
> `xattr -cr TickTick.app`

## Under the Hood

When you execute `patch.sh`, it performs the following steps:
1. Copies the target `.app` locally (extracting from a DMG if necessary).
2. Clears macOS Gatekeeper and provenance attributes (`xattr -cr`).
3. Compiles `hook.m` into `libPatchZero.dylib`.
4. Uses `insert_dylib` to inject a load command into the main executable header so the app naturally loads our custom dylib on startup.
5. Injects custom local entitlements to bypass Hardened Runtime/Library Validation constraints.
6. Deeply re-signs all nested extensions, frameworks, and finally the main App bundle.

## Development

To modify the injected behavior, simply edit `hook.m`. It uses standard Objective-C method swizzling.

## Disclaimer

This repository is provided for informational and educational purposes only.

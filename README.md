# Unlimited TickTick - macOS

> [!TIP]
> You can also find a Windows version of this patch in the [Unlimited TickTick - Windows](https://github.com/yazdipour/unlimited-ticktick-windows) repository.

A standalone set of tools to statically patch the official TickTick macOS application. It injects a custom Objective-C dynamic library to modify runtime behavior without needing an external debugger or runtime injection tool like Frida.

This creates a fully re-signed `.app` bundle that you can launch natively on macOS by simply double-clicking it.

![premium enabled](docs/screenshot.png)

## Build via GitHub Actions

If you don't have a local macOS development environment set up, or just prefer to build the patched app in the cloud, you can use GitHub Actions to generate your own patched DMG.

0. Give the repo a star.
1. **Fork** this repository using the fork button on the top right.
2. Go to the **Actions** tab on your newly forked repository. If prompted, click the button to enable workflows.
3. On the left sidebar under "All workflows", click on **Build Patched TickTick**.
4. Click the **Run workflow** button on the right side.
5. You can optionally provide a direct URL to a specific official TickTick DMG. Either provide a URL to your app or dmg, or you can find the latest version at the official TickTick website and copy the download link to the DMG file.
6. Click **Run workflow** and wait for the build to finish.
7. Go to the **Releases** section on the right side of your repository's main page. You will find a new **Draft** release containing your patched `TickTick.patched.dmg` file ready to download.
8. Download the DMG, open it, and drag the patched app out and rename it to `TickTick.app`. Then move it to your Applications folder.
9. Initially you may get this error or something similar. To pass this issue you need to run this command in terminal: `xattr -cr ~/Applications/TickTick.app` to clear the quarantine attribute from the app bundle. After that, you should be able to launch TickTick without any issues.
<img src="docs/error.png" alt="Error" width="270" />

<details>
<summary>Troubleshooting</summary>

### `Upgrade Failed` / `Abnormal data detected, please clear those data first and update again.`

The app keeps its database in its App Group container
(`~/Library/Group Containers/75TY9UT8AY.com.TickTick.task.mac`). macOS gates access
to that container on the app's real, team-signed identity (`75TY9UT8AY`). Because the
patch re-signs the app **ad-hoc**, macOS denies it read/write access to that folder
(even with the `application-groups` entitlement present), so the app fails its SQLite
WAL checkpoint during the "Upgrading…" migration and shows this error.

The injected dylib (`hook.m`) fixes this by **redirecting the App Group container to a
writable location** that a non-sandboxed, ad-hoc app can use:

```
~/Library/Application Support/TickTickPatched/GroupContainers/75TY9UT8AY.com.TickTick.task.mac/
```

Consequence: the patched app starts from a **clean local store**, so you sign in once
and TickTick re-downloads all your tasks from the server. Your data is safe — it lives
in your TickTick account, not only on disk.

> [!IMPORTANT]
> **Do not click "Clear And Restart"** if you ever see this dialog — it permanently
> deletes any not-yet-synced tasks. Make sure your tasks are synced in the official
> app first.

You can confirm the patched app launches cleanly by watching its log:

```bash
open "build/TickTick.patched.app"
ls "$HOME/Library/Application Support/TickTickPatched/GroupContainers/"*/Logs/*.log
```

A successful launch logs `handleFinishLaunching: - user not signed in.` with no
"abnormal data" lines.

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

</details>

## Disclaimer

This repository is provided for informational and educational purposes only.

# TickTick User Entitlement Hook

Runtime Frida hook that forces TickTick macOS user entitlement fields to a pro state:

- `TTUserModel.isPro` -> `true`
- `TTUserModel.proEndDate` -> `2990-01-01 00:00:00 UTC`

## Run

First prepare the app for local Frida debugging:

```bash
./prepare-app.sh
```

You can also pass a `.dmg`, an app bundle, or a directory containing
`TickTick.app`:

```bash
./prepare-app.sh TickTick_8.0.60_468.dmg
./prepare-app.sh /Applications/TickTick.app
```

This creates `TickTick.debug.app`. Launch that prepared copy under Frida:

```bash
./run.sh spawn
```

Or attach to an already-running TickTick process:

```bash
./run.sh attach
```

Attach by PID:

```bash
./run.sh attach 12345
```

## What It Hooks

- `-[TTUserModel setIsPro:]`
- `-[TTUserModel isPro]`
- `-[TTUserModel setProEndDate:]`
- `-[TTUserModel proEndDate]`

The database value can still be updated by the app or server. This hook changes
runtime behavior for the active process.

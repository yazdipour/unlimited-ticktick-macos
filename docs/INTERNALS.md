# Patch Internals & Maintenance Guide

How the patch works, what was found in the TickTick binary, and how to
maintain it when TickTick ships a new version.

Verified against **TickTick 8.2.30 (923)**, arm64 slice.

## Architecture: two independent layers

| Layer | File | Role |
|---|---|---|
| Static binary patch | `disable_piracy_alert.py` (run by `patch.sh`) | Neutralizes the piracy-alert handler in the Mach-O before signing |
| Runtime dylib | `hook.m` → `libPatchZero.dylib` | Premium unlock, container redirect, and fallback alert suppression |

The static patch is the primary defense against the launch-time piracy
alert; the dylib hooks remain as a **fallback** if the static pattern is
not found in a future TickTick build.

## What the piracy handler actually does (reverse-engineered)

Found by string xref: the handler is the only code referencing the
localization key `Application Not Licensed`. In 8.2.30 (arm64) it lives
at `0x10054e6f0` and is registered as a notification-observer closure.

Pseudocode recovered from disassembly:

```text
handler(notification):
    if !TTAccountManager.shared.<vtable+0x158 bool>():   # signed-in gate
        return
    alert = NSAlert()
    alert.messageText      = "Application Not Licensed"   # localized
    alert.informativeText  = "We detected that you are using a pirated ..."
    alert.addButton("Download TickTick")
    alert.addButton("Cancel")
    response = alert.runModal()
    if response == NSAlertFirstButtonReturn:              # 1000
        NSWorkspace.open(macappstores://itunes.apple.com/app/id966085870)
    <hide/flush the app's windows>                        # UNCONDITIONAL
```

Key finding: **the window-hiding runs after `runModal` regardless of the
answer.** No choice of `NSModalResponse` avoids it. This is why purely
runtime approaches (swizzling `NSAlert`, `orderOut:`, `miniaturize:`,
`hide:`) can only restore the window *after* it was hidden — producing a
visible flash, focus loss, and (when `orderOut:` was blocked outright)
a broken task list. The clean fix is to prevent the handler from running
at all: `disable_piracy_alert.py` replaces its first instruction with
`ret` (arm64 `0xd65f03c0`).

## How `disable_piracy_alert.py` locates the handler

Pattern-based, arm64 only (the machine architecture that matters for
local builds; CI runs on `macos-latest` = arm64):

1. find the `Application Not Licensed` C string in the slice;
2. scan `__text` for an `adrp x8, page` + `add x8, x8, off` pair that
   materializes the string address, followed by `sub x8, x8, #0x20`
   (the localization-table bias);
3. walk backwards from the xref to the nearest function prologue
   `sub sp, sp, #0x70` (`0xd101c3ff`);
4. overwrite that instruction with `ret`.

Failure mode is safe by design: if any step misses, the script exits
non-zero, `patch.sh` prints
`WARNING: piracy handler pattern not found; relying on dylib suppression`
and the build **continues** — the app still works via the dylib layer,
with the old brief launch flash.

## Dylib layers (`hook.m`)

- **Container redirect** — `containerURLForSecurityApplicationGroupIdentifier:`
  points to `~/Library/Application Support/TickTickPatched/GroupContainers/...`
  because ad-hoc signing loses access to the real App Group container.
- **JSON wire patch** — rewrites `isPro/isTeamPro/isActiveTeamUser → true`
  and `proEndDate/vipEndDate → 2098`, **only for keys the server actually
  sent**. Injecting absent keys made every profile poll look "changed";
  the sync engine rebuilt local data and the task list vanished (learned
  the hard way, keep it that way).
- **Surgical sqlite interpose** — forces pro columns on reads, gated on
  the owning table (`ZTTUSER`/`USER`). Column-name-only matching corrupts
  JOIN rows and breaks task rendering on second launch.
  `sqlite3_column_type` is deliberately NOT interposed: type-forcing broke
  row parsing the same way. A NULL `ZPROENDDATE` before the first sync is
  acceptable — `ZISPRO` int reads gate the UI, and the wire patch persists
  a 2098 date on the first profile sync.
- **Alert suppression (fallback)** — matches 41 localized piracy titles;
  first alert is answered `FirstButtonReturn` once per process (the
  startup handler only accepts that), repeats are cancelled; App Store
  URLs are swallowed.
- **Window/menu guards** — orderOut windowless-restore, startup window &
  focus recovery (5 s window), main-menu protection, activation-policy
  pin, Cmd+Q safety valve (keyCode 12 — layout-independent, literal `q`
  fails on Cyrillic).

## Version-sensitive constants (checklist on every TickTick update)

| What | Where | Breaks if renamed |
|---|---|---|
| `ZTTUSER` table, `ZISPRO/ZISTEAMPRO/ZISACTIVETEAMUSER/ZPROENDDATE/ZVIPENDDATE` columns | `hook.m` sqlite interpose | premium unlock from local store |
| `isPro/isTeamPro/isActiveTeamUser/proEndDate/vipEndDate` JSON keys | `hook.m` JSON patch | premium unlock from wire |
| `Application Not Licensed` key + `sub sp,sp,#0x70` prologue + `sub x8,#0x20` bias | `disable_piracy_alert.py` | static patch (falls back to dylib) |
| 41 localized piracy titles | `hook.m` | fallback alert matching |

## Update playbook (new TickTick release)

1. Get the new DMG URL from ticktick.app, run **Build Patched TickTick**
   (Actions → Run workflow) with that URL.
2. Check the build log:
   - `Piracy handler patched (binary level)` → all good;
   - `WARNING: piracy handler pattern not found` → dylib fallback only
     (launch flash returns); re-derive the pattern, see below.
3. Install, sign in, verify: premium badge, task list renders on second
   launch, no alert, no flash.
4. If premium stopped working: inspect the local store schema —
   ```bash
   sqlite3 "$HOME/Library/Application Support/TickTickPatched/GroupContainers/"*/*.sqlite \
     '.schema ZTTUSER'
   ```
   and update the column lists in `hook.m` if names changed.

### Re-deriving the static pattern

```bash
BIN=/path/to/TickTick.app/Contents/MacOS/TickTick

# 1. confirm the localization key still exists
strings -a "$BIN" | grep -c 'Application Not Licensed'

# 2. dump disassembly and find the xref
otool -arch arm64 -tV "$BIN" > /tmp/dis.txt
grep -n 'Application Not Licensed' /tmp/dis.txt   # adrp/add site

# 3. look ~30-60 instructions above the xref for the function prologue
#    (sub sp, sp, #imm). If imm != 0x70, update the prologue constant in
#    disable_piracy_alert.py (encoding: 0xd10003ff | (imm7<<... ) — easiest:
#    assemble `sub sp, sp, #NEW` with clang and read the 4 bytes).

# 4. test on a COPY first, then verify:
python3 disable_piracy_alert.py /tmp/TickTick.copy
otool -arch arm64 -tV /tmp/TickTick.copy | grep -A2 '<handler addr>'
# first instruction must be `ret`
```

## Build pipeline notes

- `prepare.sh` — copies the app, strips quarantine/provenance xattrs,
  re-signs nested code ad-hoc, extracts original entitlements.
- `patch.sh` — compiles `hook.m` for every arch of the app binary,
  injects the load command with `insert_dylib`, runs
  `disable_piracy_alert.py`, rebuilds entitlements (keeps App Group,
  drops provisioning-profile-backed keys — keeping them on an ad-hoc
  signature causes `Namespace CODESIGNING ... Invalid Signature`),
  re-signs, clears quarantine.
- CI (`.github/workflows/main.yml`) — manual `workflow_dispatch`; builds,
  packages the DMG, and creates a draft release.

## Why not runtime-only suppression? (history)

Every runtime-only variant was tried and failed in some way: answering
`Stop` → 150 ms modal storm; answering `FirstButtonReturn` → windows
hidden unconditionally after the modal; blocking `orderOut:` → task list
dead (AppKit transaction left half-done); restoring the window on a
timer → focus theft and Dock minimize/restore fighting the user;
`NSDisableScreenUpdates` around hide/restore → task list vanished;
`disableScreenUpdatesUntilFlush` → no-op on modern macOS. The static
`ret` at the handler entry is the only variant with zero side effects,
because no UI code ever runs.

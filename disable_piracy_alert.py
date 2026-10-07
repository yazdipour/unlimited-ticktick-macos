#!/usr/bin/env python3
"""Statically neutralize TickTick's piracy-alert notification handler.

The handler (a Swift notification-observer closure in the main binary) shows
the "Application Not Licensed" NSAlert and then hides the app windows after
runModal returns, no matter which button was answered. Runtime hooks can only
undo that hide, leaving a visible flash. Replacing the handler's first
instruction with `ret` prevents the alert and the hide loop from ever running.

Locating the handler:
  1. find the "Application Not Licensed" localization key in __cstring;
  2. find the adrp/add pair that materializes its address (arm64);
  3. walk back to the function prologue `sub sp, sp, #0x70`;
  4. overwrite the prologue instruction with `ret`.

Usage: disable_piracy_alert.py <path/to/TickTick binary>
Exit 0 when at least one slice was patched, 2 when the pattern was not found.
"""
import struct
import sys

NEEDLE = b"Application Not Licensed"
RET_ARM64 = struct.pack("<I", 0xD65F03C0)
FAT_MAGIC = {0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA}


def slices(data):
    magic = struct.unpack(">I", data[:4])[0]
    if magic not in FAT_MAGIC:
        return [(None, 0, len(data))]
    big = magic in (0xCAFEBABE, 0xCAFEBABF)
    endian = ">" if big else "<"
    count = struct.unpack(endian + "I", data[4:8])[0]
    out = []
    fat64 = magic in (0xCAFEBABF, 0xBFBAFECA)
    for i in range(count):
        if fat64:
            # fat_arch_64: cputype, cpusubtype, offset(u64), size(u64),
            # align, reserved — 32-byte records.
            cputype, _, off, size, _, _ = struct.unpack(
                endian + "iiQQII", data[8 + i * 32: 40 + i * 32]
            )
        else:
            cputype, _, off, size, _ = struct.unpack(
                endian + "iiIII", data[8 + i * 20: 28 + i * 20]
            )
        out.append((cputype, off, size))
    return out


def segments(sl):
    ncmds = struct.unpack("<I", sl[16:20])[0]
    p = 32
    segs = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", sl[p: p + 8])
        if cmd == 0x19:  # LC_SEGMENT_64
            name = sl[p + 8: p + 24].split(b"\0")[0].decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack(
                "<QQQQ", sl[p + 24: p + 56]
            )
            segs.append((name, vmaddr, vmsize, fileoff, filesize))
        p += cmdsize
    return segs


def make_maps(segs):
    def f2v(fo):
        for _, vmaddr, _, fileoff, filesize in segs:
            if fileoff <= fo < fileoff + filesize:
                return vmaddr + (fo - fileoff)
        return None

    def v2f(va):
        for _, vmaddr, vmsize, fileoff, _ in segs:
            if vmaddr <= va < vmaddr + vmsize:
                return fileoff + (va - vmaddr)
        return None

    return f2v, v2f


def patch_arm64(data, base, size):
    sl = data[base: base + size]
    segs = segments(sl)
    f2v, v2f = make_maps(segs)
    pos = sl.find(NEEDLE)
    if pos < 0:
        return None
    strva = f2v(pos)
    if strva is None:
        return None

    text = None
    for name, vmaddr, vmsize, fileoff, filesize in segs:
        if name == "__TEXT":
            text = (vmaddr, vmsize, fileoff)
    if text is None:
        return None
    tv, tsz, toff = text
    n = tsz // 4
    words = struct.unpack("<%dI" % n, sl[toff: toff + n * 4])

    hits = []
    for i in range(n - 4):
        w = words[i]
        if (w & 0x9F000000) != 0x90000000:  # adrp xd
            continue
        rd = w & 0x1F
        immlo = (w >> 29) & 3
        immhi = (w >> 5) & 0x7FFFF
        imm = (immhi << 2) | immlo
        if imm & 0x100000:
            imm -= 0x200000
        pc = tv + i * 4
        page = (pc & ~0xFFF) + (imm << 12)
        w2 = words[i + 1]
        if (w2 & 0xFFC00000) != 0x91000000:  # add xd, xn, #imm12
            continue
        if (w2 & 0x1F) != rd or ((w2 >> 5) & 0x1F) != rd:
            continue
        imm12 = (w2 >> 10) & 0xFFF
        if ((w2 >> 22) & 3) == 1:
            imm12 <<= 12
        if page + imm12 != strva:
            continue
        w3 = words[i + 2]
        if w3 != 0xD1008108:  # sub x8, x8, #0x20 (localization offset)
            continue
        hits.append(pc)

    patched = 0
    for hitva in hits:
        hitoff = v2f(hitva)
        if hitoff is None:
            continue
        # walk back to the nearest `sub sp, sp, #0x70` function prologue
        for back in range(0, 0x800, 4):
            fo = hitoff - back
            if fo < toff:
                break
            if struct.unpack("<I", sl[fo: fo + 4])[0] == 0xD101C3FF:
                data[base + fo: base + fo + 4] = RET_ARM64
                patched += 1
                break
    if patched:
        return "%d handler(s) patched (arm64)" % patched
    return None


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    with open(path, "rb") as fh:
        data = bytearray(fh.read())

    results = []
    for cputype, off, size in slices(data):
        if cputype is None or cputype == 0x0100000C:  # single or arm64
            r = patch_arm64(data, off, size)
            if r:
                results.append(r)

    if not results:
        print("piracy handler pattern not found; binary unchanged")
        return 2

    with open(path, "wb") as fh:
        fh.write(data)
    for r in results:
        print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())

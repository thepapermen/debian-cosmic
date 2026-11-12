#!/usr/bin/env python3
"""Drive a QEMU VM through its QMP socket: screenshots, keys, mouse clicks.

    vmctl.py SOCKET shot FILE.png      screenshot; prints "WxH top=F": F is the
                                       share of the most common colour (near 1.0
                                       means a blank screen). A raw copy is kept
                                       next to it as FILE.ppm for `diff`.
    vmctl.py SOCKET diff A.ppm B.ppm [X0 Y0 X1 Y1]
                                       share of pixels that differ (in the box)
    vmctl.py SOCKET bbox A.ppm B.ppm X0 Y0 X1 Y1
                                       bounding box "X0 Y0 X1 Y1" of the pixels
                                       that differ in the box, or "none"
    vmctl.py SOCKET winbox FILE.ppm    "X0 Y0 X1 Y1" of the focused window: its
                                       border has the accent colour (or "none")
    vmctl.py SOCKET type TEXT          printable ASCII without upper case
    vmctl.py SOCKET key COMBO...       e.g. ret, esc, meta_l-t, ctrl-alt-f2
    vmctl.py SOCKET usb plug IMAGE | usb unplug
                                       a USB stick (raw image) on the xhci bus
    vmctl.py SOCKET click X Y [BUTTON] click at screen pixel X,Y; BUTTON is
                                       left (default), right or middle
    vmctl.py SOCKET scroll X Y up|down [N]
                                       N mouse wheel steps (default 5) at X,Y
    vmctl.py SOCKET drag X0 Y0 X1 Y1   hold the left button from X0,Y0 to X1,Y1

Key presses and clicks go to the VM's virtual keyboard and tablet, so the guest
sees real input devices, the same as a person at the screen.
"""
import json
import os
import socket
import struct
import sys
import time
import zlib

CHARS = {
    " ": "spc", "-": "minus", ".": "dot", "/": "slash", "\n": "ret",
    ",": "comma", ";": "semicolon", "=": "equal", "'": "apostrophe",
    "[": "bracket_left", "]": "bracket_right", "\\": "backslash", "`": "grave_accent",
    ">": "shift-dot", "<": "shift-comma", "_": "shift-minus", "|": "shift-backslash",
    "&": "shift-7", "!": "shift-1", "@": "shift-2", "$": "shift-4", "*": "shift-8", ":": "shift-semicolon",
    '"': "shift-apostrophe", "(": "shift-9", ")": "shift-0", "+": "shift-equal",
}


def qmp(path, *commands):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(path)
    f = s.makefile("rw")

    def send(obj):
        f.write(json.dumps(obj) + "\n")
        f.flush()
        while True:
            reply = json.loads(f.readline())
            if "event" in reply:
                continue
            if "error" in reply:
                raise SystemExit(f"QMP {obj['execute']}: {reply['error']}")
            return reply

    json.loads(f.readline())  # greeting
    send({"execute": "qmp_capabilities"})
    replies = []
    for command, arguments in commands:
        msg = {"execute": command}
        if arguments:
            msg["arguments"] = arguments
        replies.append(send(msg))
    s.close()
    return replies


def press(path, combo):
    keys = [{"type": "qcode", "data": k} for k in combo.split("-")]
    qmp(path, ("send-key", {"keys": keys, "hold-time": 80}))
    time.sleep(0.15)


def read_ppm(name):
    with open(name, "rb") as f:
        data = f.read()
    # P6\n<w> <h>\n255\n<rgb...>
    parts = data.split(b"\n", 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def write_png(name, w, h, rgb):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body +
                struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    with open(name, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def pixels(w, h, rgb, box=None, step=2):
    x0, y0, x1, y1 = box or (0, 0, w, h)
    for y in range(max(0, y0), min(h, y1), step):
        row = y * w * 3
        for x in range(max(0, x0), min(w, x1), step):
            i = row + x * 3
            yield rgb[i:i + 3]


def shot(path, png):
    ppm = os.path.splitext(png)[0] + ".ppm"
    qmp(path, ("screendump", {"filename": os.path.abspath(ppm)}))
    w, h, rgb = read_ppm(ppm)
    write_png(png, w, h, rgb)
    counts = {}
    total = 0
    for p in pixels(w, h, rgb, step=4):
        counts[p] = counts.get(p, 0) + 1
        total += 1
    top = max(counts.values()) / total
    print(f"{w}x{h} top={top:.3f}")


def diff(a, b, box=None):
    wa, ha, ra = read_ppm(a)
    wb, hb, rb = read_ppm(b)
    if (wa, ha) != (wb, hb):
        print("1.0000")
        return
    changed = total = 0
    for p, q in zip(pixels(wa, ha, ra, box), pixels(wb, hb, rb, box)):
        total += 1
        if sum(abs(x - y) for x, y in zip(p, q)) > 24:
            changed += 1
    print(f"{changed / max(total, 1):.4f}")


def bbox(a, b, box):
    wa, ha, ra = read_ppm(a)
    wb, hb, rb = read_ppm(b)
    x0, y0, x1, y1 = box
    found = None
    for y in range(max(0, y0), min(ha, y1), 2):
        for x in range(max(0, x0), min(wa, x1), 2):
            i = (y * wa + x) * 3
            if sum(abs(p - q) for p, q in zip(ra[i:i + 3], rb[i:i + 3])) > 24:
                if found is None:
                    found = [x, y, x, y]
                else:
                    found = [min(found[0], x), min(found[1], y), max(found[2], x), max(found[3], y)]
    print(" ".join(map(str, found)) if found else "none")


ACCENT = (99, 208, 223)  # COSMIC's default accent, dark theme


def winbox(name, top=34, bottom=700):
    w, h, rgb = read_ppm(name)

    def accent(x, y):
        i = (y * w + x) * 3
        return all(abs(p - q) <= 12 for p, q in zip(rgb[i:i + 3], ACCENT))

    rows = [y for y in range(top, min(h, bottom))
            if max_run(accent(x, y) for x in range(w)) >= 300]
    cols = [x for x in range(w)
            if max_run(accent(x, y) for y in range(top, min(h, bottom))) >= 200]
    print(f"{min(cols)} {min(rows)} {max(cols)} {max(rows)}" if rows and cols else "none")


def max_run(bits):
    best = run = 0
    for b in bits:
        run = run + 1 if b else 0
        best = max(best, run)
    return best


def click(path, x, y, which="left", times=1):
    """Click (left/right/middle) at x,y; wheel-up/wheel-down scroll there."""
    tmp = f"/tmp/vmctl-size-{os.getpid()}.ppm"
    qmp(path, ("screendump", {"filename": tmp}))
    w, h, _ = read_ppm(tmp)
    os.unlink(tmp)
    ax, ay = x * 0x7FFF // (w - 1), y * 0x7FFF // (h - 1)

    def move(dx):
        return [{"type": "abs", "data": {"axis": "x", "value": ax + dx}},
                {"type": "abs", "data": {"axis": "y", "value": ay}}]

    def button(down):
        return [{"type": "btn", "data": {"down": down, "button": which}}]

    # A single motion event is sometimes lost (seen with cosmic-comp after a
    # new login), so arrive in two steps.
    qmp(path, ("input-send-event", {"events": move(8)}))
    time.sleep(0.1)
    qmp(path, ("input-send-event", {"events": move(0)}))
    time.sleep(0.2)
    for _ in range(times):
        qmp(path, ("input-send-event", {"events": button(True)}))
        time.sleep(0.08)
        qmp(path, ("input-send-event", {"events": button(False)}))
        time.sleep(0.15)


def drag(path, x0, y0, x1, y1, steps=12):
    """Press the left button at x0,y0, move to x1,y1 in steps, release."""
    tmp = f"/tmp/vmctl-size-{os.getpid()}.ppm"
    qmp(path, ("screendump", {"filename": tmp}))
    w, h, _ = read_ppm(tmp)
    os.unlink(tmp)

    def at(x, y):
        return [{"type": "abs", "data": {"axis": "x", "value": x * 0x7FFF // (w - 1)}},
                {"type": "abs", "data": {"axis": "y", "value": y * 0x7FFF // (h - 1)}}]

    qmp(path, ("input-send-event", {"events": at(x0 + 8, y0)}))
    time.sleep(0.1)
    qmp(path, ("input-send-event", {"events": at(x0, y0)}))
    time.sleep(0.2)
    qmp(path, ("input-send-event", {"events": [{"type": "btn", "data": {"down": True, "button": "left"}}]}))
    time.sleep(0.2)
    for i in range(1, steps + 1):
        qmp(path, ("input-send-event", {"events": at(x0 + (x1 - x0) * i // steps, y0 + (y1 - y0) * i // steps)}))
        time.sleep(0.04)
    time.sleep(0.2)
    qmp(path, ("input-send-event", {"events": [{"type": "btn", "data": {"down": False, "button": "left"}}]}))
    time.sleep(0.3)


def main():
    path, cmd, *args = sys.argv[1:]
    if cmd in ("screendump", "shot"):
        shot(path, args[0])
    elif cmd == "diff":
        diff(args[0], args[1], tuple(map(int, args[2:6])) if len(args) >= 6 else None)
    elif cmd == "winbox":
        winbox(args[0])
    elif cmd == "bbox":
        bbox(args[0], args[1], tuple(map(int, args[2:6])))
    elif cmd == "usb":
        # usb plug IMAGE | usb unplug: a USB stick on the VM's xhci controller
        if args[0] == "plug":
            qmp(path, ("blockdev-add", {"driver": "raw", "node-name": "stick",
                                        "file": {"driver": "file", "filename": os.path.abspath(args[1])}}),
                ("device_add", {"driver": "usb-storage", "bus": "xhci.0", "drive": "stick",
                                "id": "stick0", "removable": True}))
        else:
            qmp(path, ("device_del", {"id": "stick0"}))
            time.sleep(2)
            qmp(path, ("blockdev-del", {"node-name": "stick"}))
    elif cmd == "type":
        for ch in args[0]:
            if ch.isascii() and (ch.isdigit() or ch.islower()):
                press(path, ch)
            elif ch in CHARS:
                press(path, CHARS[ch])
            else:
                raise SystemExit(f"cannot type {ch!r}")
    elif cmd == "key":
        for combo in args:
            press(path, combo)
    elif cmd == "click":
        click(path, int(args[0]), int(args[1]), *args[2:3])
    elif cmd == "drag":
        drag(path, *map(int, args[0:4]))
    elif cmd == "scroll":
        # scroll X Y up|down [N]: N wheel steps with the pointer at X,Y
        click(path, int(args[0]), int(args[1]), "wheel-" + args[2], int(args[3]) if len(args) > 3 else 5)
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()

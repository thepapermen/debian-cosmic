#!/usr/bin/env python3
"""Drive a QEMU VM through its QMP socket: screenshots, keys, mouse clicks.

    vmctl.py SOCKET shot FILE.png      screenshot; prints "WxH top=F": F is the
                                       share of the most common colour (near 1.0
                                       means a blank screen). A raw copy is kept
                                       next to it as FILE.ppm for `diff`.
    vmctl.py SOCKET diff A.ppm B.ppm [X0 Y0 X1 Y1]
                                       share of pixels that differ (in the box)
    vmctl.py SOCKET type TEXT          printable ASCII without upper case
    vmctl.py SOCKET key COMBO...       e.g. ret, esc, meta_l-t, ctrl-alt-f2
    vmctl.py SOCKET click X Y          left click at screen pixel X,Y

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
    "&": "shift-7", "!": "shift-1", "$": "shift-4", "*": "shift-8", ":": "shift-semicolon",
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


def click(path, x, y):
    tmp = f"/tmp/vmctl-size-{os.getpid()}.ppm"
    qmp(path, ("screendump", {"filename": tmp}))
    w, h, _ = read_ppm(tmp)
    os.unlink(tmp)
    ax, ay = x * 0x7FFF // (w - 1), y * 0x7FFF // (h - 1)

    def move(dx):
        return [{"type": "abs", "data": {"axis": "x", "value": ax + dx}},
                {"type": "abs", "data": {"axis": "y", "value": ay}}]

    def button(down):
        return [{"type": "btn", "data": {"down": down, "button": "left"}}]

    # A single motion event is sometimes lost (seen with cosmic-comp after a
    # new login), so arrive in two steps.
    qmp(path, ("input-send-event", {"events": move(8)}))
    time.sleep(0.1)
    qmp(path, ("input-send-event", {"events": move(0)}))
    time.sleep(0.2)
    qmp(path, ("input-send-event", {"events": button(True)}))
    time.sleep(0.08)
    qmp(path, ("input-send-event", {"events": button(False)}))
    time.sleep(0.15)


def main():
    path, cmd, *args = sys.argv[1:]
    if cmd in ("screendump", "shot"):
        shot(path, args[0])
    elif cmd == "diff":
        diff(args[0], args[1], tuple(map(int, args[2:6])) if len(args) >= 6 else None)
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
        click(path, int(args[0]), int(args[1]))
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()

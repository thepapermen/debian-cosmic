#!/usr/bin/env python3
"""Drive a QEMU VM through its QMP socket: screenshots and key presses.

    vmctl.py SOCKET screendump FILE.png
    vmctl.py SOCKET type TEXT          (lowercase letters, digits, space, - . /)
    vmctl.py SOCKET key COMBO...       (e.g. ret, meta_l-t, ctrl-alt-f2)

Key presses go to the VM's virtual keyboard, so the guest sees a real keyboard,
the same as a person at the login screen.
"""
import json
import socket
import sys
import time

CHARS = {" ": "spc", "-": "minus", ".": "dot", "/": "slash", "\n": "ret"}


def qmp(path, command, arguments=None):
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
    msg = {"execute": command}
    if arguments:
        msg["arguments"] = arguments
    reply = send(msg)
    s.close()
    return reply


def press(path, combo):
    keys = [{"type": "qcode", "data": k} for k in combo.split("-")]
    qmp(path, "send-key", {"keys": keys, "hold-time": 80})
    time.sleep(0.15)


def main():
    path, cmd, *args = sys.argv[1:]
    if cmd == "screendump":
        qmp(path, "screendump", {"filename": args[0], "format": "png"})
    elif cmd == "type":
        for ch in args[0]:
            if ch.isalnum() and ch.isascii() and not ch.isupper():
                press(path, ch)
            elif ch in CHARS:
                press(path, CHARS[ch])
            else:
                raise SystemExit(f"cannot type {ch!r}")
    elif cmd == "key":
        for combo in args:
            press(path, combo)
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()

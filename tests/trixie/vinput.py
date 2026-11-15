#!/usr/bin/python3
# Virtual input devices for the hardware tests (hardware.sh), run as root in
# the guest: a touchpad and a keyboard with the laptop hotkeys, through uinput
# (python3-evdev). Commands come one per line from the FIFO given as the
# argument:
#   key NAME [NAME...]   press the keys together and release them (KEY_*
#                        names without the prefix, e.g. TOUCHPAD_TOGGLE)
#   move DX DY           one finger moves by DX, DY touchpad units in 20 steps
#   tap                  one-finger tap
#   scroll DY            two fingers move vertically by DY units
#   quit
# The touchpad is 100 x 66 mm (12 units per mm), on the i8042 bus as a
# laptop's built-in one is, so libinput treats it as internal.
import os
import sys
import time

from evdev import AbsInfo, UInput
from evdev import ecodes as e

W, H, RES = 1200, 800, 12
TP_CAPS = {
    e.EV_KEY: [e.BTN_LEFT, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP,
               e.BTN_TOOL_TRIPLETAP, e.BTN_TOUCH],
    e.EV_ABS: [
        (e.ABS_X, AbsInfo(0, 0, W, 0, 0, RES)),
        (e.ABS_Y, AbsInfo(0, 0, H, 0, 0, RES)),
        (e.ABS_MT_SLOT, AbsInfo(0, 0, 1, 0, 0, 0)),
        (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
        (e.ABS_MT_POSITION_X, AbsInfo(0, 0, W, 0, 0, RES)),
        (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, H, 0, 0, RES)),
    ],
}
HOTKEYS = ["TOUCHPAD_TOGGLE", "TOUCHPAD_ON", "TOUCHPAD_OFF", "F21",
           "LEFTCTRL", "LEFTMETA", "KBDILLUMUP", "KBDILLUMDOWN",
           "KBDILLUMTOGGLE", "BRIGHTNESSUP", "BRIGHTNESSDOWN", "RFKILL",
           "WLAN", "BLUETOOTH"]

tp = UInput(TP_CAPS, name="VM Test Touchpad", bustype=e.BUS_I8042,
            vendor=0x0002, product=0x0007, version=0x01b1,
            input_props=[e.INPUT_PROP_POINTER, e.INPUT_PROP_BUTTONPAD])
kb = UInput({e.EV_KEY: [getattr(e, "KEY_" + k) for k in HOTKEYS]},
            name="VM Test Hotkeys", bustype=e.BUS_I8042)
tid = 100


def frame(fingers, tool):
    """fingers: list of (x, y) or None (lifted) per slot."""
    global tid
    for slot, pos in enumerate(fingers):
        tp.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
        if pos is None:
            tp.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
            continue
        tp.write(e.EV_ABS, e.ABS_MT_POSITION_X, int(pos[0]))
        tp.write(e.EV_ABS, e.ABS_MT_POSITION_Y, int(pos[1]))
    down = [p for p in fingers if p is not None]
    if down:
        tp.write(e.EV_ABS, e.ABS_X, int(down[0][0]))
        tp.write(e.EV_ABS, e.ABS_Y, int(down[0][1]))
    tp.write(e.EV_KEY, e.BTN_TOUCH, 1 if down else 0)
    tp.write(e.EV_KEY, e.BTN_TOOL_FINGER, 1 if tool == 1 else 0)
    tp.write(e.EV_KEY, e.BTN_TOOL_DOUBLETAP, 1 if tool == 2 else 0)
    tp.syn()


def touch_down(points):
    global tid
    for slot, (x, y) in enumerate(points):
        tp.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
        tid += 1
        tp.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tid)
    frame(points, len(points))


def touch_up(n):
    frame([None] * n, 0)


def gesture(start, dx, dy, steps=20, dt=0.012):
    n = len(start)
    touch_down(start)
    time.sleep(0.03)
    for i in range(1, steps + 1):
        frame([(x + dx * i / steps, y + dy * i / steps) for x, y in start], n)
        time.sleep(dt)
    time.sleep(0.03)
    touch_up(n)


def run(cmd):
    if cmd[0] == "key":
        codes = [getattr(e, "KEY_" + k) for k in cmd[1:]]
        for c in codes:
            kb.write(e.EV_KEY, c, 1)
        kb.syn()
        time.sleep(0.05)
        for c in reversed(codes):
            kb.write(e.EV_KEY, c, 0)
        kb.syn()
    elif cmd[0] == "move":
        dx, dy = float(cmd[1]), float(cmd[2])
        gesture([(W / 2 - dx / 2, H / 2 - dy / 2)], dx, dy)
    elif cmd[0] == "tap":
        touch_down([(W / 2, H / 2)])
        time.sleep(0.05)
        touch_up(1)
    elif cmd[0] == "scroll":
        dy = float(cmd[1])
        gesture([(W / 2 - 100, H / 2 - dy / 2), (W / 2 + 100, H / 2 - dy / 2)],
                0, dy, steps=25)
    else:
        raise ValueError(cmd)


fifo = sys.argv[1]
if not os.path.exists(fifo):
    os.mkfifo(fifo, 0o600)
print("ready", flush=True)
while True:
    with open(fifo) as f:
        for line in f:
            cmd = line.split()
            if not cmd:
                continue
            if cmd[0] == "quit":
                tp.close()
                kb.close()
                sys.exit(0)
            try:
                run(cmd)
                print("done", " ".join(cmd), flush=True)
            except Exception as ex:   # keep the devices for the next command
                print("error", " ".join(cmd), ex, flush=True)

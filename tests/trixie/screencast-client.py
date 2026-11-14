#!/usr/bin/env python3
# ScreenCast portal client for the VM test: CreateSession, SelectSources
# (a monitor), Start (COSMIC shows its picker; the test clicks Share), then
# records the PipeWire stream with GStreamer for SECONDS:
#   python3 screencast-client.py SECONDS OUTDIR
# OUTDIR gets frames.txt (one line per buffer: its time in seconds), last.png
# and result.txt ("ok NODE" or "error STEP ...").
import os, subprocess, sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

secs, out = int(sys.argv[1]), sys.argv[2]
os.makedirs(out, exist_ok=True)
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
sender = bus.get_unique_name()[1:].replace(".", "_")
PORTAL, PATH, IFACE = "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.ScreenCast"
loop = GLib.MainLoop()
n = [0]

def result(text):
    open(os.path.join(out, "result.txt"), "w").write(text + "\n")

def request(method, args, sig, step):
    """Call a portal method that answers through a Request's Response signal."""
    n[0] += 1
    token = "vmtest%d" % n[0]
    path = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)
    got = {}
    def on_response(conn, snd, obj, iface, signal, params):
        got["code"], got["results"] = params.unpack()
        loop.quit()
    sub = bus.signal_subscribe(PORTAL, "org.freedesktop.portal.Request", "Response", path, None,
                               Gio.DBusSignalFlags.NO_MATCH_RULE, on_response)
    args[-1]["handle_token"] = GLib.Variant("s", token)
    bus.call_sync(PORTAL, PATH, IFACE, method, GLib.Variant(sig, tuple(args)), None, 0, -1, None)
    GLib.timeout_add_seconds(60, loop.quit)
    loop.run()
    bus.signal_unsubscribe(sub)
    if got.get("code") != 0:
        result("error %s response %s" % (step, got.get("code")))
        sys.exit(1)
    return got["results"]

r = request("CreateSession", [{"session_handle_token": GLib.Variant("s", "vmtestsession")}], "(a{sv})", "CreateSession")
session = r["session_handle"]
request("SelectSources", [session, {"types": GLib.Variant("u", 1), "multiple": GLib.Variant("b", False)}], "(oa{sv})", "SelectSources")
r = request("Start", [session, "", {}], "(osa{sv})", "Start")
node = r["streams"][0][0]
fds_out = bus.call_with_unix_fd_list_sync(PORTAL, PATH, IFACE, "OpenPipeWireRemote",
                                          GLib.Variant("(oa{sv})", (session, {})), None, 0, -1, None, None)
fd = fds_out[1].get(fds_out[0].unpack()[0])
os.dup2(fd, 3)
result("ok %d" % node)
pipe = ("pipewiresrc fd=3 path=%d always-copy=true ! tee name=t "
        "t. ! queue ! identity silent=false ! fakesink "
        "t. ! queue leaky=downstream max-size-buffers=1 ! videoconvert ! pngenc compression-level=1 ! "
        "multifilesink location=%s/last.png" % (node, out))
with open(os.path.join(out, "gst.log"), "w") as log:
    p = subprocess.Popen(["gst-launch-1.0", "-v"] + pipe.split(), stdout=log, stderr=subprocess.STDOUT, pass_fds=(3,))
    try:
        p.wait(secs)
    except subprocess.TimeoutExpired:
        p.terminate(); p.wait(10)
# identity's messages: "... pts: 0:00:01.234567890 ..." per buffer.
times = []
for line in open(os.path.join(out, "gst.log")):
    if "identity" in line and "pts: " in line:
        t = line.split("pts: ")[1].split(",")[0].strip()
        if t.count(":") == 2:
            h, m, s = t.split(":")
            times.append(int(h) * 3600 + int(m) * 60 + float(s))
open(os.path.join(out, "frames.txt"), "w").write("".join("%.3f\n" % t for t in times))

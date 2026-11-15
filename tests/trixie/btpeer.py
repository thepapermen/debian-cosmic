#!/usr/bin/python3
# The other end of the Bluetooth tests (hardware.sh), run as root in the
# guest. btvirt gives two virtual controllers that see each other; bluetoothd
# manages both, so the desktop's own one (hci0) and "VMTest Phone" (hci1)
# share it. This makes hci1 discoverable and pairable and registers an agent
# that accepts everything as BlueZ's default agent: requests for the phone's
# side go to it, as a phone would ask its own user, while pairings that the
# desktop starts still ask the desktop's agent (COSMIC's). It also lists
# AuthorizeService calls, so the test sees the phone's side of a connection.
# A serial port profile (RFCOMM), registered for both ends, gives Connect
# something to connect: a phone offers several profiles, the bare virtual
# controller none, and BlueZ drops a link without one.
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

PHONE = "/org/bluez/hci1"
AGENT = "/vmtest/btpeer"
PROFILE = "/vmtest/serial"
SPP = "00001101-0000-1000-8000-00805f9b34fb"


class Agent(dbus.service.Object):
    def log(self, *what):
        print(*what, flush=True)

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        self.log("release")

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        self.log("authorize-service", device, uuid)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        self.log("pin", device)
        return "0000"

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        self.log("passkey", device)
        return dbus.UInt32(0)

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        self.log("display-passkey", device, passkey)

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        self.log("display-pin", device, pincode)

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        self.log("confirm", device, passkey)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        self.log("authorize", device)

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        self.log("cancel")


class Profile(dbus.service.Object):
    fds = {}

    @dbus.service.method("org.bluez.Profile1", in_signature="", out_signature="")
    def Release(self):
        print("profile-release", flush=True)

    @dbus.service.method("org.bluez.Profile1", in_signature="oha{sv}", out_signature="")
    def NewConnection(self, device, fd, properties):
        self.fds[str(device)] = fd.take()          # keep it open: connected
        print("connection", device, flush=True)

    @dbus.service.method("org.bluez.Profile1", in_signature="o", out_signature="")
    def RequestDisconnection(self, device):
        fd = self.fds.pop(str(device), None)
        if fd is not None:
            import os
            os.close(fd)
        print("disconnection", device, flush=True)


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
props = dbus.Interface(bus.get_object("org.bluez", PHONE), "org.freedesktop.DBus.Properties")
for name, value in (("Powered", dbus.Boolean(True)),
                    ("Alias", dbus.String(sys.argv[1] if len(sys.argv) > 1 else "VMTest Phone")),
                    ("DiscoverableTimeout", dbus.UInt32(0)),
                    ("Discoverable", dbus.Boolean(True)),
                    ("PairableTimeout", dbus.UInt32(0)),
                    ("Pairable", dbus.Boolean(True))):
    props.Set("org.bluez.Adapter1", name, value)
Agent(bus, AGENT)
manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
manager.RegisterAgent(AGENT, "DisplayYesNo")
manager.RequestDefaultAgent(AGENT)
Profile(bus, PROFILE)
profiles = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.ProfileManager1")
profiles.RegisterProfile(PROFILE, SPP, {"Name": "VMTest Serial", "Channel": dbus.UInt16(22),
                                        "AutoConnect": True, "RequireAuthentication": False,
                                        "RequireAuthorization": False})
print("ready", flush=True)
GLib.MainLoop().run()

# Laptop hardware, simulated in the VM (sourced by vm-session.sh after
# regressions.sh): a touchpad and the hotkeys through uinput (vinput.py),
# Wi-Fi and Bluetooth through the kernel's virtual radios, the screen shared
# with Firefox. What this proves is COSMIC's side (keys, applets, Settings,
# NetworkManager, BlueZ, the portal working together), not real drivers or
# firmware. ACCEPTANCE.md lists the items; hardware is still needed for the
# brightness keys and the headset jack.

VIN=/run/vinput.fifo
# vin COMMAND...: a command for vinput.py (key NAME..., move DX DY, tap, scroll DY).
vin() { g sudo sh -c "echo $* > $VIN"; }

hw_input_setup() {
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-evdev wev libinput-tools > /dev/null 2>&1; then
        fail "[touchpad] python3-evdev, wev and libinput-tools could not be installed"
        return 1
    fi
    "${SSH[@]}" "cat > /tmp/vinput.py" < "$HERE/vinput.py"
    g sudo pkill -f 'python3 /tmp/vinput.py'
    g sudo sh -c "setsid python3 /tmp/vinput.py $VIN > /tmp/vinput.log 2>&1 < /dev/null &"
    wait_for 10 "virtual touchpad and hotkeys" grep -q ready /tmp/vinput.log || { fail "[touchpad] vinput.py did not start: $(g tail -n 3 /tmp/vinput.log)"; return 1; }
    sleep 2                              # the compositor opens the new devices
}
hw_input_stop() { vin quit; sleep 1; }

# wev, the Wayland event viewer, logs what the focused client gets; its window
# opens in the middle of the screen. wev_probe puts the pointer in it first
# (QEMU's tablet), then empties the log.
wev_start() {
    g pkill -x wev
    gs sh -c "setsid stdbuf -oL wev > /tmp/wev.log 2>&1 < /dev/null &"
    sleep 3
    ctl click 640 300
    sleep 1
}
wev_probe() { ctl move 640 300; sleep 0.5; g sh -c ": > /tmp/wev.log"; }
wev_count() { g grep -a -c "wl_pointer.*$1" /tmp/wev.log; }
# wev_scroll: the sign of the first vertical scroll value ("+", "-" or "").
wev_scroll() {
    local v
    v=$(g grep -a -o -m 1 'vertical), value: -\?[0-9]' /tmp/wev.log)
    case $v in "") echo ;; *": -"*) echo - ;; *) echo + ;; esac
}

# Touchpad hotkey (cosmic-osd TESTING.md): XF86TouchpadToggle runs
# "cosmic-osd touchpad", which sets cosmic-comp's input_touchpad_override;
# the OSD shows the touchpad's state.
hw_touchpad() {
    say "== touchpad hotkey: the touchpad off and on again, with the OSD (cosmic-osd TESTING.md) [$(elapsed)]"
    local cfg=.config/cosmic/com.system76.CosmicComp/v1/input_touchpad_override n light
    if g sudo libinput list-devices 2>/dev/null | grep -A12 'VM Test Touchpad' | grep -q 'Capabilities: *pointer gesture'; then
        ok "[touchpad] the virtual laptop touchpad is a touchpad to libinput"
    else
        fail "[touchpad] libinput does not list the virtual touchpad as one"
        return
    fi
    wev_start
    wev_probe; vin move 300 0; sleep 1.5
    n=$(wev_count motion)
    check "[touchpad] moving a finger moves the pointer ($n motion events)" [ "$n" -ge 5 ]
    shot TH0 > /dev/null
    vin key TOUCHPAD_TOGGLE
    sleep 1.5
    shot TH1-off > /dev/null
    check "[touchpad] the touchpad key turns the touchpad off (input_touchpad_override: $(g cat "$cfg" 2>&1))" \
        [ "$(g cat "$cfg" 2>/dev/null)" = ForceDisable ]
    check "[touchpad] the OSD shows that (TH1-off.png)" gt "$(changed TH0 TH1-off 553 456 727 598)" 0.5
    light=$(ctl light "$OUT/TH1-off.ppm" 580 480 700 575)
    if gt "$light" 0.02; then
        ok "[touchpad] the OSD has the touchpad-off icon"
    else
        # Its icon, touchpad-disabled-symbolic, is in the Pop icon theme that
        # COSMIC's theme inherits (Inherits=Pop,hicolor); Debian has no Pop
        # icon theme, and Adwaita, which has the icon, is not inherited.
        known_issue "[touchpad] the OSD for the touchpad off is an empty box: COSMIC's icon theme takes touchpad-disabled-symbolic from the Pop icon theme, which Debian does not have (light $light, TH1-off.png)"
    fi
    wev_probe; vin move 300 0; sleep 1.5
    n=$(wev_count motion)
    check "[touchpad] while off, a finger does not move the pointer ($n motion events)" [ "$n" -eq 0 ]
    sleep 3                              # the OSD goes
    vin key TOUCHPAD_TOGGLE
    sleep 1.5
    shot TH2-on > /dev/null
    check "[touchpad] the key again turns it back on ($(g cat "$cfg" 2>&1))" [ "$(g cat "$cfg" 2>/dev/null)" = 'r#None' ]
    check "[touchpad] the OSD shows the touchpad icon (TH2-on.png)" gt "$(ctl light "$OUT/TH2-on.ppm" 580 480 700 575)" 0.02
    wev_probe; vin move -300 0; sleep 1.5
    n=$(wev_count motion)
    check "[touchpad] then a finger moves the pointer again ($n motion events)" [ "$n" -ge 5 ]
    g pkill -x wev
    sleep 3
}

# Touchpad settings (cosmic-settings TESTING.md, Input devices): tap to click
# and natural scrolling, switched in Settings, change what a tap and a
# two-finger scroll do; switched back, they are as before.
hw_touchpad_settings() {
    say "== touchpad settings: tap to click, natural scrolling (cosmic-settings TESTING.md) [$(elapsed)]"
    local cfg=.config/cosmic/com.system76.CosmicComp/v1/input_touchpad n s
    # tp_probe NAME: "TAPS SIGN" for a tap and a two-finger scroll down.
    tp_probe() {
        wev_probe; vin tap; sleep 1.5
        n=$(wev_count 'button:.*state: 1')
        wev_probe; vin scroll 300; sleep 2
        s=$(wev_scroll)
    }
    # tp_switch NAME Y: in Settings, flip natural scrolling and tap to click
    # (its switch at Y: with tap to click off, the two tap rows below it go).
    tp_switch() {
        settings_page touchpad "$1"
        wclick 790 26                    # maximize
        sleep 2
        ctl scroll 800 500 down 10
        sleep 2
        shot "$1-page" > /dev/null
        ctl click 1135 574               # Natural scrolling, first: the rows
        sleep 1                          # move when tap to click changes
        ctl click 1135 "$2"              # Tap to click
        sleep 2
        shot "$1-switched" > /dev/null
        g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
        sleep 2
    }
    wev_start
    tp_probe
    check "[touchpad-settings] by default a tap clicks ($n press)" [ "$n" -ge 1 ]
    check "[touchpad-settings] by default two fingers moving down scroll down (not natural; sign $s)" [ "$s" = + ]
    tp_switch TS0 224
    if g grep -q 'enabled: false' "$cfg" && g grep -q 'natural_scroll: Some(true)' "$cfg"; then
        ok "[touchpad-settings] Settings has the touchpad page; tap to click off and natural scrolling on are saved"
    else
        fail "[touchpad-settings] tap to click off and natural scrolling on were not saved (TS0-switched.png): $(g cat "$cfg" 2>&1 | tr -s ' \n' ' ')"
    fi
    wev_start
    tp_probe
    check "[touchpad-settings] with tap to click off a tap does not click ($n press)" [ "$n" -eq 0 ]
    check "[touchpad-settings] with natural scrolling two fingers moving down scroll up (sign $s)" [ "$s" = - ]
    tp_switch TS1 322
    wev_start
    tp_probe
    check "[touchpad-settings] switched back, a tap clicks again ($n press)" [ "$n" -ge 1 ]
    check "[touchpad-settings] switched back, scrolling is not natural again (sign $s)" [ "$s" = + ]
    g pkill -x wev
    sleep 1
}

# Wi-Fi: mac80211_hwsim's two virtual radios. The second one goes into its
# own network namespace as the access point (hostapd, WPA2; dnsmasq for
# DHCP), so the desktop sees one Wi-Fi card and one network, VMTest-WiFi.
WIFI_SSID=VMTest-WiFi WIFI_PSK=cosmic-wifi-1
wifi_state() {                           # wifi_state STATE SECONDS
    local i s
    for i in $(seq "$2"); do
        s=$(g nmcli -t -f DEVICE,STATE device | grep '^wlan0:')
        [ "$s" = "wlan0:$1" ] && return 0
        sleep 1
    done
    return 1
}
wifi_ap() {                              # (re)start the access point
    g sudo sh -c "[ -f /run/hostapd-vm.pid ] && kill \$(cat /run/hostapd-vm.pid) 2>/dev/null; sleep 1
                  ip netns exec wifiap hostapd -B -P /run/hostapd-vm.pid /tmp/hostapd.conf >> /tmp/hostapd.log 2>&1"
}
hw_wifi_setup() {
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq hostapd dnsmasq-base iw > /dev/null 2>&1; then
        fail "[wifi] hostapd, dnsmasq-base and iw could not be installed"
        return 1
    fi
    g sudo sh -c "
        set -e
        modprobe mac80211_hwsim radios=2
        for i in \$(seq 20); do [ -e /sys/class/net/wlan1/phy80211 ] && break; sleep 0.5; done
        ip netns add wifiap
        iw phy \$(cat /sys/class/net/wlan1/phy80211/name) set netns name wifiap
        ip netns exec wifiap ip link set lo up
        ip netns exec wifiap ip addr add 10.77.0.1/24 dev wlan1
        printf '%s\n' interface=wlan1 driver=nl80211 ssid=$WIFI_SSID hw_mode=g channel=6 \
            wpa=2 wpa_key_mgmt=WPA-PSK rsn_pairwise=CCMP wpa_passphrase=$WIFI_PSK > /tmp/hostapd.conf
        ip netns exec wifiap dnsmasq --interface=wlan1 --bind-interfaces --dhcp-range=10.77.0.50,10.77.0.99,1h \
            --pid-file=/run/dnsmasq-vm.pid --no-resolv --log-facility=/run/dnsmasq-vm.log" ||
        { fail "[wifi] the virtual radios could not be set up"; return 1; }
    wifi_ap
    if ! wait_for 60 "NetworkManager sees $WIFI_SSID" sh -c "sudo nmcli -t -f SSID device wifi list --rescan yes ifname wlan0 2>/dev/null | grep -qx $WIFI_SSID"; then
        fail "[wifi] NetworkManager does not see the virtual access point ($(g tail -n 2 /tmp/hostapd.log | tr '\n' ' '))"
        return 1
    fi
}
hw_wifi_cleanup() {
    g sudo sh -c "nmcli connection delete $WIFI_SSID > /dev/null 2>&1
                  kill \$(cat /run/hostapd-vm.pid /run/dnsmasq-vm.pid) 2>/dev/null; sleep 1
                  ip netns del wifiap; modprobe -r mac80211_hwsim; rm -f /run/hostapd-vm.pid /run/dnsmasq-vm.pid"
    sleep 2
}

# Settings, Wi-Fi (cosmic-settings TESTING.md: disconnect and connect):
# connect with the password, disconnect and connect again from the network's
# menu, forget it, and connect again. Settings is opened from the launcher, as
# a user would: started over SSH it is not in the desktop session, and
# NetworkManager refuses it ("Not authorized to control networking").
hw_wifi() {
    say "== Settings, Wi-Fi: connect, disconnect, connect again, forget (cosmic-settings TESTING.md) [$(elapsed)]"
    local d
    g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    wait_gone 10 "Settings closed" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    launch_app "cosmic settings" cosmic-settings
    wait_for 20 "Settings running" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    sleep 2
    win WI0
    wclick 124 74                        # Network & wireless
    sleep 3
    shot WI1-network > /dev/null
    wclick 572 146                       # Wi-Fi, now first
    sleep 3
    wclick 790 26                        # maximize: the rows have fixed places
    sleep 3
    shot WI2-wifi > /dev/null
    ctl click 1116 311                   # Connect, on the visible network
    sleep 3
    shot WI3-prompt > /dev/null
    ctl type "$WIFI_PSK"                 # the password field has the focus
    sleep 1
    shot WI4-typed > /dev/null
    check "[wifi] the password prompt takes the password without a click (WI4-typed.png)" \
        gt "$(ctl light "$OUT/WI4-typed.ppm" 500 388 860 410)" 0.003
    ctl key ret
    if wifi_state connected 40 && g ping -c 1 -W 3 10.77.0.1 > /dev/null; then
        ok "[wifi] Connect and the password in Settings connect to $WIFI_SSID ($(g ip -4 -o addr show wlan0 | awk '{ print $4 }'))"
    else
        fail "[wifi] Settings did not connect to $WIFI_SSID (WI3-prompt.png, WI4-typed.png; $(g nmcli -t -f DEVICE,STATE device | grep '^wlan0:'))"
        hw_settings_close
        return
    fi
    sleep 3
    shot WI5-connected > /dev/null
    ctl click 1143 298                   # the network's menu
    sleep 2
    shot WI6-menu > /dev/null
    ctl click 1091 337                   # Disconnect
    if wifi_state disconnected 15; then
        ok "[wifi] Disconnect in the network's menu disconnects"
    else
        fail "[wifi] Disconnect in the network's menu did not disconnect (WI6-menu.png)"
    fi
    sleep 12                             # the row shows Connect again
    shot WI7-disconnected > /dev/null
    ctl click 1077 298                   # Connect, on the known network
    if wifi_state connected 40; then
        ok "[wifi] Connect on the known network connects again, without the password"
    else
        fail "[wifi] Connect on the known network did not connect (WI7-disconnected.png)"
    fi
    sleep 3
    ctl click 1143 298
    sleep 2
    ctl click 1118 424                   # Forget this network
    sleep 2
    shot WI8-forget > /dev/null
    # A key typed with this confirmation open should not reach Settings
    # behind it (it has no text field of its own).
    ctl key x
    sleep 1
    shot WI9-key > /dev/null
    d=$(changed WI8-forget WI9-key 60 40 300 70)
    ctl click 863 438                    # Forget
    if wifi_state disconnected 15 && ! g nmcli -t -f NAME connection show | grep -qx "$WIFI_SSID"; then
        ok "[wifi] Forget (confirmed) disconnects and removes the network's profile"
    else
        fail "[wifi] Forget did not remove the network (WI8-forget.png)"
    fi
    if gt "$d" 0.05; then
        known_issue "[focus] a key typed while Settings' \"Forget this Wi-Fi network?\" dialog is open goes into the search field behind it (WI9-key.png; not confirmed upstream)"
        ctl click 276 55                 # clear the search: the Wi-Fi page is back
        sleep 2
    fi
    sleep 8
    shot WI10-forgotten > /dev/null
    ctl click 1116 311                   # Connect: the password again
    sleep 3
    ctl type "$WIFI_PSK"
    ctl key ret
    if wifi_state connected 40; then
        ok "[wifi] after Forget, Connect asks for the password again and connects"
    else
        fail "[wifi] after Forget, Connect with the password did not connect (WI10-forgotten.png)"
    fi
    hw_settings_close
}
hw_settings_close() {
    g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    sleep 2
}

# Airplane mode hotkey (cosmic-osd TESTING.md). The kernel itself handles
# KEY_RFKILL (Debian's kernel has CONFIG_RFKILL_INPUT) and blocks every radio;
# cosmic-osd watches rfkill and shows the airplane OSD. The access point's
# radio is blocked too (one machine), and hostapd does not recover from it:
# it is started again, as a router would just keep sending.
# wifi_soft: wlan0's rfkill soft block, 1 or 0 (the rfkill number changes
# each time the module is loaded).
wifi_soft() { g sh -c 'cat /sys/class/net/wlan0/phy80211/rfkill*/soft'; }
hw_airplane() {
    say "== airplane mode hotkey: the radios off and on, with the OSD; Wi-Fi comes back (cosmic-osd TESTING.md) [$(elapsed)]"
    shot AI0 > /dev/null
    vin key RFKILL
    sleep 1
    shot AI1-on > /dev/null
    if [ "$(wifi_soft)" = 1 ] && wifi_state unavailable 10; then
        ok "[airplane] the airplane mode key turns the radios off; Wi-Fi goes"
    else
        fail "[airplane] the airplane mode key did not turn Wi-Fi off (rfkill soft $(wifi_soft); $(g nmcli -t -f DEVICE,STATE device | grep '^wlan0:'))"
    fi
    check "[airplane] the OSD shows airplane mode (AI1-on.png)" \
        gt "$(ctl light "$OUT/AI1-on.ppm" 580 480 700 575)" 0.02
    sleep 4                              # the OSD goes
    vin key RFKILL
    sleep 1
    shot AI2-off > /dev/null
    check "[airplane] the key again turns the radios on (rfkill soft $(wifi_soft))" \
        [ "$(wifi_soft)" = 0 ]
    check "[airplane] the OSD shows airplane mode off (AI2-off.png)" \
        gt "$(ctl light "$OUT/AI2-off.ppm" 580 480 700 575)" 0.02
    wifi_ap
    if wifi_state connected 60; then
        ok "[airplane] Wi-Fi connects again by itself"
    else
        fail "[airplane] Wi-Fi did not connect again after airplane mode ($(g nmcli -t -f DEVICE,STATE device | grep '^wlan0:'))"
    fi
}

# Bluetooth: btvirt (bluez-test-tools) makes two virtual controllers that see
# each other. hci0 is the laptop's; hci1 is the phone (btpeer.py), which
# bluetoothd manages too, so Settings lists it as a second adapter and
# COSMIC's agent may be asked to confirm the phone's side of a pairing: the
# test confirms, as the phone's user would. With PipeWire's Bluetooth plugin
# both ends offer audio profiles, so the phone connects as an audio device.
BT_PHONE=00:AA:01:01:00:01 BT_NAME="VMTest Phone, the other end"
# The phone as the laptop's adapter sees it. (bluetoothctl's "devices" and
# "info" use its default controller, which can be the phone's.)
BT_DEV=/org/bluez/hci0/dev_00_AA_01_01_00_01
bt_prop() { g busctl get-property org.bluez "$BT_DEV" org.bluez.Device1 "$1" 2>/dev/null | awk '{ print $2 }'; }
bt_info() { echo "paired=$(bt_prop Paired) connected=$(bt_prop Connected)"; }
bt_wait() {                              # bt_wait PROPERTY VALUE SECONDS
    local i
    for i in $(seq "$3"); do
        [ "$(bt_prop "$1")" = "$2" ] && return 0
        sleep 1
    done
    return 1
}
# bt_pair_wait SECONDS: until the phone is paired and connected, confirming
# COSMIC's "Confirm Bluetooth PIN" dialog whenever it shows. Which agent
# BlueZ asks for which side varies (both ends are one bluetoothd): the number
# of dialogs is reported, not required.
bt_pair_wait() {
    local i info n=0
    for i in $(seq "$1"); do
        [ "$(bt_info)" = "paired=true connected=true" ] && { BT_DIALOGS=$n; return 0; }
        ctl shot "$OUT/BT-poll.png" > /dev/null
        if gt "$(ctl light "$OUT/BT-poll.ppm" 380 280 900 310)" 0.01; then
            n=$((n + 1))
            cp "$OUT/BT-poll.png" "$OUT/BL-confirm-$n.png"
            ctl click 857 472            # Confirm
        fi
        sleep 1
    done
    BT_DIALOGS=$n
    return 1
}
# bt_connect: press Connect on the phone (under Nearby devices, or, once
# paired, under Previously connected devices) until it is paired and
# connected, twice at most. Both ends are one bluetoothd and one PipeWire,
# whose audio profiles race each other: a user would press Connect again.
bt_connect() {
    local try
    for try in 1 2; do
        if [ "$(bt_prop Paired)" = true ]; then ctl click 1072 298; else ctl click 1116 298; fi
        bt_pair_wait 30 && return 0
        shot "BL-retry-$1" > /dev/null
        [ "$try" = 1 ] && say "  not paired and connected after 30s ($(bt_info), BL-retry-$1.png): Connect again"
    done
    return 1
}
# bt_row SHOT: wait (30 s at most) until Settings draws the phone's row; the
# page lags BlueZ by some seconds.
bt_row() {
    local i
    for i in $(seq 15); do
        ctl shot "$OUT/$1.png" > /dev/null
        gt "$(ctl light "$OUT/$1.ppm" 430 288 700 310 150)" 0.01 && return 0
        sleep 2
    done
    return 1
}
hw_bt_setup() {
    say "  bluez, bluez-test-tools and libspa-0.2-bluetooth installed for the test (the package pulls in none of them)"
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bluez bluez-test-tools libspa-0.2-bluetooth > /dev/null 2>&1; then
        fail "[bluetooth] bluez, bluez-test-tools and libspa-0.2-bluetooth could not be installed"
        return 1
    fi
    gs systemctl --user restart wireplumber
    g sudo modprobe hci_vhci
    local try
    for try in 1 2; do                   # (once, btvirt did not start)
        g sudo sh -c "pkill -x btvirt; setsid btvirt -l2 > /tmp/btvirt.log 2>&1 < /dev/null &"
        wait_for 15 "two virtual Bluetooth controllers" sh -c '[ "$(bluetoothctl list | grep -c Controller)" = 2 ]' && break
    done
    if [ "$(g bluetoothctl list | grep -c Controller)" != 2 ]; then
        fail "[bluetooth] btvirt made no controllers ($(g tail -n 2 /tmp/btvirt.log | tr '\n' ' '))"
        return 1
    fi
    "${SSH[@]}" "cat > /tmp/btpeer.py" < "$HERE/btpeer.py"
    # Named before Settings opens (btpeer.py, started later, sets it again).
    g sudo busctl set-property org.bluez /org/bluez/hci1 org.bluez.Adapter1 Alias s "$BT_NAME"
    sleep 3                              # WirePlumber registers its profiles
}
hw_bt_cleanup() {
    g sudo busctl call org.bluez /org/bluez/hci0 org.bluez.Adapter1 RemoveDevice o "$BT_DEV" > /dev/null 2>&1
    g sudo pkill -f 'python3 /tmp/btpeer.py'
    g sudo pkill -x btvirt
    sleep 2
    g sudo modprobe -r hci_vhci
}

# Settings, Bluetooth (cosmic-settings TESTING.md): connect (pairing),
# disconnect and connect again, forget and pair again.
hw_bluetooth() {
    say "== Settings, Bluetooth: pair and connect, disconnect, connect again, forget, pair again (cosmic-settings TESTING.md) [$(elapsed)]"
    g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    wait_gone 10 "Settings closed" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    launch_app "cosmic settings" cosmic-settings
    wait_for 20 "Settings running" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    sleep 2
    win BL0
    wclick 124 114                       # Bluetooth
    sleep 3
    wclick 790 26                        # maximize
    sleep 3
    shot BL1-adapters > /dev/null
    # The two adapters, in no fixed order. The phone's page must not be
    # opened: it starts a scan on the phone's controller that outlives the
    # page, and a scanning controller is not found by others. Its long name
    # tells its row: text right of x=600.
    local r272 r321
    r272=$(ctl light "$OUT/BL1-adapters.ppm" 600 262 760 284 150)
    r321=$(ctl light "$OUT/BL1-adapters.ppm" 600 311 760 333 150)
    if gt "$r272" "$r321"; then ctl click 783 321; else ctl click 783 272; fi
    sleep 5
    shot BL2-adapter > /dev/null
    disc() { g busctl get-property org.bluez "/org/bluez/$1" org.bluez.Adapter1 Discovering | awk '{ print $2 }'; }
    laptop_page() { [ "$(disc hci0)" = true ]; }
    check "[bluetooth] the laptop's adapter page scans for devices (BL2-adapter.png)" laptop_page
    # The phone's agent, registered after Settings' own.
    g sudo sh -c "setsid python3 /tmp/btpeer.py '$BT_NAME' > /tmp/btpeer.log 2>&1 < /dev/null &"
    wait_for 10 "the virtual phone" grep -q ready /tmp/btpeer.log
    if wait_for 60 "the phone found" busctl introspect org.bluez "$BT_DEV"; then
        ok "[bluetooth] the laptop's adapter finds the phone"
    else
        fail "[bluetooth] the laptop's adapter does not find the virtual phone (BL2-adapter.png)"
        hw_settings_close
        return
    fi
    bt_row BL3-found || say "  the phone's row not drawn after 30s (BL3-found.png)"
    if bt_connect first; then
        ok "[bluetooth] Connect pairs and connects (confirmation dialogs: $BT_DIALOGS)"
    else
        fail "[bluetooth] Connect did not pair and connect the phone (BL3-found.png; $(bt_info))"
        hw_settings_close
        return
    fi
    # (Informational: which audio profile wins between the two ends varies.)
    say "  the phone's audio devices in PipeWire: $(gs pactl list short sinks | grep -c bluez_output) output(s), $(gs pactl list short sources | grep -v monitor | grep -c bluez_input) input(s)"
    sleep 8                              # still connected a while later
    check "[bluetooth] it stays connected" [ "$(bt_prop Connected)" = true ]
    shot BL4-connected > /dev/null
    ctl click 1143 298                   # the device's menu
    sleep 2
    shot BL5-menu > /dev/null
    ctl click 1091 337                   # Disconnect
    if bt_wait Connected false 15; then ok "[bluetooth] Disconnect in the device's menu disconnects"; else fail "[bluetooth] Disconnect did not disconnect (BL5-menu.png)"; fi
    sleep 3
    shot BL6-disconnected > /dev/null
    if bt_connect reconnect; then        # Connect, on the paired device
        ok "[bluetooth] Connect on the paired device connects again"
    else
        fail "[bluetooth] Connect on the paired device did not connect (BL6-disconnected.png)"
    fi
    sleep 3
    ctl click 1143 298
    sleep 2
    ctl click 1077 395                   # Forget
    sleep 3
    shot BL7-forgotten > /dev/null
    if [ "$(bt_prop Paired)" != true ]; then
        ok "[bluetooth] Forget removes the pairing"
    else
        fail "[bluetooth] Forget did not remove the pairing (BL7-forgotten.png)"
    fi
    # The phone forgets the laptop too (with its old key it did not pair again
    # in two runs of three: both ends are one bluetoothd), then comes back
    # under Nearby devices once the scan finds it again.
    g sudo busctl call org.bluez /org/bluez/hci1 org.bluez.Adapter1 RemoveDevice o /org/bluez/hci1/dev_00_AA_01_00_00_00 > /dev/null 2>&1
    if wait_for 60 "the phone found again" busctl introspect org.bluez "$BT_DEV"; then
        bt_row BL8-again || say "  the phone's row not drawn after 30s (BL8-again.png)"
        if bt_connect again; then
            ok "[bluetooth] after Forget it pairs and connects again"
        else
            fail "[bluetooth] after Forget it did not pair again (BL8-again.png)"
        fi
    else
        fail "[bluetooth] after Forget the phone was not found again"
    fi
    hw_settings_close
}

hardware() {
    hw_input_setup || return
    hw_touchpad
    hw_touchpad_settings
    if hw_wifi_setup; then
        hw_wifi
        hw_airplane
    fi
    hw_wifi_cleanup
    if hw_bt_setup; then
        hw_bluetooth
    fi
    hw_bt_cleanup
    hw_input_stop
}

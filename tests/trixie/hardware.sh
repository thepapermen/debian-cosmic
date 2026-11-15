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

hardware() {
    hw_input_setup || return
    hw_touchpad
    hw_touchpad_settings
    if hw_wifi_setup; then
        hw_wifi
        hw_airplane
    fi
    hw_wifi_cleanup
    hw_input_stop
}

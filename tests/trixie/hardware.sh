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
    # Its icon, touchpad-disabled-symbolic, is in the Pop icon theme that
    # COSMIC's theme inherits; Debian has no Pop icon theme. Builds from
    # 2026-11-16 on add Adwaita, which has it (Inherits=Pop,Adwaita,hicolor).
    local inherits
    inherits=$(g sed -n 's/^Inherits=//p' /usr/share/icons/Cosmic/index.theme)
    if gt "$light" 0.02; then
        ok "[touchpad] the OSD has the touchpad-off icon (Inherits=$inherits)"
    else
        case ",$inherits," in
            *,Adwaita,*)
                fail "[touchpad] the OSD for the touchpad off is an empty box although COSMIC's icon theme inherits Adwaita (Inherits=$inherits; adwaita-icon-theme: $(g dpkg-query -W -f='${db:Status-Status}' adwaita-icon-theme 2>&1); light $light, TH1-off.png)" ;;
            *)
                known_issue "[touchpad] the OSD for the touchpad off is an empty box: COSMIC's icon theme takes touchpad-disabled-symbolic from the Pop icon theme, which Debian does not have (Inherits=$inherits; light $light, TH1-off.png)" ;;
        esac
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
    local p st missing=
    # Builds from 2026-11-16 on recommend bluez and libspa-0.2-bluetooth:
    # apt has installed them with the package.
    if g dpkg-query -W -f='${Recommends}' cosmic-epoch-monorepo | grep -q -E '(^|[ ,])bluez([ ,]|$)'; then
        for p in bluez libspa-0.2-bluetooth; do
            st=$(g dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)
            [ "$st" = installed ] || missing+=" $p"
        done
        check "[bluetooth] the package's Recommends brought bluez and libspa-0.2-bluetooth${missing:+ (missing:$missing)}" [ -z "$missing" ]
        say "  bluez-test-tools installed for the test (btvirt)"
    else
        say "  bluez, bluez-test-tools and libspa-0.2-bluetooth installed for the test (this build recommends none of them)"
    fi
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

# Webcam and screen sharing prompted through Firefox (xdg-desktop-portal-cosmic
# TESTING.md). A local page (share.html, served on 127.0.0.1) asks for the
# screen and the camera; what it gets goes back to its server's log. Firefox
# takes the screen through the ScreenCast portal (Firefox's prompt, then
# COSMIC's picker) only with XDG_SESSION_TYPE=wayland, as in the desktop
# session (over SSH it is "tty"). The camera: a GStreamer test pattern as a
# PipeWire camera node; the Camera portal asks COSMIC's Access dialog, once
# per Firefox process and until the answer is stored.
FF_LOG=/tmp/share/server.log
ff_start() {                             # ff_start NAME: Firefox, a new profile
    g pkill -u tester -x firefox-esr
    sleep 3
    g sh -c "mkdir -p /tmp/ff-$1 && cp /tmp/share/user.js /tmp/ff-$1/"
    local n
    n=$(g grep -c 'report?loaded' "$FF_LOG")
    gs sh -c "XDG_SESSION_TYPE=wayland setsid firefox-esr --profile /tmp/ff-$1 --new-instance http://127.0.0.1:8765/share.html < /dev/null > /tmp/ff-$1.log 2>&1 &"
    wait_for 60 "Firefox with the page" sh -c "[ \$(grep -c 'report?loaded' $FF_LOG) -gt $n ]"
    sleep 3
}
ff_report() { wait_for "$2" "the page's report" grep -q "report?$1" "$FF_LOG"; }
ff_last() { g grep -o 'GET /report?[^ ]*' "$FF_LOG" | tail -n 1 | sed 's/^GET .report?//; s/%20/ /g; s/%3D/=/g'; }
cam_perm() {                             # cam_perm delete | cam_perm lookup
    if [ "$1" = delete ]; then
        g env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus busctl --user call org.freedesktop.impl.portal.PermissionStore \
            /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore Delete ss devices camera > /dev/null 2>&1
    else
        g env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus busctl --user call org.freedesktop.impl.portal.PermissionStore \
            /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore Lookup ss devices camera 2>/dev/null |
            grep -o '"yes"\|"no"' | tr -d '"'
    fi
}
hw_firefox_setup() {
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq firefox-esr gstreamer1.0-pipewire gstreamer1.0-tools > /dev/null 2>&1; then
        fail "[firefox] firefox-esr and the GStreamer PipeWire elements could not be installed"
        return 1
    fi
    g mkdir -p /tmp/share
    "${SSH[@]}" "cat > /tmp/share/share.html" < "$HERE/share.html"
    g sh -c 'printf "%s\n" "user_pref(\"browser.shell.checkDefaultBrowser\", false);" \
        "user_pref(\"browser.startup.homepage_override.mstone\", \"ignore\");" "user_pref(\"browser.aboutwelcome.enabled\", false);" \
        "user_pref(\"datareporting.policy.dataSubmissionEnabled\", false);" "user_pref(\"toolkit.telemetry.reportingpolicy.firstRun\", false);" \
        "user_pref(\"app.update.enabled\", false);" "user_pref(\"media.webrtc.camera.allow-pipewire\", true);" > /tmp/share/user.js'
    g sh -c "setsid python3 -m http.server --bind 127.0.0.1 8765 --directory /tmp/share > $FF_LOG 2>&1 < /dev/null &"
    local cam="videotestsrc is-live=true pattern=ball ! video/x-raw,width=640,height=480,framerate=15/1 ! videoconvert"
    cam+=' ! pipewiresink mode=provide stream-properties="props,media.class=Video/Source,media.role=Camera,node.name=vmtest-camera,node.description=VMTest-Camera"'
    gs sh -c "setsid gst-launch-1.0 -q $cam < /dev/null > /tmp/cam.log 2>&1 &"
    wait_for 15 "the virtual camera in PipeWire" sh -c 'XDG_RUNTIME_DIR=/run/user/1000 wpctl status | grep -q VMTest-Camera' ||
        { fail "[firefox] the virtual camera did not start ($(g tail -n 2 /tmp/cam.log | tr '\n' ' '))"; return 1; }
}
hw_firefox_cleanup() {
    g pkill -u tester -x firefox-esr
    g pkill -u tester -f 'gst-launch-1.0 -q videotestsrc'
    g pkill -u tester -f 'http.server --bind 127.0.0.1 8765'
    cam_perm delete
    sleep 2
}
hw_firefox() {
    say "== Firefox: the screen shared through COSMIC's picker; the camera through its Access dialog (xdg-desktop-portal-cosmic TESTING.md) [$(elapsed)]"
    local r
    ff_start screen
    shot FX0 > /dev/null
    ctl click 320 420                    # Share the screen
    sleep 4
    shot FX1-firefox > /dev/null
    ctl click 655 246                    # Allow, in Firefox's prompt
    sleep 4
    shot FX2-picker > /dev/null
    check "[firefox] Firefox's request opens COSMIC's screen picker (FX2-picker.png)" \
        gt "$(ctl light "$OUT/FX2-picker.ppm" 379 115 600 145)" 0.05
    ctl click 640 420                    # the output, Virtual-1
    sleep 1
    ctl click 866 632                    # Share
    if ff_report 'screen%20ok' 20; then
        r=$(ff_last)
        sleep 1
        shot FX3-shared > /dev/null
        if grep -q 'video=1280x800' <<< "$r" && gt "$(changed FX0 FX3-shared 952 520 1272 720)" 0.3; then
            ok "[firefox] the page gets the screen, 1280x800, and shows it ($r)"
        else
            fail "[firefox] the shared screen did not reach the page (FX3-shared.png; $r)"
        fi
    else
        fail "[firefox] sharing the screen gave the page nothing (FX2-picker.png; $(ff_last))"
    fi
    sleep 4                              # the page stops the stream
    ctl click 320 420                    # again, and Cancel in the picker
    sleep 4
    ctl click 655 246
    sleep 4
    shot FX4-picker > /dev/null
    ctl click 785 632                    # Cancel
    if ff_report 'screen%20error%20NotAllowedError' 15; then
        ok "[firefox] Cancel in the picker refuses the page (NotAllowedError)"
    else
        fail "[firefox] Cancel in the picker: the page got $(ff_last) (FX4-picker.png)"
    fi
    # The camera, refused and then allowed, each in a new Firefox.
    cam_perm delete
    ff_start camera1
    ctl click 960 420                    # Use the camera
    sleep 4
    shot FX5-access > /dev/null
    check "[firefox] the camera request opens COSMIC's \"Allow app to Use the Camera?\" (FX5-access.png)" \
        gt "$(ctl light "$OUT/FX5-access.ppm" 459 290 820 320)" 0.05
    ctl click 788 458                    # Cancel
    if ff_report 'camera%20error%20NotAllowedError' 15 && [ "$(cam_perm lookup)" = no ]; then
        ok "[firefox] Cancel refuses the camera; the portal keeps \"no\""
    else
        fail "[firefox] Cancel in the camera dialog: the page got $(ff_last), the portal keeps \"$(cam_perm lookup)\""
    fi
    cam_perm delete
    ff_start camera2
    ctl click 960 420
    sleep 4
    shot FX6-access > /dev/null
    ctl click 867 458                    # Allow
    sleep 5
    if [ "$(cam_perm lookup)" = yes ] && ! ff_last | grep -q NotAllowedError; then
        ok "[firefox] Allow gives the camera to the app; the portal keeps \"yes\""
    else
        fail "[firefox] Allow in the camera dialog: the portal keeps \"$(cam_perm lookup)\", the page got $(ff_last) (FX6-access.png)"
    fi
    # Firefox does not take the test pattern node as a camera (NotFoundError):
    # the camera stream itself needs a real webcam.
    say "  the page, with the camera allowed: $(ff_last) (a real webcam is still a hardware item)"
}

# Keyboard backlight hotkeys (cosmic-osd TESTING.md). vmtest_backlight.c,
# built in the guest, gives a keyboard backlight LED (levels 0-3) and a screen
# backlight. COSMIC does not set the keyboard backlight on the keys itself:
# KeyboardBrightnessUp/Down are commented out in cosmic-settings-daemon's
# system actions (cosmic-epoch#3872, cosmic-settings-daemon#115, open).
# Where the firmware handles the key and the kernel tells (the module's
# kbd_hw), UPower passes the level on and cosmic-osd shows it; the power
# applet has a slider for it. A laptop has the LED from boot: the OSD and the
# panel start again after it is loaded, and again after it is gone.
KBD_HW=/sys/module/vmtest_backlight/parameters/kbd_hw
kbd_upower() { g busctl call org.freedesktop.UPower /org/freedesktop/UPower/KbdBacklight org.freedesktop.UPower.KbdBacklight GetBrightness 2>/dev/null | awk '{ print $2 }'; }
hw_shell_restart() {                     # cosmic-osd and the panel see the devices
    local start
    start=$(g date +%s)
    g pkill -u tester -x cosmic-osd
    g pkill -u tester -x cosmic-panel
    sleep 2
    wait_for 30 "cosmic-osd again" pgrep -u tester -x cosmic-osd
    wait_for 30 "the panel again" pgrep -u tester -f cosmic-applet-battery
    sleep 5
    add_window "$start" "$(g date +%s)"
}
hw_kbd_setup() {
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "linux-headers-$(g uname -r)" gcc make libc6-dev > /dev/null 2>&1; then
        fail "[kbd-backlight] the kernel headers and gcc could not be installed"
        return 1
    fi
    g mkdir -p /tmp/vmbl
    "${SSH[@]}" "cat > /tmp/vmbl/vmtest_backlight.c" < "$HERE/vmtest_backlight.c"
    if ! g sh -c 'cd /tmp/vmbl && echo "obj-m := vmtest_backlight.o" > Kbuild && make -s -C /lib/modules/$(uname -r)/build M=/tmp/vmbl modules > build.log 2>&1' ||
       ! g sudo insmod /tmp/vmbl/vmtest_backlight.ko; then
        fail "[kbd-backlight] the backlight module did not build or load: $(g tail -n 3 /tmp/vmbl/build.log | tr '\n' ' ')"
        return 1
    fi
    g sudo systemctl restart upower
    sleep 2
    hw_shell_restart
}
hw_kbd_cleanup() {
    g sudo rmmod vmtest_backlight 2> /dev/null && { g sudo systemctl restart upower; sleep 2; hw_shell_restart; }
}
hw_kbd_backlight() {
    say "== keyboard backlight: the laptop's key (firmware), the keys as key codes, the power applet's slider (cosmic-osd TESTING.md) [$(elapsed)]"
    local l f
    check "[kbd-backlight] UPower finds the keyboard backlight (levels 0-$(g busctl call org.freedesktop.UPower /org/freedesktop/UPower/KbdBacklight org.freedesktop.UPower.KbdBacklight GetMaxBrightness 2>/dev/null | awk '{ print $2 }'))" \
        [ "$(g busctl call org.freedesktop.UPower /org/freedesktop/UPower/KbdBacklight org.freedesktop.UPower.KbdBacklight GetMaxBrightness 2>/dev/null | awk '{ print $2 }')" = 3 ]
    for l in 3 0 2; do
        shot "KL$l-before" > /dev/null
        g sudo sh -c "echo $l > $KBD_HW"
        sleep 0.8
        shot "KL$l-osd" > /dev/null
        f=$(ctl fill "$OUT/KL$l-osd.ppm" 543 809 574)
        if [ "$(kbd_upower)" = "$l" ] && gt "$(changed "KL$l-before" "KL$l-osd" 445 548 835 600)" 0.2 &&
           awk -v f="$f" -v l="$l" 'BEGIN { exit !(f > l / 3 - 0.06 && f < l / 3 + 0.06) }'; then
            ok "[kbd-backlight] the laptop's key sets level $l: UPower has it, the OSD shows $(( l * 100 / 3 ))% (bar $f)"
        else
            fail "[kbd-backlight] level $l from the laptop's key: UPower $(kbd_upower), OSD bar $f (KL$l-osd.png)"
        fi
        sleep 3                          # the OSD goes
    done
    # The keys as key codes, which some laptops send for the desktop to act.
    vin key KBDILLUMUP
    sleep 1
    if [ "$(kbd_upower)" = 2 ]; then
        known_issue "[kbd-backlight] the keyboard backlight keys as key codes (KEY_KBDILLUMUP) change nothing: COSMIC has no action for them (cosmic-epoch#3872, cosmic-settings-daemon#115)"
    else
        ok "[kbd-backlight] the keyboard backlight up key raises the level ($(kbd_upower))"
    fi
    # The power applet's slider: level 3 at its right end.
    ctl click 1191 15                    # the power applet
    sleep 2
    shot KL-applet > /dev/null
    ctl click 1190 285
    sleep 2
    l=$(g cat /sys/class/leds/vmtest::kbd_backlight/brightness)
    check "[kbd-backlight] the power applet's keyboard slider sets the backlight (LED $l, UPower $(kbd_upower); KL-applet.png)" [ "$l" = 3 ]
    ctl key esc
    sleep 1
}

# Screen brightness (ACCEPTANCE.md osd 3): the module's screen backlight
# (vmtest_backlight.c) stands for the laptop's panel, reloaded with the
# levels of different panels. cosmic-settings-daemon picks the backlight,
# turns the brightness keys into 5% steps and sets the level through logind;
# cosmic-osd and the power applet show it. COSMIC 1.11's Settings has no
# brightness control. What the VM cannot show: a real panel driver, monitors
# over DDC/CI, and whether a laptop's keys send these key codes.
BL=/sys/class/backlight/vmtest_backlight
BL2=/sys/class/backlight/vmtest_backlight2
BL_HW=/sys/module/vmtest_backlight/parameters/bl_hw
bl_now() { g cat "${1:-$BL}/brightness"; }
bl_daemon() {
    gs busctl --user get-property com.system76.CosmicSettingsDaemon /com/system76/CosmicSettingsDaemon \
        com.system76.CosmicSettingsDaemon "$1" 2> /dev/null | awk '{ print $2 }'
}
# bl_set LEVEL [DEVICE]: as root, then wait for the OSD it shows to go.
bl_set() { g sudo sh -c "echo $1 > ${2:-$BL}/brightness"; sleep 4; }
# bl_press KEY [N]: press a brightness key N times; prints the level after.
bl_press() {
    local i
    for i in $(seq "${2:-1}"); do vin key "$1"; sleep 0.5; done
    sleep 0.3
    bl_now "${3:-$BL}"
}
near() { awk -v a="$1" -v b="$2" -v d="${3:-0.04}" 'BEGIN { exit !(a > b - d && a < b + d) }'; }
# bl_load [MODULE PARAMETERS...]: the module again with these backlights;
# with "restart", cosmic-osd and the panel start again too (they keep the
# maximum level from when they started).
bl_load() {
    local restart=
    [ "${1:-}" = restart ] && { restart=1; shift; }
    g sudo rmmod vmtest_backlight 2> /dev/null
    if ! g sudo insmod /tmp/vmbl/vmtest_backlight.ko "$@"; then
        fail "[brightness] the backlight module did not load ($*)"
        return 1
    fi
    g udevadm settle
    sleep 2
    [ -z "$restart" ] || hw_shell_restart
}
# bl_osd NAME: screenshot NAME, print the fill of the OSD's bar (0..1).
bl_osd() { shot "$1" > /dev/null; ctl fill "$OUT/$1.ppm" 543 809 574; }
hw_brightness() {
    say "== screen brightness: keys, OSD, power applet, firmware keys, panels of 10, 100 and 255 levels, two backlights (cosmic-osd TESTING.md) [$(elapsed)]"
    local l l2 f max
    bl_load restart bl_max=100 || return
    check "[brightness] the settings daemon uses the laptop's backlight (levels 0-$(bl_daemon MaxDisplayBrightness))" \
        [ "$(bl_daemon MaxDisplayBrightness)" = 100 ]
    # The keys: 5% steps; the OSD shows the level.
    bl_set 50
    shot SB0 > /dev/null
    l=$(bl_press BRIGHTNESSUP)
    f=$(bl_osd SB1-up)
    if [ "$l" = 55 ] && gt "$(changed SB0 SB1-up 445 548 835 600)" 0.2 && near "$f" 0.55; then
        ok "[brightness] Brightness Up raises 50 to 55 (of 100), the OSD shows 55% (bar $f)"
    else
        fail "[brightness] Brightness Up from 50 (of 100): level $l, OSD bar $f (SB1-up.png)"
    fi
    sleep 3
    l=$(bl_press BRIGHTNESSDOWN 2)
    check "[brightness] Brightness Down twice lowers 55 to 45" [ "$l" = 45 ]
    # The lowest level: 1, never off (more than 20 levels).
    bl_set 10
    l=$(bl_press BRIGHTNESSDOWN)
    l2=$(bl_press BRIGHTNESSDOWN 2)
    check "[brightness] Brightness Down from 10 goes to 5, then stops at 1: the screen does not go off ($l, then $l2)" \
        [ "$l" = 5 ] && [ "$l2" = 1 ]
    sleep 3
    # The firmware handles the key itself on many laptops (ACPI): the OSD shows
    # the new level all the same.
    shot SB2-before > /dev/null
    g sudo sh -c "echo 30 > $BL_HW"
    sleep 0.8
    f=$(bl_osd SB2-firmware)
    if [ "$(bl_daemon DisplayBrightness)" = 30 ] && gt "$(changed SB2-before SB2-firmware 445 548 835 600)" 0.2 && near "$f" 0.30; then
        ok "[brightness] a level the firmware set (the laptop's own key) shows in the OSD: 30% (bar $f)"
    else
        fail "[brightness] the firmware set 30: COSMIC has $(bl_daemon DisplayBrightness), OSD bar $f (SB2-firmware.png)"
    fi
    sleep 3
    # The power applet's slider shows the level and sets it.
    ctl click 1191 15
    sleep 2
    shot SB3-applet > /dev/null
    f=$(ctl fill "$OUT/SB3-applet.ppm" 993 1191 243)
    ctl click 1141 243                   # three quarters along
    sleep 1.5
    l=$(bl_now)
    ctl key esc
    sleep 1
    check "[brightness] the power applet's slider shows 30% (bar $f) and sets the level (75% gives $l)" \
        near "$f" 0.32 0.06 && [ "$l" -ge 72 ] && [ "$l" -le 78 ]
    sleep 2

    # A panel with 255 levels (amdgpu, as on most AMD laptops).
    bl_load restart bl_max=255 || return
    bl_set 128
    shot SB4-before > /dev/null
    l=$(bl_press BRIGHTNESSUP)
    f=$(bl_osd SB4-255)
    if [ "$l" = 140 ] && near "$f" 0.55; then
        ok "[brightness] 255 levels: Brightness Up raises 128 to 140 (the 55% step), the OSD shows 55% (bar $f)"
    else
        fail "[brightness] 255 levels: Brightness Up from 128 gives $l, OSD bar $f (SB4-255.png)"
    fi
    sleep 3
    bl_set 13
    l=$(bl_press BRIGHTNESSDOWN)
    l2=$(bl_press BRIGHTNESSUP)
    check "[brightness] 255 levels: Brightness Down from 13 stops at 1, Brightness Up goes back to 13 ($l, $l2)" \
        [ "$l" = 1 ] && [ "$l2" = 13 ]
    sleep 3

    # A coarse panel (10 levels, as some ACPI backlights): every level is a
    # step, and the lowest is 0, which COSMIC allows with 20 levels or fewer.
    bl_load restart bl_max=10 || return
    bl_set 2
    l=$(bl_press BRIGHTNESSDOWN)
    l2=$(bl_press BRIGHTNESSDOWN)
    f=$(bl_press BRIGHTNESSUP)
    check "[brightness] 10 levels: Brightness Down from 2 gives 1 then 0, Brightness Up 1 ($l, $l2, $f)" \
        [ "$l" = 1 ] && [ "$l2" = 0 ] && [ "$f" = 1 ]
    sleep 3

    # A panel that stays dark at its lowest levels (an OLED; here up to 3):
    # after a low level COSMIC raises it until it lights (actual_brightness).
    bl_load bl_max=100 bl_dark=3 || return
    bl_set 10
    l=$(bl_press BRIGHTNESSDOWN 2)
    l2=$(g cat "$BL/actual_brightness")
    check "[brightness] a panel dark up to level 3: Brightness Down to the lowest leaves level $l (lit: $l2), not a black screen" \
        [ "$l" = 4 ] && [ "$l2" = 4 ]
    sleep 3

    # Two backlights for one panel (firmware 100 levels, raw 255), as older
    # kernels left on some laptops. The kernel's documentation
    # (sysfs-class-backlight, "type") says to prefer firmware over platform
    # over raw; COSMIC takes the one with the most levels.
    bl_load restart bl_max=100 bl_type=firmware bl2_max=255 bl2_type=raw || return
    max=$(bl_daemon MaxDisplayBrightness)
    bl_set 50
    bl_set 128 "$BL2"
    l=$(bl_press BRIGHTNESSUP)
    l2=$(bl_now "$BL2")
    case "$max:$l:$l2" in
        100:55:128) ok "[brightness] two backlights: COSMIC uses the firmware one, as the kernel advises (firmware 50 -> 55, raw stays 128)" ;;
        255:50:140) known_issue "[brightness] two backlights: COSMIC uses the raw one (255 levels; 128 -> 140) and not the firmware one, which the kernel's documentation says to prefer (sysfs-class-backlight); recent kernels mostly register one per panel; not confirmed upstream" ;;
        *) fail "[brightness] two backlights: COSMIC's maximum $max, firmware $l (was 50), raw $l2 (was 128)" ;;
    esac
    sleep 3

    # A backlight that comes or changes while logged in (a driver loaded
    # later): cosmic-osd keeps the old maximum (here 255 for one of 100).
    bl_load bl_max=100 || return
    bl_set 50
    l=$(bl_press BRIGHTNESSUP)
    f=$(bl_osd SB5-later)
    if near "$f" 0.55; then
        ok "[brightness] a backlight that appears while logged in: the OSD shows its level (55%, bar $f)"
    elif [ "$l" = 55 ]; then
        known_issue "[brightness] a backlight that appears or changes while logged in: the OSD and the power applet keep the old maximum (55 of 100 shown as bar $f, as of 255) until they restart; the settings daemon announces the level, not MaxDisplayBrightness (SB5-later.png; not confirmed upstream)"
    else
        fail "[brightness] a backlight that appears while logged in: Brightness Up from 50 gives $l (SB5-later.png)"
    fi
    sleep 3
    hw_shell_restart

    # Kept over the reboot (boot 3): systemd-backlight saves the level at
    # shutdown and restores it when the device comes; the module loads at
    # boot for that (removed again in hw_brightness_after_reboot).
    bl_set 50
    l=$(bl_press BRIGHTNESSDOWN 3)
    g sudo install -D -m 0644 /tmp/vmbl/vmtest_backlight.ko "/lib/modules/$(g uname -r)/updates/vmtest_backlight.ko"
    g sudo depmod -a
    g sudo sh -c 'echo vmtest_backlight > /etc/modules-load.d/vmtest-backlight.conf'
    BL_SAVED=$l
    say "  the backlight stays at $l, loaded at boot too, for the check after the reboot"
}
BL_SAVED=
hw_brightness_after_reboot() {
    [ -n "$BL_SAVED" ] || return 0
    local l d
    l=$(bl_now 2> /dev/null)
    d=$(bl_daemon DisplayBrightness)
    check "[brightness] the level is kept over the reboot ($BL_SAVED before; now $l, COSMIC $d)" \
        [ "$l" = "$BL_SAVED" ] && [ "$d" = "$BL_SAVED" ]
    g sudo rm -f /etc/modules-load.d/vmtest-backlight.conf "/lib/modules/$(g uname -r)/updates/vmtest_backlight.ko"
    g sudo depmod -a
    g sudo rmmod vmtest_backlight 2> /dev/null && { g sudo systemctl restart upower; sleep 2; hw_shell_restart; }
}
hardware() {
    local hw_start
    hw_start=$(g date +%s)
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
    if hw_firefox_setup; then
        hw_firefox
    fi
    hw_firefox_cleanup
    if hw_kbd_setup; then
        hw_kbd_backlight
        hw_brightness
    fi
    # The module stays for the reboot when hw_brightness got that far.
    [ -n "$BL_SAVED" ] || hw_kbd_cleanup
    hw_input_stop
    # The simulation's own error lines (journal-hardware.txt) are accepted
    # only in this span; cleanup messages come a few seconds after.
    HW_WINDOWS+="$hw_start $(( $(g date +%s) + 10 ))"$'\n'
}
